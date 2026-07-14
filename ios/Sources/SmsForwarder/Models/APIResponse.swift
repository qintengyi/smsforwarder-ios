import Foundation

// MARK: - 通用响应

/// 后端统一响应结构
/// - code: 200 表示成功
/// - msg: 提示信息
/// - data: 业务数据（泛型）
struct APIResponse<T: Decodable>: Decodable {
    let code: Int
    let msg: String?
    let data: T?

    var isSuccess: Bool { code == 200 }
}

// MARK: - 设备配置

/// config/query 返回的设备配置信息
/// 字段采用可选声明，后端可能不返回全部字段
struct DeviceConfig: Codable {
    var deviceModel: String? = nil
    var androidVersion: String? = nil
    var appVersion: String? = nil
    var sim1State: String? = nil
    var sim2State: String? = nil
    var heartbeatInterval: Int? = nil
    var batteryLevel: Int? = nil
    var batteryStatus: String? = nil
    var locationAddress: String? = nil
    var locationTime: Int64? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil
    var forwardRules: [String]? = nil
    var webhookUrl: String? = nil
    var pushToken: String? = nil
    var serverIp: String? = nil
    var serverPort: Int? = nil
    var uptime: Int64? = nil
    var createTime: Int64? = nil

    enum CodingKeys: String, CodingKey {
        case deviceModel = "device_model"
        case androidVersion = "android_version"
        case appVersion = "app_version"
        case sim1State = "sim1_state"
        case sim2State = "sim2_state"
        case heartbeatInterval = "heartbeat_interval"
        case batteryLevel = "battery_level"
        case batteryStatus = "battery_status"
        case locationAddress = "location_address"
        case locationTime = "location_time"
        case latitude
        case longitude
        case forwardRules = "forward_rules"
        case webhookUrl = "webhook_url"
        case pushToken = "push_token"
        case serverIp = "server_ip"
        case serverPort = "server_port"
        case uptime
        case createTime = "create_time"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deviceModel = try? c.decodeIfPresent(String.self, forKey: .deviceModel)
        androidVersion = try? c.decodeIfPresent(String.self, forKey: .androidVersion)
        appVersion = try? c.decodeIfPresent(String.self, forKey: .appVersion)
        sim1State = try? c.decodeIfPresent(String.self, forKey: .sim1State)
        sim2State = try? c.decodeIfPresent(String.self, forKey: .sim2State)
        heartbeatInterval = c.decodeFlexibleInt(forKey: .heartbeatInterval)
        batteryLevel = c.decodeFlexibleInt(forKey: .batteryLevel)
        batteryStatus = try? c.decodeIfPresent(String.self, forKey: .batteryStatus)
        locationAddress = try? c.decodeIfPresent(String.self, forKey: .locationAddress)
        locationTime = c.decodeFlexibleInt64(forKey: .locationTime)
        latitude = c.decodeFlexibleDouble(forKey: .latitude)
        longitude = c.decodeFlexibleDouble(forKey: .longitude)
        // forwardRules 可能是字符串数组，也可能是其他类型，用 try? 安全解码
        forwardRules = try? c.decodeIfPresent([String].self, forKey: .forwardRules)
        webhookUrl = try? c.decodeIfPresent(String.self, forKey: .webhookUrl)
        pushToken = try? c.decodeIfPresent(String.self, forKey: .pushToken)
        serverIp = try? c.decodeIfPresent(String.self, forKey: .serverIp)
        serverPort = c.decodeFlexibleInt(forKey: .serverPort)
        uptime = c.decodeFlexibleInt64(forKey: .uptime)
        createTime = c.decodeFlexibleInt64(forKey: .createTime)
    }
}

// MARK: - 短信记录

/// sms/query 返回的单条短信记录
struct SmsRecord: Codable, Identifiable {
    let name: String?
    let number: String?
    let content: String?
    /// 毫秒时间戳，兼容数字或字符串
    let date: Int64?
    /// 0=SIM1, 1=SIM2
    let sim_id: Int?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        number = try? c.decodeIfPresent(String.self, forKey: .number)
        content = try? c.decodeIfPresent(String.self, forKey: .content)
        date = c.decodeFlexibleInt64(forKey: .date)
        sim_id = c.decodeFlexibleInt(forKey: .sim_id)
    }

    var id: String {
        "\(number ?? "")_\(date ?? 0)_\(content?.prefix(16) ?? "")"
    }
}

// MARK: - 通话记录

/// call/query 返回的单条通话记录
struct CallRecord: Codable, Identifiable {
    let name: String?
    let number: String?
    /// 毫秒时间戳，兼容数字或字符串
    let dateLong: Int64?
    /// 时长（秒）
    let duration: Int?
    /// 1=呼入 2=呼出 3=未接
    let type: Int?
    /// 0=SIM1, 1=SIM2
    let sim_id: Int?

    enum CodingKeys: String, CodingKey {
        case name, number, dateLong, duration, type, sim_id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        number = try? c.decodeIfPresent(String.self, forKey: .number)
        dateLong = c.decodeFlexibleInt64(forKey: .dateLong)
        duration = c.decodeFlexibleInt(forKey: .duration)
        type = c.decodeFlexibleInt(forKey: .type)
        sim_id = c.decodeFlexibleInt(forKey: .sim_id)
    }

    var id: String {
        "\(number ?? "")_\(dateLong ?? 0)_\(duration ?? 0)"
    }
}

// MARK: - 联系人

/// contact/query 返回的单个联系人
struct Contact: Codable, Identifiable {
    let name: String?
    let phone_number: String?

    var id: String {
        "\(phone_number ?? "")_\(name ?? "")"
    }
}
