import Foundation
import CryptoKit
import AuthenticationServices
import UIKit

// MARK: - OIDC 错误

enum OIDCError: LocalizedError {
    case missingCode
    case stateMismatch
    case tokenExchangeFailed(String)
    case userCancelled
    case sessionFailed(Error)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .missingCode:
            return "OIDC 授权回调缺少 code 参数"
        case .stateMismatch:
            return "OIDC state 不匹配，可能存在安全风险"
        case .tokenExchangeFailed(let msg):
            return "OIDC 令牌交换失败：\(msg)"
        case .userCancelled:
            return "用户取消了登录"
        case .sessionFailed(let err):
            return "浏览器会话启动失败：\(err.localizedDescription)"
        case .invalidURL:
            return "OIDC 服务地址无效"
        }
    }
}

// MARK: - OIDC 令牌响应

struct OIDCTokenResponse: Decodable {
    let accessToken: String
    let tokenType: String?
    let expiresIn: Int?
    let refreshToken: String?
    let idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
    }
}

// MARK: - OIDCManager

/// 管理 OIDC 授权码 + PKCE 登录流程。
///
/// 流程：
/// 1. 生成 PKCE code_verifier + code_challenge
/// 2. 用 ASWebAuthenticationSession 打开 OIDC 授权页面
/// 3. 用户在浏览器中输入 QQ 号 → Koishi 发验证链接 → 用户点击验证
/// 4. OIDC 回调 smsforwarder://oauth/callback?code=...&state=...
/// 5. 用 code + code_verifier 调 POST /token 换 access_token
/// 6. 将 access_token 发给面板 POST /api/auth/oidc 换面板 JWT
final class OIDCManager: NSObject, ASWebAuthenticationPresentationContextProviding {

    static let shared = OIDCManager()

    // OIDC 身份提供者地址（固定，用户只有这一个 OIDC 服务）
    private let issuer = "https://auth.xiaoyyua.top"

    // 注册的 OIDC 客户端信息
    private let clientID = "smsforwarder-ios"
    private let redirectURI = "smsforwarder://oauth/callback"
    private let scope = "openid profile qq offline_access"
    private let callbackScheme = "smsforwarder"

    // 当前 PKCE 状态（每次登录重新生成）
    private var codeVerifier: String = ""
    private var state: String = ""

    private override init() {
        super.init()
    }

    // MARK: - PKCE

    /// 生成 PKCE code_verifier（43-128 字符，base64url 编码的随机字节）
    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64url(Data(bytes))
    }

    /// 从 code_verifier 计算 code_challenge (S256)
    private func generateCodeChallenge(verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return base64url(Data(hash))
    }

    /// base64url 编码（无 padding）
    private func base64url(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - 授权 URL 构建

    /// 构建 OIDC 授权 URL（带 PKCE）
    private func buildAuthURL() throws -> URL {
        codeVerifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(verifier: codeVerifier)
        state = UUID().uuidString

        var components = URLComponents(string: issuer)
        components?.path = "/auth"

        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]

        guard let url = components?.url else {
            throw OIDCError.invalidURL
        }
        return url
    }

    // MARK: - 启动 OIDC 登录

    /// 启动完整 OIDC 登录流程，返回面板 JWT。
    ///
    /// - Parameter panelURL: 面板地址（用于调 /api/auth/oidc 换 JWT）
    /// - Returns: 面板 JWT token
    func startOIDCLogin(panelURL: String) async throws -> (jwt: String, username: String) {
        // 1. 构建授权 URL
        let authURL = try buildAuthURL()

        // 2. 启动 ASWebAuthenticationSession 等待回调
        let callbackURL = try await openAuthSession(url: authURL)

        // 3. 从回调 URL 提取 code 和 state
        let code = try extractCode(from: callbackURL)

        // 4. 用 code + verifier 换 access_token
        let tokenResp = try await exchangeCodeForToken(code: code)

        // 5. 用 access_token 调面板换 JWT
        let (jwt, username) = try await exchangeTokenForPanelJWT(
            accessToken: tokenResp.accessToken,
            panelURL: panelURL
        )

        return (jwt, username)
    }

    // MARK: - ASWebAuthenticationSession

    /// 启动 ASWebAuthenticationSession，等待用户完成授权后返回回调 URL
    @MainActor
    private func openAuthSession(url: URL) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error = error {
                    if let asError = error as? ASWebAuthenticationSessionError,
                       asError.code == .canceledLogin {
                        continuation.resume(throwing: OIDCError.userCancelled)
                    } else {
                        continuation.resume(throwing: OIDCError.sessionFailed(error))
                    }
                    return
                }
                guard let callbackURL = callbackURL else {
                    continuation.resume(throwing: OIDCError.sessionFailed(
                        NSError(domain: "OIDC", code: -1, userInfo: [NSLocalizedDescriptionKey: "回调 URL 为空"])
                    ))
                    return
                }
                continuation.resume(returning: callbackURL)
            }

            // 需要设置 presentationContextProvider
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false

            if !session.start() {
                continuation.resume(throwing: OIDCError.sessionFailed(
                    NSError(domain: "OIDC", code: -2, userInfo: [NSLocalizedDescriptionKey: "无法启动浏览器会话"])
                ))
            }
        }
    }

    // MARK: - 回调解析

    /// 从回调 URL 提取 code 并验证 state
    private func extractCode(from url: URL) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            throw OIDCError.missingCode
        }

        // 检查是否有 error 参数（OIDC 授权失败）
        if let error = queryItems.first(where: { $0.name == "error" })?.value, !error.isEmpty {
            let desc = queryItems.first(where: { $0.name == "error_description" })?.value ?? error
            throw OIDCError.tokenExchangeFailed("授权失败：\(desc)")
        }

        // 验证 state
        let returnedState = queryItems.first(where: { $0.name == "state" })?.value
        guard returnedState == state else {
            throw OIDCError.stateMismatch
        }

        // 提取 code
        guard let code = queryItems.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw OIDCError.missingCode
        }

        return code
    }

    // MARK: - Token 交换

    /// 用授权码 + PKCE verifier 换 access_token
    private func exchangeCodeForToken(code: String) async throws -> OIDCTokenResponse {
        guard var components = URLComponents(string: issuer) else {
            throw OIDCError.invalidURL
        }
        components.path = "/token"
        guard let tokenURL = components.url else {
            throw OIDCError.invalidURL
        }

        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15

        let params = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": codeVerifier
        ]

        let bodyString = params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }.joined(separator: "&")
        req.httpBody = bodyString.data(using: .utf8)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw OIDCError.tokenExchangeFailed("网络请求失败：\(error.localizedDescription)")
        }

        guard let http = response as? HTTPURLResponse else {
            throw OIDCError.tokenExchangeFailed("服务器响应异常")
        }

        if http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OIDCError.tokenExchangeFailed("HTTP \(http.statusCode): \(body)")
        }

        do {
            return try JSONDecoder().decode(OIDCTokenResponse.self, from: data)
        } catch {
            throw OIDCError.tokenExchangeFailed("解析令牌响应失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 面板 JWT 交换

    /// 用 OIDC access_token 调面板 POST /api/auth/oidc 换面板 JWT
    private func exchangeTokenForPanelJWT(accessToken: String, panelURL: String) async throws -> (String, String) {
        guard !panelURL.isEmpty else {
            throw APIError.invalidURL
        }

        var components = URLComponents(string: panelURL)
        var basePath = components?.path ?? ""
        if basePath.hasSuffix("/") { basePath.removeLast() }
        components?.path = basePath + "/api/auth/oidc"

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15

        let body: [String: Any] = ["access_token": accessToken]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (rawData, response): (Data, URLResponse)
        do {
            (rawData, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.invalidResponse
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if let errorResp = try? JSONDecoder().decode(APIResponse<EmptyData>.self, from: rawData) {
                throw APIError.businessError(code: errorResp.code, message: errorResp.msg)
            }
            throw APIError.httpError(http.statusCode)
        }

        struct PanelLoginData: Decodable {
            let token: String
            let id: Int?
            let username: String?
            let remark: String?
        }

        let decoded = try JSONDecoder().decode(APIResponse<PanelLoginData>.self, from: rawData)
        if !decoded.isSuccess {
            throw APIError.businessError(code: decoded.code, message: decoded.msg)
        }
        guard let jwt = decoded.data?.token, !jwt.isEmpty else {
            throw APIError.decodeError("面板响应中缺少 token")
        }
        let username = decoded.data?.username ?? "OIDC用户"
        return (jwt, username)
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // 返回当前活跃的 key window
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
           let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first {
            return window
        }
        return ASPresentationAnchor()
    }
}
