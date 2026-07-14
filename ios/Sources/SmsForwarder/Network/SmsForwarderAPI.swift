import Foundation
import Observation

// MARK: - API 错误

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case decodeError(String)
    case businessError(code: Int, message: String?)
    case emptyData
    case authRequired
    case noDeviceSelected

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "面板地址无效，请在设置中检查服务器地址。"
        case .invalidResponse:
            return "服务器响应格式异常。"
        case .httpError(let code):
            return "网络请求失败（HTTP \(code)）。"
        case .decodeError(let msg):
            return "数据解析失败：\(msg)"
        case .businessError(let code, let message):
            return message ?? "业务错误（code=\(code)）"
        case .emptyData:
            return "服务器未返回数据。"
        case .authRequired:
            return "登录已过期，请重新登录。"
        case .noDeviceSelected:
            return "请先在设备管理中选择一台设备。"
        }
    }
}

// MARK: - SmsForwarderAPI

/// Go 面板 API 网络层
/// 通过 Go 面板的 JSON API 获取数据，面板内部代理转发到 SmsForwarder 设备
final class SmsForwarderAPI {
    static let shared = SmsForwarderAPI()

    private let session: URLSession
    private let settingsStore: SettingsStore
    private let deviceStore: DeviceStore

    init(session: URLSession = .shared, settingsStore: SettingsStore = .shared, deviceStore: DeviceStore = .shared) {
        self.session = session
        self.settingsStore = settingsStore
        self.deviceStore = deviceStore
    }

    // MARK: - URL 构建

    /// 构建面板 API URL（如 /api/auth/login, /api/devices）
    private func buildAPIURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        let settings = settingsStore.settings
        guard !settings.serverURL.isEmpty else {
            throw APIError.invalidURL
        }

        var components = URLComponents(string: settings.serverURL)
        var basePath = components?.path ?? ""
        if basePath.hasSuffix("/") { basePath.removeLast() }
        components?.path = basePath + "/api/\(path)"
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }

        guard let url = components?.url else {
            throw APIError.invalidURL
        }
        return url
    }

    /// 构建设备代理 URL（如 /api/device/1/proxy/sms/query）
    private func buildProxyURL(deviceId: Int, path: String) throws -> URL {
        let settings = settingsStore.settings
        guard !settings.serverURL.isEmpty else {
            throw APIError.invalidURL
        }

        var components = URLComponents(string: settings.serverURL)
        var basePath = components?.path ?? ""
        if basePath.hasSuffix("/") { basePath.removeLast() }
        // path 形如 "/sms/query"，直接拼接
        let proxyPath = path.hasPrefix("/") ? path : "/" + path
        components?.path = basePath + "/api/device/\(deviceId)/proxy\(proxyPath)"

        guard let url = components?.url else {
            throw APIError.invalidURL
        }
        return url
    }

    // MARK: - 统一请求

    /// 面板 API GET 请求
    func get<T: Decodable>(path: String, queryItems: [URLQueryItem] = []) async throws -> APIResponse<T> {
        let url = try buildAPIURL(path: path, queryItems: queryItems)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 15
        return try await perform(req)
    }

    /// 面板 API POST 请求
    func post<T: Decodable>(path: String, body: [String: Any] = [:]) async throws -> APIResponse<T> {
        let url = try buildAPIURL(path: path)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        if !body.isEmpty {
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        }
        return try await perform(req)
    }

    /// 执行面板 API 请求（自动附加认证 header）
    private func perform<T: Decodable>(_ req: URLRequest) async throws -> APIResponse<T> {
        var req = req
        if let token = settingsStore.settings.token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (rawData, response): (Data, URLResponse)
        do {
            (rawData, response) = try await session.data(for: req)
        } catch {
            throw APIError.invalidResponse
        }

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 {
                throw APIError.authRequired
            }
            if !(200..<300).contains(http.statusCode) {
                throw APIError.httpError(http.statusCode)
            }
        }

        do {
            let decoded = try JSONDecoder().decode(APIResponse<T>.self, from: rawData)
            if decoded.code == 401 {
                throw APIError.authRequired
            }
            return decoded
        } catch let err as APIError {
            throw err
        } catch {
            throw APIError.decodeError(error.localizedDescription)
        }
    }

    // MARK: - 设备代理调用

    /// 通过面板代理调用设备 API
    /// - Parameters:
    ///   - path: 设备 API 路径，如 "/sms/query"
    ///   - body: 请求参数
    /// - Returns: 解码后的 APIResponse<T>
    func proxyCall<T: Decodable>(path: String, body: [String: Any] = [:]) async throws -> APIResponse<T> {
        guard let deviceId = deviceStore.currentDeviceId else {
            throw APIError.noDeviceSelected
        }

        let url = try buildProxyURL(deviceId: deviceId, path: path)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30 // 代理调用可能较慢
        if let token = settingsStore.settings.token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (rawData, response): (Data, URLResponse)
        do {
            (rawData, response) = try await session.data(for: req)
        } catch {
            throw APIError.invalidResponse
        }

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 {
                throw APIError.authRequired
            }
            if !(200..<300).contains(http.statusCode) {
                throw APIError.httpError(http.statusCode)
            }
        }

        do {
            let decoded = try JSONDecoder().decode(APIResponse<T>.self, from: rawData)
            if decoded.code == 401 {
                throw APIError.authRequired
            }
            if !decoded.isSuccess {
                throw APIError.businessError(code: decoded.code, message: decoded.msg)
            }
            return decoded
        } catch let err as APIError {
            throw err
        } catch {
            throw APIError.decodeError(error.localizedDescription)
        }
    }

    /// 代理调用并返回列表数据（兼容 data 为数组或 {list: [...]} 的情况）
    private func proxyFetchList<T: Decodable>(path: String, body: [String: Any] = [:]) async throws -> [T] {
        guard let deviceId = deviceStore.currentDeviceId else {
            throw APIError.noDeviceSelected
        }

        let url = try buildProxyURL(deviceId: deviceId, path: path)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        if let token = settingsStore.settings.token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (rawData, response) = try await session.data(for: req)

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 {
                throw APIError.authRequired
            }
            if !(200..<300).contains(http.statusCode) {
                throw APIError.httpError(http.statusCode)
            }
        }

        // 先尝试直接解析 APIResponse<[T]>
        if let arrResp = try? JSONDecoder().decode(APIResponse<[T]>.self, from: rawData) {
            if arrResp.code == 401 {
                throw APIError.authRequired
            }
            if !arrResp.isSuccess {
                throw APIError.businessError(code: arrResp.code, message: arrResp.msg)
            }
            return arrResp.data ?? []
        }

        // 再尝试解析 { code, msg, data: { list: [...] } }
        if let jsonObj = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any],
           let code = jsonObj["code"] as? Int, code == 200,
           let dataObj = jsonObj["data"] as? [String: Any],
           let listObj = dataObj["list"] {
            let listData = try JSONSerialization.data(withJSONObject: listObj, options: [])
            let list = try JSONDecoder().decode([T].self, from: listData)
            return list
        }

        return []
    }

    // MARK: - 认证

    /// 获取 Turnstile 配置
    func fetchTurnstileConfig(serverURL: String) async throws -> TurnstileConfig {
        guard !serverURL.isEmpty else { throw APIError.invalidURL }

        var components = URLComponents(string: serverURL)
        var basePath = components?.path ?? ""
        if basePath.hasSuffix("/") { basePath.removeLast() }
        components?.path = basePath + "/api/auth/turnstile"

        guard let url = components?.url else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 10

        let (rawData, response) = try await session.data(for: req)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.httpError(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(APIResponse<TurnstileConfig>.self, from: rawData)
        return decoded.data ?? TurnstileConfig(enabled: false, siteKey: "")
    }

    /// 登录认证
    /// - Parameters:
    ///   - username: 用户名
    ///   - password: 密码
    ///   - turnstileToken: Turnstile 人机验证 token（如启用）
    ///   - serverURL: 面板地址
    /// - Returns: 登录成功后的 token
    func login(username: String, password: String, turnstileToken: String, serverURL: String) async throws -> String {
        guard !serverURL.isEmpty else { throw APIError.invalidURL }

        var components = URLComponents(string: serverURL)
        var basePath = components?.path ?? ""
        if basePath.hasSuffix("/") { basePath.removeLast() }
        components?.path = basePath + "/api/auth/login"

        guard let url = components?.url else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15

        let body: [String: Any] = [
            "username": username,
            "password": password,
            "turnstile_token": turnstileToken
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (rawData, response) = try await session.data(for: req)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // 尝试解析错误消息
            if let errorResp = try? JSONDecoder().decode(APIResponse<EmptyData>.self, from: rawData) {
                throw APIError.businessError(code: errorResp.code, message: errorResp.msg)
            }
            throw APIError.httpError(http.statusCode)
        }

        struct LoginData: Decodable {
            let token: String
            let id: Int?
            let username: String?
            let remark: String?
        }

        let decoded = try JSONDecoder().decode(APIResponse<LoginData>.self, from: rawData)
        if !decoded.isSuccess {
            throw APIError.businessError(code: decoded.code, message: decoded.msg)
        }
        guard let token = decoded.data?.token, !token.isEmpty else {
            throw APIError.decodeError("登录响应中缺少 token")
        }
        return token
    }

    /// 获取用户信息
    func fetchProfile() async throws -> UserProfile {
        let resp: APIResponse<UserProfile> = try await get(path: "auth/profile")
        return resp.data ?? UserProfile(id: nil, username: nil, remark: nil)
    }

    // MARK: - 设备管理

    /// 获取设备列表
    func fetchDevices() async throws -> [Device] {
        let resp: APIResponse<[Device]> = try await get(path: "devices")
        return resp.data ?? []
    }

    /// 检查设备健康状态（面板级别）
    func checkDeviceHealth(deviceId: Int) async throws -> DeviceHealth {
        let resp: APIResponse<DeviceHealth> = try await get(path: "device/\(deviceId)/health")
        return resp.data ?? DeviceHealth(online: false, duration_ms: 0)
    }

    // MARK: - 设备代理业务方法

    /// 查询设备配置（通过代理）
    func queryConfig() async throws -> DeviceConfig {
        let resp: APIResponse<DeviceConfig> = try await proxyCall(path: "/config/query", body: [:])
        return resp.data ?? DeviceConfig()
    }

    /// 检查设备在线状态（通过代理）
    func checkProxyHealth() async throws -> Bool {
        struct HealthData: Decodable {
            let online: Bool?
        }
        let resp: APIResponse<HealthData> = try await proxyCall(path: "/health", body: [:])
        return resp.data?.online ?? false
    }

    /// 发送短信（通过代理）
    func sendSMS(simSlot: Int, phoneNumbers: String, msgContent: String) async throws -> String {
        struct EmptyResult: Decodable {}
        let body: [String: Any] = [
            "sim_slot": simSlot,
            "phone_numbers": phoneNumbers,
            "msg_content": msgContent
        ]
        let resp: APIResponse<EmptyResult> = try await proxyCall(path: "/sms/send", body: body)
        return resp.msg ?? "发送成功"
    }

    /// 查询短信列表（通过代理）
    func querySMS(type: Int, pageNum: Int, pageSize: Int, keyword: String) async throws -> [SmsRecord] {
        let body: [String: Any] = [
            "type": type,
            "page_num": pageNum,
            "page_size": pageSize,
            "keyword": keyword
        ]
        return try await proxyFetchList(path: "/sms/query", body: body)
    }

    /// 查询通话列表（通过代理）
    func queryCalls(type: Int, phoneNumber: String, pageNum: Int, pageSize: Int) async throws -> [CallRecord] {
        let body: [String: Any] = [
            "type": type,
            "phone_number": phoneNumber,
            "page_num": pageNum,
            "page_size": pageSize
        ]
        return try await proxyFetchList(path: "/call/query", body: body)
    }

    /// 查询联系人（通过代理）
    func queryContacts(phoneNumber: String, name: String) async throws -> [Contact] {
        let body: [String: Any] = [
            "phone_number": phoneNumber,
            "name": name
        ]
        return try await proxyFetchList(path: "/contact/query", body: body)
    }

    /// 添加联系人（通过代理）
    func addContact(phoneNumber: String, name: String) async throws -> String {
        struct EmptyResult: Decodable {}
        let body: [String: Any] = [
            "phone_number": phoneNumber,
            "name": name
        ]
        let resp: APIResponse<EmptyResult> = try await proxyCall(path: "/contact/add", body: body)
        return resp.msg ?? "添加成功"
    }

    /// 查询电量（通过代理）
    func queryBattery() async throws -> BatteryInfo {
        let resp: APIResponse<BatteryInfo> = try await proxyCall(path: "/battery/query", body: [:])
        return resp.data ?? BatteryInfo(level: nil, status: nil, health: nil, plugged: nil, voltage: nil, temperature: nil)
    }

    /// 远程唤醒（通过代理）
    func sendWOL(mac: String, ip: String, port: Int) async throws -> String {
        struct EmptyResult: Decodable {}
        let body: [String: Any] = [
            "mac": mac,
            "ip": ip,
            "port": port
        ]
        let resp: APIResponse<EmptyResult> = try await proxyCall(path: "/wol/send", body: body)
        return resp.msg ?? "唤醒指令已发送"
    }

    /// 查询定位（通过代理）
    func queryLocation() async throws -> LocationInfo {
        let resp: APIResponse<LocationInfo> = try await proxyCall(path: "/location/query", body: [:])
        return resp.data ?? LocationInfo(address: nil, latitude: nil, longitude: nil, time: nil, provider: nil)
    }
}

// MARK: - 空数据类型

struct EmptyData: Decodable {}
