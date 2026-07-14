import Foundation
import CryptoKit
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
            return "设备地址无效，请在设置中检查 IP 与端口。"
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

/// SmsForwarder 设备 API 网络层
/// 负责生成签名、发起 POST 请求、解码响应
final class SmsForwarderAPI {
    static let shared = SmsForwarderAPI()

    private let session: URLSession
    private let settingsStore: SettingsStore

    init(session: URLSession = .shared, settingsStore: SettingsStore = .shared) {
        self.session = session
        self.settingsStore = settingsStore
    }

    // MARK: - 签名生成

    /// 生成请求签名
    /// 1. sign_str = "{timestamp}\n{secret_key}"
    /// 2. HMAC-SHA256(key=secret_key.utf8, msg=sign_str.utf8) -> Data
    /// 3. base64 编码 -> String
    /// 4. 对该字符串做 URL 编码 -> 最终 sign
    func generateSign(timestamp: Int64, secretKey: String) -> String {
        let signStr = "\(timestamp)\n\(secretKey)"
        let keyData = Data(secretKey.utf8)
        let msgData = Data(signStr.utf8)
        let mac = HMAC<SHA256>.authenticationCode(for: msgData, using: SymmetricKey(data: keyData))
        let base64Str = Data(mac).base64EncodedString()
        // URL 编码（percent encoding）
        return base64Str.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? base64Str
    }

    // MARK: - 统一请求

    /// 统一 POST 请求封装
    /// - Parameters:
    ///   - endpoint: 接口端点，如 "config/query"
    ///   - data: 业务参数（可空，默认空字典）
    /// - Returns: 解码后的 APIResponse<T>
    func request<T: Decodable>(endpoint: String, data: [String: Any] = [:]) async throws -> APIResponse<T> {
        let settings = settingsStore.settings
        guard !settings.deviceIP.isEmpty, settings.devicePort > 0 else {
            throw APIError.invalidURL
        }

        let urlString = "http://\(settings.deviceIP):\(settings.devicePort)/\(endpoint)"
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }

        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let sign = generateSign(timestamp: timestamp, secretKey: settings.secretKey)

        let payload: [String: Any] = [
            "timestamp": timestamp,
            "sign": sign,
            "data": data
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15

        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            throw APIError.decodeError("请求体序列化失败：\(error.localizedDescription)")
        }

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
        let resp: APIResponse<DeviceConfig> = try await request(endpoint: "config/query")
        return resp.data ?? DeviceConfig()
    }

    /// 发送短信
    /// - Parameters:
    ///   - simSlot: 1=SIM1, 2=SIM2
    ///   - phoneNumbers: 多号码分号分隔
    ///   - msgContent: 短信内容
    func sendSMS(simSlot: Int, phoneNumbers: String, msgContent: String) async throws -> String {
        struct EmptyResult: Decodable {}
        let data: [String: Any] = [
            "sim_slot": simSlot,
            "phone_numbers": phoneNumbers,
            "msg_content": msgContent
        ]
        let resp: APIResponse<EmptyResult> = try await request(endpoint: "sms/send", data: data)
        return resp.msg ?? "发送成功"
    }

    /// 查询短信列表
    /// - Parameters:
    ///   - type: 1=接收, 2=发送
    ///   - pageNum: 页码
    ///   - pageSize: 每页数量
    ///   - keyword: 关键字
    func querySMS(type: Int, pageNum: Int, pageSize: Int, keyword: String) async throws -> [SmsRecord] {
        let data: [String: Any] = [
            "type": type,
            "page_num": pageNum,
            "page_size": pageSize,
            "keyword": keyword
        ]
        // 后端可能在 data 中直接返回数组，也可能包在某个字段中；统一兼容两种情况
        return try await fetchList(endpoint: "sms/query", data: data)
    }

    /// 查询通话列表
    /// - Parameters:
    ///   - type: 0=全部, 1=呼入, 2=呼出, 3=未接
    ///   - phoneNumber: 号码
    ///   - pageNum: 页码
    ///   - pageSize: 每页数量
    func queryCalls(type: Int, phoneNumber: String, pageNum: Int, pageSize: Int) async throws -> [CallRecord] {
        let data: [String: Any] = [
            "type": type,
            "phone_number": phoneNumber,
            "page_num": pageNum,
            "page_size": pageSize
        ]
        return try await fetchList(endpoint: "call/query", data: data)
    }

    /// 查询联系人
    func queryContacts(phoneNumber: String, name: String) async throws -> [Contact] {
        let data: [String: Any] = [
            "phone_number": phoneNumber,
            "name": name
        ]
        return try await fetchList(endpoint: "contact/query", data: data)
    }

    /// 添加联系人
    func addContact(phoneNumber: String, name: String) async throws -> String {
        struct EmptyResult: Decodable {}
        let data: [String: Any] = [
            "phone_number": phoneNumber,
            "name": name
        ]
        let resp: APIResponse<EmptyResult> = try await request(endpoint: "contact/add", data: data)
        return resp.msg ?? "添加成功"
    }

    /// 查询电量
    func queryBattery() async throws -> BatteryInfo {
        let resp: APIResponse<BatteryInfo> = try await request(endpoint: "battery/query")
        return resp.data ?? BatteryInfo(level: nil, status: nil, health: nil, plugged: nil, voltage: nil, temperature: nil)
    }

    /// 远程唤醒 (Wake-On-LAN)
    func sendWOL(mac: String, ip: String, port: Int) async throws -> String {
        struct EmptyResult: Decodable {}
        let data: [String: Any] = [
            "mac": mac,
            "ip": ip,
            "port": port
        ]
        let resp: APIResponse<EmptyResult> = try await request(endpoint: "wol/send", data: data)
        return resp.msg ?? "唤醒指令已发送"
    }

    /// 查询定位
    func queryLocation() async throws -> LocationInfo {
        let resp: APIResponse<LocationInfo> = try await request(endpoint: "location/query")
        return resp.data ?? LocationInfo(address: nil, latitude: nil, longitude: nil, time: nil, provider: nil)
    }

    // MARK: - 列表通用解析

    /// 后端可能以 data 字段直接返回数组，也可能包在 { "data": { "list": [...] } } 中。
    /// 此方法优先按数组解析，失败再尝试 list 字段解析，最后尝试空 data 兜底。
    private func fetchList<T: Decodable>(endpoint: String, data: [String: Any]) async throws -> [T] {
        let settings = settingsStore.settings
        guard !settings.deviceIP.isEmpty, settings.devicePort > 0 else {
            throw APIError.invalidURL
        }

        let urlString = "http://\(settings.deviceIP):\(settings.devicePort)/\(endpoint)"
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }

        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let sign = generateSign(timestamp: timestamp, secretKey: settings.secretKey)
        let payload: [String: Any] = [
            "timestamp": timestamp,
            "sign": sign,
            "data": data
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

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
