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

    /// App 进入后台：断开 WS（iOS 后台会强制中断），保持 audio 保活
    func onBackground() {
        isBackground = true
        print("[Monitor] onBackground: disconnecting WS, keeping audio alive")
        ws.stop()  // 主动断开，避免系统 abort 错误暴露给用户
    }

    /// App 回到前台：立即重连 WS
    func onForeground() {
        guard isBackground else { return }
        isBackground = false
        print("[Monitor] onForeground: reconnecting WS")
        // 只在监听开关开启且已登录时重连
        if enabled && SettingsStore.shared.settings.isLoggedIn {
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
