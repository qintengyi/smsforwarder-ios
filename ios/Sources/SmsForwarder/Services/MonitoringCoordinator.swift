import Foundation
import Observation

// MARK: - 监听协调器

/// 统一管理 WebSocket / HTTP 轮询 / 后台保活 / 灵动岛 四者联动
///
/// 策略：
/// - 前台：WebSocket 实时推送 + HTTP 轮询双保险（WS 断了 poller 兜底）
/// - 后台：停 WS（iOS 会杀掉 WS 连接），只用 HTTP 轮询
/// - CLLocationManager 定位保活贯穿前后台，让 App 在后台不被挂起
/// - 灵动岛：来验证码推送了再上岛（不预启动待命活动）
/// - 本地通知：后台收到验证码时可靠弹窗
/// - 去重：LiveActivityManager.handleSMS 内 5 秒内相同内容去重
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
                // 后台：停 WS（iOS 会杀掉连接，避免重连风暴），只用 poller
                ws.stop()
                poller.start()
            } else {
                // 前台：WS 实时推送 + poller 双保险
                // poller 作为 fallback：即使 WS 连不上也能检测到新短信
                // 去重由 LiveActivityManager.handleSMS 内 5 秒窗口处理
                ws.start()
                poller.start()
            }
            // 定位保活贯穿前后台
            ka.start()
            isRunning = true
        } else {
            ws.stop()
            poller.stop()
            ka.stop()
            la.endAll()
            isRunning = false
        }
    }

    /// App 进入后台：停 WS（避免重连风暴），启动 HTTP 轮询
    /// 定位保活已在前台启动，后台继续运行
    func onBackground() {
        isBackground = true
        print("[Monitor] onBackground: stopping WS, starting poller")
        if enabled && SettingsStore.shared.settings.isLoggedIn {
            ws.stop()  // 后台 WS 不可靠，主动停止避免重连风暴和 "Software caused connection abort" 错误
            poller.start()
        }
    }

    /// App 回到前台：启动 WS + 保持 poller 运行（双保险）
    /// 处理后台暂存的验证码（如果 Activity.request 在后台失败）
    func onForeground() {
        // 不再 guard isBackground：App 被系统杀死后重启时 isBackground 默认 false，
        // 但 WS 可能未连接，需要重新启动
        let wasBackground = isBackground
        isBackground = false
        print("[Monitor] onForeground: wasBackground=\(wasBackground), ws.isConnected=\(ws.isConnected)")
        if enabled && SettingsStore.shared.settings.isLoggedIn {
            // 启动 WS（如果已连接则 start() 内部会跳过）
            ws.start()
            // poller 保持运行作为前台 fallback（双保险）
            // 去重由 LiveActivityManager.handleSMS 处理
            poller.start()
            // 补显示后台暂存的验证码（如果有的话）
            la.processPending()
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
