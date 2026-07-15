import ActivityKit
import Foundation
import Observation
import UserNotifications
import UIKit

// MARK: - 灵动岛管理器

/// 验证码通知管理器
///
/// 双通道通知：
/// 1. Live Activity（灵动岛）— 前台预启动 + 后台 update
/// 2. 本地通知 — 后台可靠后备，即使灵动岛失败也能看到验证码
@Observable
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    var lastDebugLog: String = ""
    var activitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    var standbyActive: Bool = false
    var lastUpdatePath: String = ""
    var pendingCount: Int = 0
    /// 通知权限是否已授权
    var notificationAuthorized: Bool = false

    private var lastProcessedContent: String = ""
    private var lastProcessedTime: Date = .distantPast
    private var resetTimer: Timer?
    private var pendingSMS: PendingCode?

    struct PendingCode {
        let rule: CodeRule
        let projectName: String
        let code: String
        let sender: String
        let deviceName: String
        let timestamp: Date
    }

    // MARK: - 通知权限

    /// 请求本地通知权限（启用监听时调用）
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                self.notificationAuthorized = granted
                print("[LiveActivity] notification permission: \(granted ? "granted" : "denied")")
            }
        }
    }

    // MARK: - 待命活动管理

    func startStandby() {
        guard activitiesEnabled else {
            print("[LiveActivity] cannot start standby: activities not enabled")
            return
        }

        let existing = Activity<CodeActivityAttributes>.activities.filter { $0.activityState == .active }
        if !existing.isEmpty {
            print("[LiveActivity] found \(existing.count) existing active activity(ies)")
            standbyActive = true
            updateToIdle(activity: existing[0])
            return
        }

        let attributes = CodeActivityAttributes(ruleId: "standby")
        let state = CodeActivityAttributes.ContentState(
            projectName: "", code: "", sender: "", deviceName: "",
            receivedTime: Date(), isIdle: true
        )

        do {
            let content = ActivityContent(state: state, staleDate: nil)
            let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            standbyActive = true
            lastDebugLog = "[\(timeStr())] 待命灵动岛已启动"
            print("[LiveActivity] standby started, id=\(activity.id)")
        } catch {
            standbyActive = false
            lastDebugLog = "[\(timeStr())] 启动待命失败: \(error.localizedDescription)"
            print("[LiveActivity] standby failed: \(error.localizedDescription)")
        }
    }

    func stopStandby() {
        resetTimer?.invalidate()
        resetTimer = nil
        for activity in Activity<CodeActivityAttributes>.activities {
            Task { await activity.end(dismissalPolicy: .immediate) }
        }
        standbyActive = false
    }

    // MARK: - 短信处理

    func handleSMS(deviceId: Int, deviceName: String, sms: WSSmsRecord) {
        let content = sms.content ?? ""
        guard !content.isEmpty else {
            lastDebugLog = "[\(timeStr())] 收到空短信，跳过"
            return
        }

        let now = Date()
        if content == lastProcessedContent && now.timeIntervalSince(lastProcessedTime) < 5 {
            return
        }
        lastProcessedContent = content
        lastProcessedTime = now

        let rules = RuleStore.shared.matchingRules(deviceId: deviceId, content: content)
        guard let rule = rules.first else {
            lastDebugLog = "[\(timeStr())] 设备\(deviceId)无匹配规则\n短信: \(String(content.prefix(60)))"
            return
        }
        guard let code = CodeExtractor.code(from: content) else {
            lastDebugLog = "[\(timeStr())] 未提取到验证码\n短信: \(String(content.prefix(60)))"
            return
        }

        let projectName = CodeExtractor.projectName(from: content, fallback: sms.name)
        let sender = (sms.name?.isEmpty == false ? sms.name : sms.number) ?? "未知发送方"

        updateWithCode(rule: rule, projectName: projectName, code: code, sender: sender, deviceName: deviceName)
    }

    func testActivity() {
        let testRule = CodeRule(deviceId: 0, deviceName: "测试设备", keyword: "", enabled: true, autoEndMinutes: 2)
        updateWithCode(rule: testRule, projectName: "测试项目", code: "123456", sender: "测试发送方", deviceName: "测试设备")
    }

    // MARK: - 核心逻辑

    private func updateWithCode(rule: CodeRule, projectName: String, code: String, sender: String, deviceName: String) {
        let isBackground = UIApplication.shared.applicationState == .background
        lastDebugLog = "[\(timeStr())] 收到验证码: \(projectName) \(code) (后台:\(isBackground))"

        let state = CodeActivityAttributes.ContentState(
            projectName: projectName, code: code, sender: sender,
            deviceName: deviceName, receivedTime: Date(), isIdle: false
        )
        let minutes = max(1, rule.autoEndMinutes)
        let staleDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        let content = ActivityContent(state: state, staleDate: staleDate)

        // 通道 1：尝试 Live Activity
        let activeActivities = Activity<CodeActivityAttributes>.activities.filter { $0.activityState == .active }
        if let activity = activeActivities.first {
            lastUpdatePath = "update(活动数:\(activeActivities.count))"
            standbyActive = true
            print("[LiveActivity] updating activity id=\(activity.id)")
            Task { await activity.update(content) }
            scheduleResetToIdle(minutes: minutes)
        } else {
            standbyActive = false
            do {
                let attributes = CodeActivityAttributes(ruleId: rule.id)
                let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
                lastUpdatePath = "request(成功)"
                standbyActive = true
                print("[LiveActivity] request succeeded, id=\(activity.id)")
                scheduleResetToIdle(minutes: minutes)
            } catch {
                lastUpdatePath = "request失败"
                pendingSMS = PendingCode(rule: rule, projectName: projectName, code: code, sender: sender, deviceName: deviceName, timestamp: Date())
                pendingCount = 1
                print("[LiveActivity] request failed: \(error.localizedDescription)")
            }
        }

        // 通道 2：本地通知（后台时必定发送，前台时跳过避免打扰）
        if isBackground {
            sendLocalNotification(projectName: projectName, code: code, sender: sender, deviceName: deviceName)
        }

        // 更新日志
        if isBackground {
            lastDebugLog = "[\(timeStr())] 验证码: \(projectName) \(code) (后台通知已发送)"
        }
    }

    /// 发送本地通知（后台可靠显示验证码）
    private func sendLocalNotification(projectName: String, code: String, sender: String, deviceName: String) {
        let center = UNUserNotificationCenter.current()

        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                print("[LiveActivity] notification not authorized, skipping")
                return
            }

            let notif = UNMutableNotificationContent()
            notif.title = "验证码 - \(projectName)"
            notif.body = code
            notif.subtitle = "\(sender) · \(deviceName)"
            notif.sound = .default
            notif.categoryIdentifier = "CODE_NOTIFICATION"
            notif.interruptionLevel = .timeSensitive  // 突破专注模式

            let request = UNNotificationRequest(
                identifier: "smsf_code_\(Date().timeIntervalSince1970)",
                content: notif,
                trigger: nil  // 立即发送
            )

            center.add(request) { error in
                if let error = error {
                    print("[LiveActivity] notification send error: \(error.localizedDescription)")
                } else {
                    print("[LiveActivity] notification sent: \(projectName) \(code)")
                }
            }
        }
    }

    /// 回到前台时处理暂存的验证码
    func processPending() {
        guard let pending = pendingSMS else { return }
        pendingSMS = nil
        pendingCount = 0
        print("[LiveActivity] processing pending: \(pending.code)")

        let state = CodeActivityAttributes.ContentState(
            projectName: pending.projectName, code: pending.code, sender: pending.sender,
            deviceName: pending.deviceName, receivedTime: pending.timestamp, isIdle: false
        )
        let minutes = max(1, pending.rule.autoEndMinutes)
        let staleDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        let content = ActivityContent(state: state, staleDate: staleDate)

        let activeActivities = Activity<CodeActivityAttributes>.activities.filter { $0.activityState == .active }
        if let activity = activeActivities.first {
            Task { await activity.update(content) }
            lastUpdatePath = "pending→update"
            lastDebugLog = "[\(timeStr())] 补显示: \(pending.projectName) \(pending.code)"
            standbyActive = true
            scheduleResetToIdle(minutes: minutes)
        } else {
            do {
                let attributes = CodeActivityAttributes(ruleId: pending.rule.id)
                let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
                lastUpdatePath = "pending→request"
                lastDebugLog = "[\(timeStr())] 补显示: \(pending.projectName) \(pending.code)"
                standbyActive = true
                scheduleResetToIdle(minutes: minutes)
            } catch {
                lastUpdatePath = "pending→失败"
                lastDebugLog = "[\(timeStr())] 补显示失败: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - 超时重置

    private func scheduleResetToIdle(minutes: Int) {
        resetTimer?.invalidate()
        resetTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: false) { [weak self] _ in
            self?.resetToIdle()
        }
    }

    private func resetToIdle() {
        let activeActivities = Activity<CodeActivityAttributes>.activities.filter { $0.activityState == .active }
        guard let activity = activeActivities.first else {
            standbyActive = false
            return
        }
        updateToIdle(activity: activity)
        lastDebugLog = "[\(timeStr())] 已重置为待命"
    }

    private func updateToIdle(activity: Activity<CodeActivityAttributes>) {
        let idleState = CodeActivityAttributes.ContentState(
            projectName: "", code: "", sender: "", deviceName: "",
            receivedTime: Date(), isIdle: true
        )
        let content = ActivityContent(state: idleState, staleDate: nil)
        Task { await activity.update(content) }
    }

    // MARK: - 清理

    func endAll() {
        resetTimer?.invalidate()
        resetTimer = nil
        pendingSMS = nil
        pendingCount = 0
        for activity in Activity<CodeActivityAttributes>.activities {
            Task { await activity.end(dismissalPolicy: .immediate) }
        }
        standbyActive = false
    }

    func cleanupStale() {
        pendingSMS = nil
        pendingCount = 0
        for activity in Activity<CodeActivityAttributes>.activities {
            Task { await activity.end(dismissalPolicy: .immediate) }
        }
        standbyActive = false
    }

    private func timeStr() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}
