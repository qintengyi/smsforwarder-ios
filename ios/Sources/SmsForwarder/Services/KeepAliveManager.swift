import CoreLocation
import Observation
import UIKit

// MARK: - 后台保活管理器（定位模式 · 极简版）

/// 通过 startMonitoringSignificantLocationChanges 保持 App 在后台可被唤醒
///
/// 策略：
/// - 只用 startMonitoringSignificantLocationChanges（基站变化唤醒，极低功耗）
/// - 不用 startUpdatingLocation（避免持续定位开销和潜在崩溃）
/// - 不用 allowsBackgroundLocationUpdates（避免授权相关崩溃）
/// - 不用 beginBackgroundTask（极简策略，不需要额外后台时间）
/// - 唤醒后触发一次 HTTP 轮询检查新短信
///
/// 这是 iOS 最安全的后台保活方式：
/// - 不需要 allowsBackgroundLocationUpdates
/// - 不需要持续 GPS
/// - 可从挂起状态唤醒 App（约 10-20 秒处理时间）
@Observable
final class KeepAliveManager {
    static let shared = KeepAliveManager()

    /// 是否正在保活
    var isKeepingAlive: Bool = false
    /// 供调试面板查看的最后一次错误
    var lastError: String = ""
    /// 供调试面板查看的最后启动时间
    var startedAt: String = ""
    /// 定位授权状态（供调试面板查看）
    var authStatus: String = "未请求"
    /// 最近一次唤醒时间
    var lastWakeTime: String = ""
    /// 唤醒次数
    var wakeCount: Int = 0

    @ObservationIgnored private let lm = CLLocationManager()
    @ObservationIgnored private let delegate = LocationDelegate()
    @ObservationIgnored private var hasStarted = false

    init() {
        delegate.onAuthChange = { [weak self] status in
            DispatchQueue.main.async { self?.handleAuthChange(status) }
        }
        delegate.onError = { [weak self] error in
            DispatchQueue.main.async { self?.lastError = error }
        }
        delegate.onLocationUpdate = { [weak self] in
            DispatchQueue.main.async { self?.handleLocationWake() }
        }

        lm.delegate = delegate
        lm.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        // 不设置 allowsBackgroundLocationUpdates（避免崩溃）
        // 不调用 startUpdatingLocation（避免持续定位）
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        isKeepingAlive = true
        lastError = ""

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        startedAt = formatter.string(from: Date())

        let status = lm.authorizationStatus
        print("[KeepAlive] start: authStatus=\(status.rawValue)")

        switch status {
        case .notDetermined:
            lm.requestWhenInUseAuthorization()
            authStatus = "等待授权"
        case .authorizedWhenInUse, .authorizedAlways:
            startMonitoring()
        case .denied, .restricted:
            lastError = "定位权限被拒绝，无法后台保活。请在设置→SmsForwarder→位置中开启"
            authStatus = "已拒绝"
            isKeepingAlive = false
            hasStarted = false
        @unknown default:
            lm.requestWhenInUseAuthorization()
        }
    }

    func stop() {
        if hasStarted {
            lm.stopMonitoringSignificantLocationChanges()
            hasStarted = false
        }
        isKeepingAlive = false
        print("[KeepAlive] stopped")
    }

    // MARK: - 监控启动

    /// 只启动 significantLocationChanges，不启动 startUpdatingLocation
    private func startMonitoring() {
        lm.startMonitoringSignificantLocationChanges()
        print("[KeepAlive] significantLocationChanges started")
    }

    // MARK: - 授权回调

    private func handleAuthChange(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            authStatus = "未请求"
        case .restricted:
            authStatus = "受限"
        case .denied:
            authStatus = "已拒绝"
            lastError = "定位权限被拒绝"
        case .authorizedAlways:
            authStatus = "始终"
            if hasStarted && !isKeepingAlive {
                isKeepingAlive = true
                startMonitoring()
            }
        case .authorizedWhenInUse:
            authStatus = "使用时"
            if hasStarted && !isKeepingAlive {
                isKeepingAlive = true
                startMonitoring()
            }
        @unknown default:
            authStatus = "未知"
        }
        print("[KeepAlive] auth changed: \(authStatus)")
    }

    // MARK: - 位置唤醒回调

    /// significantLocationChanges 触发时调用
    /// App 被唤醒，有约 10-20 秒处理时间
    private func handleLocationWake() {
        wakeCount += 1
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        lastWakeTime = formatter.string(from: Date())
        print("[KeepAlive] location wake #\(wakeCount) at \(lastWakeTime)")

        // 触发一次后台轮询检查新短信
        // BackgroundPoller 会在有新短信时通知 LiveActivityManager
        Task { await BackgroundPoller.shared.pollOnce() }
    }
}

// MARK: - CLLocationManagerDelegate 独立类

private final class LocationDelegate: NSObject, CLLocationManagerDelegate {
    var onAuthChange: ((CLAuthorizationStatus) -> Void)?
    var onError: ((String) -> Void)?
    var onLocationUpdate: (() -> Void)?

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // significantLocationChanges 触发，通知 KeepAliveManager
        onLocationUpdate?()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        onError?(error.localizedDescription)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuthChange?(manager.authorizationStatus)
    }
}
