import Foundation
import Observation

// MARK: - 监听协调器

/// 统一管理 WebSocket / 后台保活 / 灵动岛 三者联动
@Observable
final class MonitoringCoordinator {
    static let shared = MonitoringCoordinator()

    /// 是否正在运行（供 UI 显示状态）
    var isRunning: Bool = false
    /// 是否在后台（供 scenePhase 切换用）
    private var isBackground: Bool = false

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
        print("[Monitor] apply: enabled=\(enabled) loggedIn=\(loggedIn) rulesCount=\(RuleStore.shared.rules.count) deviceIds=\(RuleStore.shared.subscribedDeviceIds.map { String($0) }.joined(separator: ","))")
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

    /// App 进入后台：保持 WS 连接，依赖 audio 后台保活维持 App 运行
    /// KeepAliveManager 播放静音音频让 App 不被挂起，WS 连接持续有效
    /// 如果 WS 被系统意外中断，reconnect 机制会自动重连
    func onBackground() {
        isBackground = true
        print("[Monitor] onBackground: keeping WS alive via audio background mode")
        // 不主动断开 WS
    }

    /// App 回到前台：兜底检查 WS 连接，如果后台断开且未自动重连成功则重连
    func onForeground() {
        guard isBackground else { return }
        isBackground = false
        print("[Monitor] onForeground: checking WS connection, isConnected=\(ws.isConnected)")
        if enabled && SettingsStore.shared.settings.isLoggedIn && !ws.isConnected {
            ws.start()
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
