import Foundation
import Observation

// MARK: - 设备模型

/// Go 面板中的设备模型
struct Device: Codable, Identifiable, Equatable {
    let id: Int
    let name: String
    let api_base_url: String?
    let sign_key: String?
    let remark: String?
}

// MARK: - 用户信息

/// 登录后返回的用户信息
struct UserProfile: Codable {
    let id: Int?
    let username: String?
    let remark: String?
}

// MARK: - 设备健康状态

/// 设备健康检查结果
struct DeviceHealth: Codable {
    let online: Bool?
    let duration_ms: Int?

    init(online: Bool?, duration_ms: Int?) {
        self.online = online
        self.duration_ms = duration_ms
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        online = try? c.decodeIfPresent(Bool.self, forKey: .online)
        duration_ms = c.decodeFlexibleInt(forKey: .duration_ms)
    }
}

// MARK: - 设备管理 Store

/// 全局设备状态管理，管理设备列表和当前选中设备
@Observable
final class DeviceStore {
    static let shared = DeviceStore()

    var devices: [Device] = []
    var currentDeviceId: Int? = nil
    var isLoaded: Bool = false
    var isLoading: Bool = false
    var errorMessage: String?

    private let store = SettingsStore.shared

    var current: Device? {
        guard let id = currentDeviceId else { return devices.first }
        return devices.first { $0.id == id }
    }

    var hasDevices: Bool {
        !devices.isEmpty
    }

    /// 从面板拉取设备列表
    func fetch() async throws {
        isLoading = true
        defer { isLoading = false }

        let resp: APIResponse<[Device]> = try await SmsForwarderAPI.shared.get(path: "devices")
        devices = resp.data ?? []

        // 恢复上次选中的设备
        if currentDeviceId == nil || !devices.contains(where: { $0.id == currentDeviceId }) {
            currentDeviceId = devices.first?.id
            persistCurrentDeviceId()
        }

        isLoaded = true
    }

    /// 设置当前设备
    func setCurrent(_ id: Int) {
        currentDeviceId = id
        persistCurrentDeviceId()
    }

    /// 清除设备列表（退出登录时调用）
    func clear() {
        devices = []
        currentDeviceId = nil
        isLoaded = false
        var s = store.settings
        s.currentDeviceId = nil
        store.save(s)
    }

    /// 从本地存储恢复上次选中的设备 ID
    func restoreFromStorage() {
        if let savedId = store.settings.currentDeviceId {
            currentDeviceId = savedId
        }
    }

    private func persistCurrentDeviceId() {
        var s = store.settings
        s.currentDeviceId = currentDeviceId
        store.save(s)
    }
}
