import ActivityKit
import Foundation
import Observation

// MARK: - 灵动岛管理器

/// 根据订阅规则匹配短信，启动 / 更新 / 结束灵动岛 Live Activity
@Observable
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    /// 当前活跃的活动（ruleId -> Activity）
    private var activities: [String: Activity<CodeActivityAttributes>] = [:]

    /// 处理一条收到的实时短信
    func handleSMS(deviceId: Int, deviceName: String, sms: WSSmsRecord) {
        let content = sms.content ?? ""
        guard !content.isEmpty else {
            NSLog("[LiveActivity] handleSMS skipped: empty content")
            return
        }

        NSLog("[LiveActivity] handleSMS: deviceId=%d name=%@ content=%@", deviceId, deviceName, String(content.prefix(80)))

        let rules = RuleStore.shared.matchingRules(deviceId: deviceId, content: content)
        guard let rule = rules.first else {
            NSLog("[LiveActivity] no matching rule for device %d (rules count=%d)", deviceId, RuleStore.shared.rules.count)
            return
        }
        guard let code = CodeExtractor.code(from: content) else {
            NSLog("[LiveActivity] rule matched but no code extracted from: %@", String(content.prefix(80)))
            return
        }

        let projectName = CodeExtractor.projectName(from: content, fallback: sms.name)
        let sender = (sms.name?.isEmpty == false ? sms.name : sms.number) ?? "未知发送方"
        NSLog("[LiveActivity] starting activity: project=%@ code=%@ sender=%@ device=%@", projectName, code, sender, deviceName)
        startActivity(rule: rule, projectName: projectName, code: code, sender: sender, deviceName: deviceName)
    }

    /// 启动灵动岛（同规则先结束旧的，避免重复）
    func startActivity(rule: CodeRule, projectName: String, code: String, sender: String, deviceName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            NSLog("[LiveActivity] activities not enabled (user may have disabled in Settings)")
            return
        }

        endActivity(ruleId: rule.id)

        let attributes = CodeActivityAttributes(ruleId: rule.id)
        let state = CodeActivityAttributes.ContentState(
            projectName: projectName,
            code: code,
            sender: sender,
            deviceName: deviceName,
            receivedTime: Date()
        )

        let minutes = max(1, rule.autoEndMinutes)
        let staleDate = Date().addingTimeInterval(TimeInterval(minutes * 60))

        do {
            let content = ActivityContent(state: state, staleDate: staleDate)
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            activities[rule.id] = activity
            NSLog("[LiveActivity] activity started successfully: project=%@ code=%@", projectName, code)

            // 到时自动结束
            let ruleId = rule.id
            DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(minutes * 60)) { [weak self] in
                self?.endActivity(ruleId: ruleId)
            }
        } catch {
            NSLog("[LiveActivity] failed to start activity: %@", error.localizedDescription)
        }
    }

    /// 结束指定规则的活动
    func endActivity(ruleId: String) {
        guard let activity = activities[ruleId] else { return }
        activities.removeValue(forKey: ruleId)
        Task { await activity.end(dismissalPolicy: .immediate) }
    }

    /// 结束所有活动
    func endAll() {
        let snapshot = activities
        activities.removeAll()
        for (_, activity) in snapshot {
            Task { await activity.end(dismissalPolicy: .immediate) }
        }
    }

    /// 清理上次 App 运行残留的 Live Activity（启动时调用）
    func cleanupStale() {
        for activity in Activity<CodeActivityAttributes>.activities {
            Task { await activity.end(dismissalPolicy: .immediate) }
        }
        activities.removeAll()
    }
}
