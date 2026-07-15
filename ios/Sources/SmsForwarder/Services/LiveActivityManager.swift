import ActivityKit
import Foundation
import Observation
import UserNotifications
import UIKit

// MARK: - 灵动岛管理器

/// 验证码通知管理器
///
/// 策略：来验证码推送了再上岛（不预启动待命活动）
///
/// 双通道通知：
/// 1. Live Activity（灵动岛）— 收到验证码时创建/更新
/// 2. 本地通知 — 后台可靠后备，即使灵动岛失败也能看到验证码
@Observable
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    var lastDebugLog: String = ""
    var activitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
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
            deviceName: deviceName, receivedTime: Date()
        )
        let minutes = max(1, rule.autoEndMinutes)
        let staleDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        let content = ActivityContent(state: state, staleDate: staleDate)

        // 通道 1：尝试 Live Activity
        // 查找已有的活跃活动（可能上次验证码创建的还未结束）
        let activeActivities = Activity<CodeActivityAttributes>.activities.filter { $0.activityState == .active }
        if let activity = activeActivities.first {
            // 更新已有活动
            lastUpdatePath = "update(活动数:\(activeActivities.count))"
            print("[LiveActivity] updating existing activity id=\(activity.id)")
            Task { await activity.update(content) }
            scheduleEndActivity(minutes: minutes)
        } else {
            // 创建新活动
            do {
                let attributes = CodeActivityAttributes(ruleId: rule.id)
                let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
                lastUpdatePath = "request(成功)"
                print("[LiveActivity] created new activity id=\(activity.id)")
                scheduleEndActivity(minutes: minutes)
            } catch {
                // 后台 Activity.request 可能失败，存为 pending
                lastUpdatePath = "request失败:\(error.localizedDescription)"
                pendingSMS = PendingCode(rule: rule, projectName: projectName, code: code, sender: sender, deviceName: deviceName, timestamp: Date())
                pendingCount = 1
                print("[LiveActivity] request failed: \(error.localizedDescription), saved as pending")
            }
        }

        // 通道 2：本地通知（后台时发送，前台时跳过避免打扰）
        if isBackground {
            sendLocalNotification(projectName: projectName, code: code, sender: sender, deviceName: deviceName)
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

    /// 回到前台时处理暂存的验证码（后台 Activity.request 失败的情况）
    func processPending() {
        guard let pending = pendingSMS else { return }
        pendingSMS = nil
        pendingCount = 0
        print("[LiveActivity] processing pending: \(pending.code)")

        let state = CodeActivityAttributes.ContentState(
            projectName: pending.projectName, code: pending.code, sender: pending.sender,
            deviceName: pending.deviceName, receivedTime: pending.timestamp
        )
        let minutes = max(1, pending.rule.autoEndMinutes)
        let staleDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        let content = ActivityContent(state: state, staleDate: staleDate)

        // 先结束已有活动
        for activity in Activity<CodeActivityAttributes>.activities where activity.activityState == .active {
            Task { await activity.end(dismissalPolicy: .immediate) }
        }

        // 创建新活动显示 pending 验证码
        do {
            let attributes = CodeActivityAttributes(ruleId: pending.rule.id)
                let _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
                lastUpdatePath = "pending→request"
            lastDebugLog = "[\(timeStr())] 补显示: \(pending.projectName) \(pending.code)"
            scheduleEndActivity(minutes: minutes)
        } catch {
            lastUpdatePath = "pending→失败"
            lastDebugLog = "[\(timeStr())] 补显示失败: \(error.localizedDescription)"
        }
    }

    // MARK: - 超时结束

    /// N 分钟后结束活动（不再重置为待命）
    private func scheduleEndActivity(minutes: Int) {
        resetTimer?.invalidate()
        resetTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: false) { [weak self] _ in
            self?.endAllActivities()
        }
    }

    private func endAllActivities() {
        for activity in Activity<CodeActivityAttributes>.activities where activity.activityState == .active {
            Task { await activity.end(dismissalPolicy: .immediate) }
        }
        lastDebugLog = "[\(timeStr())] 验证码活动已结束"
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
    }

    func cleanupStale() {
        pendingSMS = nil
        pendingCount = 0
        for activity in Activity<CodeActivityAttributes>.activities {
            Task { await activity.end(dismissalPolicy: .immediate) }
        }
    }

    private func timeStr() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}
