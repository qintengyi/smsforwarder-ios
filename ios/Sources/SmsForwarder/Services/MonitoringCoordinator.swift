import Foundation
import Observation

// MARK: - 监听协调器

/// 统一管理 WebSocket / HTTP 轮询 / 后台保活 / 灵动岛 四者联动
///
/// 策略：
/// - 前台：WebSocket 实时推送（低延迟）
/// - 后台：HTTP 轮询（可靠，不受 iOS WebSocket 后台限制影响）
/// - audio 后台保活贯穿前后台，让 App 在后台不被挂起
@Observable
final class MonitoringCoordinator {
    static let shared = MonitoringCoordinator()

    /// 是否正在运行（供 UI 显示状态）
    var isRunning: Bool = false
    /// 是否在后台（供 scenePhase 切换用）
    private var isBackground: Bool = false

    private let ws = WebSocketClient.shared
    private let poller = BackgroundPoller.shared
    private let ka = KeepAliveManager.shared
    private let la = LiveActivityManager.shared
    private let key = "io.smsforwarder.monitoringEnabled"

    var enabled: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? false
    }

    /// 应用启动 / 登录成功后调用
    func setup() {
        la.cleanupStale()
        // WebSocket 和 Poller 共用同一个回调，都路由到 LiveActivityManager
        ws.onSMS = { [weak self] deviceId, deviceName, sms in
            self?.la.handleSMS(deviceId: deviceId, deviceName: deviceName, sms: sms)
        }
        poller.onSMS = { [weak self] deviceId, deviceName, sms in
            self?.la.handleSMS(deviceId: deviceId, deviceName: deviceName, sms: sms)
        }
        apply()
    }

    /// 根据「开关 + 登录状态」启动或停止监听
    func apply() {
        let loggedIn = SettingsStore.shared.settings.isLoggedIn
        print("[Monitor] apply: enabled=\(enabled) loggedIn=\(loggedIn) isBackground=\(isBackground) rulesCount=\(RuleStore.shared.rules.count) deviceIds=\(RuleStore.shared.subscribedDeviceIds.map { String($0) }.joined(separator: ","))")
        if enabled && loggedIn {
            if isBackground {
                // 后台：用 HTTP 轮询
                ws.stop()
                poller.start()
            } else {
                // 前台：用 WebSocket
                poller.stop()
                ws.start()
            }
            ka.start()
            isRunning = true
        } else {
            ws.stop()
            poller.stop()
            ka.stop()
            isRunning = false
        }
    }

    /// App 进入后台：切换到 HTTP 轮询模式
    /// WebSocket 在后台容易被 iOS 系统强制中断，HTTP 请求更可靠
    func onBackground() {
        isBackground = true
        print("[Monitor] onBackground: switching to HTTP polling")
        ws.stop()
        if enabled && SettingsStore.shared.settings.isLoggedIn {
            poller.start()
        }
    }

    /// App 回到前台：切换回 WebSocket 实时模式
    func onForeground() {
        guard isBackground else { return }
        isBackground = false
        print("[Monitor] onForeground: switching to WebSocket")
        poller.stop()
        if enabled && SettingsStore.shared.settings.isLoggedIn {
            ws.start()
        }
    }

    /// 退出登录时调用
    func onLogout() {
        ws.stop()
        poller.stop()
        ka.stop()
        la.endAll()
        isRunning = false
    }
}
