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

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Web 面板地址无效，请在设置中检查服务器地址。"
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
        }
    }
}

// MARK: - SmsForwarderAPI

/// Web 面板 API 网络层
/// 通过 Flask 面板的 JSON API 获取数据，不再直接连设备
final class SmsForwarderAPI {
    static let shared = SmsForwarderAPI()

    private let session: URLSession
    private let settingsStore: SettingsStore

    init(session: URLSession = .shared, settingsStore: SettingsStore = .shared) {
        self.session = session
        self.settingsStore = settingsStore
    }

    // MARK: - URL 构建

    /// 构建 Flask API 的完整 URL
    /// - Parameters:
    ///   - path: API 路径，如 "config"（会拼接为 /api/config）
    ///   - queryItems: URL 查询参数
    /// - Returns: 构建好的 URL
    private func buildURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        let settings = settingsStore.settings
        guard !settings.serverURL.isEmpty else {
            throw APIError.invalidURL
        }

        var components = URLComponents(string: settings.serverURL)
        // 规范化路径：去掉尾部斜杠，避免拼接出 //api/xxx
        var basePath = components?.path ?? ""
        if basePath.hasSuffix("/") {
            basePath.removeLast()
        }
        components?.path = basePath + "/api/\(path)"
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }

        guard let url = components?.url else {
            throw APIError.invalidURL
        }
        return url
    }

    // MARK: - 统一请求

    /// 统一 GET 请求封装
    /// - Parameters:
    ///   - path: API 路径，如 "config"（会拼接为 /api/config）
    ///   - queryItems: URL 查询参数
    /// - Returns: 解码后的 APIResponse<T>
    func get<T: Decodable>(path: String, queryItems: [URLQueryItem] = []) async throws -> APIResponse<T> {
        let url = try buildURL(path: path, queryItems: queryItems)

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 15

        return try await perform(req)
    }

    /// 统一 POST 请求封装
    /// - Parameters:
    ///   - path: API 路径，如 "sms/send"（会拼接为 /api/sms/send）
    ///   - body: 请求体参数
    /// - Returns: 解码后的 APIResponse<T>
    func post<T: Decodable>(path: String, body: [String: Any] = [:]) async throws -> APIResponse<T> {
        let url = try buildURL(path: path)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15

        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            throw APIError.decodeError("请求体序列化失败：\(error.localizedDescription)")
        }

        return try await perform(req)
    }

    /// 执行请求并解码响应
    private func perform<T: Decodable>(_ req: URLRequest) async throws -> APIResponse<T> {
        let (rawData, response): (Data, URLResponse)
        do {
            (rawData, response) = try await session.data(for: req)
        } catch {
            throw APIError.invalidResponse
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.httpError(http.statusCode)
        }

        do {
            let decoded = try JSONDecoder().decode(APIResponse<T>.self, from: rawData)
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

    // MARK: - 业务方法

    /// 查询设备配置
    func queryConfig() async throws -> DeviceConfig {
        let resp: APIResponse<DeviceConfig> = try await get(path: "config")
        return resp.data ?? DeviceConfig()
    }

    /// 发送短信
    /// - Parameters:
    ///   - simSlot: 1=SIM1, 2=SIM2
    ///   - phoneNumbers: 多号码分号分隔
    ///   - msgContent: 短信内容
    func sendSMS(simSlot: Int, phoneNumbers: String, msgContent: String) async throws -> String {
        struct EmptyResult: Decodable {}
        let body: [String: Any] = [
            "sim_slot": simSlot,
            "phone_numbers": phoneNumbers,
            "msg_content": msgContent
        ]
        let resp: APIResponse<EmptyResult> = try await post(path: "sms/send", body: body)
        return resp.msg ?? "发送成功"
    }

    /// 查询短信列表
    /// - Parameters:
    ///   - type: 1=接收, 2=发送
    ///   - pageNum: 页码
    ///   - pageSize: 每页数量
    ///   - keyword: 关键字
    func querySMS(type: Int, pageNum: Int, pageSize: Int, keyword: String) async throws -> [SmsRecord] {
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "type", value: String(type)),
            URLQueryItem(name: "page_num", value: String(pageNum)),
            URLQueryItem(name: "page_size", value: String(pageSize)),
            URLQueryItem(name: "keyword", value: keyword)
        ]
        return try await fetchList(path: "sms", queryItems: queryItems)
    }

    /// 查询通话列表
    /// - Parameters:
    ///   - type: 0=全部, 1=呼入, 2=呼出, 3=未接
    ///   - phoneNumber: 号码
    ///   - pageNum: 页码
    ///   - pageSize: 每页数量
    func queryCalls(type: Int, phoneNumber: String, pageNum: Int, pageSize: Int) async throws -> [CallRecord] {
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "type", value: String(type)),
            URLQueryItem(name: "page_num", value: String(pageNum)),
            URLQueryItem(name: "page_size", value: String(pageSize)),
            URLQueryItem(name: "phone_number", value: phoneNumber)
        ]
        return try await fetchList(path: "calls", queryItems: queryItems)
    }

    /// 查询联系人
    func queryContacts(phoneNumber: String, name: String) async throws -> [Contact] {
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "phone_number", value: phoneNumber),
            URLQueryItem(name: "name", value: name)
        ]
        return try await fetchList(path: "contacts", queryItems: queryItems)
    }

    /// 添加联系人
    func addContact(phoneNumber: String, name: String) async throws -> String {
        struct EmptyResult: Decodable {}
        let body: [String: Any] = [
            "phone_number": phoneNumber,
            "name": name
        ]
        let resp: APIResponse<EmptyResult> = try await post(path: "contacts/add", body: body)
        return resp.msg ?? "添加成功"
    }

    /// 查询电量
    func queryBattery() async throws -> BatteryInfo {
        let resp: APIResponse<BatteryInfo> = try await get(path: "battery")
        return resp.data ?? BatteryInfo(level: nil, status: nil, health: nil, plugged: nil, voltage: nil, temperature: nil)
    }

    /// 远程唤醒 (Wake-On-LAN)
    func sendWOL(mac: String, ip: String, port: Int) async throws -> String {
        struct EmptyResult: Decodable {}
        let body: [String: Any] = [
            "mac": mac,
            "ip": ip,
            "port": port
        ]
        let resp: APIResponse<EmptyResult> = try await post(path: "wol", body: body)
        return resp.msg ?? "唤醒指令已发送"
    }

    /// 查询定位
    func queryLocation() async throws -> LocationInfo {
        let resp: APIResponse<LocationInfo> = try await get(path: "location")
        return resp.data ?? LocationInfo(address: nil, latitude: nil, longitude: nil, time: nil, provider: nil)
    }

    // MARK: - 列表通用解析

    /// 后端可能以 data 字段直接返回数组，也可能包在 { "data": { "list": [...] } } 中。
    /// 此方法优先按数组解析，失败再尝试 list 字段解析，最后尝试空 data 兜底。
    private func fetchList<T: Decodable>(path: String, queryItems: [URLQueryItem]) async throws -> [T] {
        let url = try buildURL(path: path, queryItems: queryItems)

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 15

        let (rawData, response) = try await session.data(for: req)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.httpError(http.statusCode)
        }

        // 先尝试直接解析 APIResponse<[T]>
        if let arrResp = try? JSONDecoder().decode(APIResponse<[T]>.self, from: rawData) {
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

        // 最终兜底：返回空数组
        return []
    }
}
