import Foundation
import Observation

// MARK: - 监听协调器

/// 统一管理 WebSocket / 后台保活 / 灵动岛 三者联动
@Observable
final class MonitoringCoordinator {
    static let shared = MonitoringCoordinator()

    /// 是否正在运行（供 UI 显示状态）
    var isRunning: Bool = false

    private let ws = WebSocketClient.shared
    private let ka = KeepAliveManager.shared
    private let la = LiveActivityManager.shared
    private let key = "io.smsforwarder.monitoringEnabled"

    var enabled: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? false
    }

    /// 应用启动 / 登录成功后调用
    func setup() {
        la.cleanupStale()
        ws.onSMS = { [weak self] deviceId, deviceName, sms in
            self?.la.handleSMS(deviceId: deviceId, deviceName: deviceName, sms: sms)
        }
        apply()
    }

    /// 根据「开关 + 登录状态」启动或停止监听
    func apply() {
        let loggedIn = SettingsStore.shared.settings.isLoggedIn
        NSLog("[Monitor] apply: enabled=%@ loggedIn=%@ rulesCount=%d deviceIds=%@",
              enabled ? "true" : "false",
              loggedIn ? "true" : "false",
              RuleStore.shared.rules.count,
              RuleStore.shared.subscribedDeviceIds.map { String($0) }.joined(separator: ","))
        if enabled && loggedIn {
            ws.start()
            ka.start()
            isRunning = true
        } else {
            ws.stop()
            ka.stop()
            isRunning = false
        }
    }

    /// 退出登录时调用
    func onLogout() {
        ws.stop()
        ka.stop()
        la.endAll()
        isRunning = false
    }
}
