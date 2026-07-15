import Foundation
import Observation

// MARK: - 监听协调器

/// 统一管理 WebSocket / HTTP 轮询 / 后台保活 / 灵动岛 四者联动
///
/// 策略：
/// - 前台：WebSocket 实时推送（低延迟）
/// - 后台：WebSocket 保持 + HTTP 轮询作为后备（双保险）
/// - audio 后台保活贯穿前后台，让 App 在后台不被挂起
/// - LiveActivityManager 内置 5 秒去重，防止 WS + poller 双路径重复触发
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
        la.requestNotificationPermission()
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
            // 确保通知权限（本地通知是后台验证码的可靠通道）
            la.requestNotificationPermission()
            if isBackground {
                // 后台：WS 保持 + poller 后备
                ws.start()
                poller.start()
            } else {
                // 前台：只用 WS
                poller.stop()
                ws.start()
                // 前台时启动待命灵动岛（Activity.request 只能在前台调用）
                la.startStandby()
            }
            ka.start()
            isRunning = true
        } else {
            ws.stop()
            poller.stop()
            ka.stop()
            la.stopStandby()
            isRunning = false
        }
    }

    /// App 进入后台：WS 保持连接 + 启动 HTTP 轮询作为后备
    /// 灵动岛已在前台预启动，后台收到验证码时用 activity.update() 更新
    func onBackground() {
        isBackground = true
        print("[Monitor] onBackground: starting poller as backup (WS stays alive)")
        if enabled && SettingsStore.shared.settings.isLoggedIn {
            poller.start()
        }
        // 不主动断开 WS
    }

    /// App 回到前台：停止 poller，只在 WS 断开时重连
    /// 处理后台暂存的验证码 + 确保待命灵动岛存在
    func onForeground() {
        guard isBackground else { return }
        isBackground = false
        print("[Monitor] onForeground: stopping poller, ws.isConnected=\(ws.isConnected)")
        poller.stop()
        if enabled && SettingsStore.shared.settings.isLoggedIn {
            if !ws.isConnected {
                ws.start()
            }
            // 先处理后台暂存的验证码（如果有）
            la.processPending()
            // 确保待命灵动岛存在
            la.startStandby()
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
