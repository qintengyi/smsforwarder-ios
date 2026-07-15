import CoreLocation
import Observation
import UIKit

// MARK: - 后台保活管理器（定位模式）

/// 通过 CLLocationManager 低功耗定位保持 App 在后台持续运行
///
/// 参考 AFN.dylib（微信保活插件）的策略：
/// 1. startMonitoringSignificantLocationChanges — 基站变化时唤醒 App（极低功耗）
/// 2. startUpdatingLocation + kCLLocationAccuracyThreeKilometers — 3km 精度仅用基站 triangulation
/// 3. beginBackgroundTask + 定时刷新 — 获取额外后台处理时间
/// 4. 系统暂停后自动重启 — locationManagerDidPauseLocationUpdates
///
/// ⚠️ 关键：allowsBackgroundLocationUpdates 必须在授权后设置，
///    否则 iOS 会抛出 NSInternalInconsistencyException 崩溃
@Observable
final class KeepAliveManager: NSObject, CLLocationManagerDelegate {
    static let shared = KeepAliveManager()

    /// 是否正在保活
    var isKeepingAlive: Bool = false
    /// 供调试面板查看的最后一次错误
    var lastError: String = ""
    /// 供调试面板查看的最后启动时间
    var startedAt: String = ""
    /// 定位授权状态（供调试面板查看）
    var authStatus: String = "未请求"
    /// 后台剩余时间（供调试面板查看）
    var bgTimeRemaining: TimeInterval = 0

    @ObservationIgnored private let lm = CLLocationManager()
    @ObservationIgnored private var bgTaskId: UIBackgroundTaskIdentifier = UIBackgroundTaskIdentifier.invalid
    @ObservationIgnored private var bgTaskTimer: Timer?
    /// 定位更新是否已启动（防止重复启动）
    @ObservationIgnored private var locationUpdatesStarted: Bool = false

    override init() {
        super.init()
        lm.delegate = self
        // 3km 精度：仅使用基站 triangulation，不启用 GPS 芯片，功耗极低
        lm.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        // 不自动暂停定位更新
        lm.pausesLocationUpdatesAutomatically = false
        lm.activityType = .other
        // ⚠️ 不在这里设置 allowsBackgroundLocationUpdates！
        // 必须等用户授权后才能设置，否则崩溃
    }

    func start() {
        guard !isKeepingAlive else { return }
        isKeepingAlive = true
        lastError = ""

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        startedAt = formatter.string(from: Date())

        let status = lm.authorizationStatus
        print("[KeepAlive] start: authStatus=\(status.rawValue)")

        switch status {
        case .notDetermined:
            // 请求授权，等回调后启动定位
            lm.requestWhenInUseAuthorization()
            authStatus = "等待授权"
        case .authorizedWhenInUse, .authorizedAlways:
            // 已有授权，直接启动
            startLocationUpdates()
        case .denied, .restricted:
            lastError = "定位权限被拒绝，无法后台保活。请在设置→SmsForwarder→位置中开启"
            authStatus = "已拒绝"
            isKeepingAlive = false
        @unknown default:
            lm.requestWhenInUseAuthorization()
        }

        print("[KeepAlive] start requested (accuracy=3km)")
    }

    func stop() {
        if locationUpdatesStarted {
            lm.stopUpdatingLocation()
            lm.stopMonitoringSignificantLocationChanges()
            locationUpdatesStarted = false
        }
        stopBgTaskTimer()
        endBgTask()
        isKeepingAlive = false
        print("[KeepAlive] stopped")
    }

    // MARK: - 定位更新（授权后调用）

    /// 启动定位更新 — 仅在授权后调用
    private func startLocationUpdates() {
        guard !locationUpdatesStarted else { return }
        locationUpdatesStarted = true

        // 授权后才能设置 allowsBackgroundLocationUpdates
        lm.allowsBackgroundLocationUpdates = true

        // 启动显著位置变化监听（基站变化时唤醒 App，可从挂起状态恢复）
        lm.startMonitoringSignificantLocationChanges()

        // 启动低精度持续定位（保持 App 在后台不被挂起）
        lm.startUpdatingLocation()

        // 启动后台任务定时器
        startBgTaskTimer()

        print("[KeepAlive] location updates started (accuracy=3km, significantChanges=on)")
    }

    // MARK: - 后台任务管理

    /// 启动定时器，每 5 秒刷新后台任务
    private func startBgTaskTimer() {
        bgTaskTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.requestMoreBackgroundTime()
        }
        requestMoreBackgroundTime()
    }

    private func stopBgTaskTimer() {
        bgTaskTimer?.invalidate()
        bgTaskTimer = nil
    }

    /// 请求更多后台处理时间
    /// iOS 给约 30 秒后台时间，每 5 秒刷新一次确保不超时
    private func requestMoreBackgroundTime() {
        // 先结束旧任务
        if bgTaskId != UIBackgroundTaskIdentifier.invalid {
            UIApplication.shared.endBackgroundTask(bgTaskId)
            bgTaskId = UIBackgroundTaskIdentifier.invalid
        }

        bgTimeRemaining = UIApplication.shared.backgroundTimeRemaining

        bgTaskId = UIApplication.shared.beginBackgroundTask(withName: "KeepAlive") { [weak self] in
            self?.handleBgTaskExpired()
        }
    }

    private func handleBgTaskExpired() {
        print("[KeepAlive] background task expired, requesting more")
        if bgTaskId != UIBackgroundTaskIdentifier.invalid {
            UIApplication.shared.endBackgroundTask(bgTaskId)
            bgTaskId = UIBackgroundTaskIdentifier.invalid
        }
        requestMoreBackgroundTime()
    }

    private func endBgTask() {
        if bgTaskId != UIBackgroundTaskIdentifier.invalid {
            UIApplication.shared.endBackgroundTask(bgTaskId)
            bgTaskId = UIBackgroundTaskIdentifier.invalid
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // 位置更新保持 App 在后台不被挂起
        // 我们不使用位置数据，仅利用定位回调保活
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastError = error.localizedDescription
        print("[KeepAlive] location error: \(error.localizedDescription)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            authStatus = "未请求"
        case .restricted:
            authStatus = "受限"
        case .denied:
            authStatus = "已拒绝"
            lastError = "定位权限被拒绝，无法后台保活。请在设置→SmsForwarder→位置中开启"
        case .authorizedAlways:
            authStatus = "始终"
            if isKeepingAlive && !locationUpdatesStarted {
                startLocationUpdates()
            }
        case .authorizedWhenInUse:
            authStatus = "使用时"
            if isKeepingAlive && !locationUpdatesStarted {
                startLocationUpdates()
            }
        @unknown default:
            authStatus = "未知"
        }
        print("[KeepAlive] location auth changed: \(authStatus)")
    }

    /// 系统暂停了定位更新时自动重启
    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        print("[KeepAlive] location updates paused by system, restarting")
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.locationUpdatesStarted else { return }
            self.lm.startUpdatingLocation()
            self.lm.startMonitoringSignificantLocationChanges()
        }
    }
}
