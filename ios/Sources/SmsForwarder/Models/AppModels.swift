import Foundation

// MARK: - 电量信息

/// battery/query 返回的电量信息
struct BatteryInfo: Codable {
    let level: Int?          // 电量百分比 0-100，兼容 "85%" / "85" / 85
    let status: String?      // 充电状态: charging / discharging / full / not-charging
    let health: String?      // 健康: good / overheat / dead / over_voltage / cold / unknown
    let plugged: String?     // 是否接入电源: ac / usb / wireless / null
    let voltage: Int?        // 电压 (mV)，兼容字符串
    let temperature: Int?    // 温度 (10*℃)，兼容字符串

    init(level: Int?, status: String?, health: String?, plugged: String?, voltage: Int?, temperature: Int?) {
        self.level = level
        self.status = status
        self.health = health
        self.plugged = plugged
        self.voltage = voltage
        self.temperature = temperature
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        level = c.decodeFlexibleInt(forKey: .level)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        health = try? c.decodeIfPresent(String.self, forKey: .health)
        plugged = try? c.decodeIfPresent(String.self, forKey: .plugged)
        voltage = c.decodeFlexibleInt(forKey: .voltage)
        temperature = c.decodeFlexibleInt(forKey: .temperature)
    }
}

// MARK: - 定位信息

/// location/query 返回的定位信息
struct LocationInfo: Codable {
    let address: String?     // 详细地址
    let latitude: Double?
    let longitude: Double?
    /// 毫秒时间戳
    let time: Int64?
    let provider: String?    // 定位提供者: gps / network / passive / fused

    init(address: String?, latitude: Double?, longitude: Double?, time: Int64?, provider: String?) {
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.time = time
        self.provider = provider
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        address = try? c.decodeIfPresent(String.self, forKey: .address)
        latitude = c.decodeFlexibleDouble(forKey: .latitude)
        longitude = c.decodeFlexibleDouble(forKey: .longitude)
        time = c.decodeFlexibleInt64(forKey: .time)
        provider = try? c.decodeIfPresent(String.self, forKey: .provider)
    }
}

// MARK: - 宽松 JSON 解码

extension KeyedDecodingContainer {
    func decodeFlexibleInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            let normalized = value.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let intValue = Int(normalized) { return intValue }
            if let doubleValue = Double(normalized) { return Int(doubleValue) }
            return nil
        }
        return nil
    }

    func decodeFlexibleInt64(forKey key: Key) -> Int64? {
        if let value = try? decodeIfPresent(Int64.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return Int64(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return Int64(value) }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if let intValue = Int64(normalized) { return intValue }
            if let doubleValue = Double(normalized) { return Int64(doubleValue) }
            return nil
        }
        return nil
    }

    func decodeFlexibleDouble(forKey key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return Double(value) }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}

// MARK: - 应用设置模型

/// 设置页使用的本地配置（持久化到 UserDefaults）
/// 只需一个 Web 面板地址 + 登录 token，Flask 面板内部管理设备 IP/端口/密钥
struct AppSettings: Codable, Equatable {
    var serverURL: String
    var token: String?       // 登录认证 token，nil 表示未登录
    var username: String?    // 记住上次登录用户名

    static let `default` = AppSettings(
        serverURL: "https://smsf.xiaoyyua.top",
        token: nil,
        username: nil
    )

    var isLoggedIn: Bool {
        guard let token = token, !token.isEmpty else { return false }
        return true
    }
}

// MARK: - 本地配置管理

/// 管理面板连接配置和登录状态，持久化到 UserDefaults
final class SettingsStore {
    static let shared = SettingsStore()
    private let key = "io.smsforwarder.settings"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var settings: AppSettings {
        get {
            guard let data = defaults.data(forKey: key),
                  let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
                return .default
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: key)
            }
        }
    }

    func save(_ settings: AppSettings) {
        self.settings = settings
    }

    /// 保存登录 token
    func saveLogin(token: String, username: String) {
        var s = settings
        s.token = token
        s.username = username
        save(s)
    }

    /// 清除登录状态（退出登录）
    func clearLogin() {
        var s = settings
        s.token = nil
        save(s)
    }
}
