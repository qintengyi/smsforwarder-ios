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

    /// 去重：5 秒内相同内容的短信不重复处理（防止 WS + poller 双路径重复触发）
    private var lastProcessedContent: String = ""
    private var lastProcessedTime: Date = .distantPast

    /// 调试信息
    var lastDebugLog: String = ""
    var activitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// 处理一条收到的实时短信
    func handleSMS(deviceId: Int, deviceName: String, sms: WSSmsRecord) {
        let content = sms.content ?? ""
        guard !content.isEmpty else {
            lastDebugLog = "[\(timeStr())] 收到空短信，跳过"
            return
        }

        // 去重：5 秒内相同内容跳过（WS 和 poller 可能同时推送同一条短信）
        let now = Date()
        if content == lastProcessedContent && now.timeIntervalSince(lastProcessedTime) < 5 {
            print("[LiveActivity] duplicate SMS skipped: \(String(content.prefix(60)))")
            return
        }
        lastProcessedContent = content
        lastProcessedTime = now

        let rules = RuleStore.shared.matchingRules(deviceId: deviceId, content: content)
        guard let rule = rules.first else {
            lastDebugLog = "[\(timeStr())] 设备\(deviceId)无匹配规则（共\(RuleStore.shared.rules.count)条规则）\n短信: \(String(content.prefix(60)))"
            return
        }
        guard let code = CodeExtractor.code(from: content) else {
            lastDebugLog = "[\(timeStr())] 规则匹配但未提取到验证码\n短信: \(String(content.prefix(60)))"
            return
        }

        let projectName = CodeExtractor.projectName(from: content, fallback: sms.name)
        let sender = (sms.name?.isEmpty == false ? sms.name : sms.number) ?? "未知发送方"
        lastDebugLog = "[\(timeStr())] 启动灵动岛: \(projectName) \(code)"
        startActivity(rule: rule, projectName: projectName, code: code, sender: sender, deviceName: deviceName)
    }

    /// 手动测试灵动岛（不经过 WebSocket，直接启动）
    func testActivity() {
        let testRule = CodeRule(deviceId: 0, deviceName: "测试设备", keyword: "", enabled: true, autoEndMinutes: 2)
        lastDebugLog = "[\(timeStr())] 手动测试灵动岛..."
        startActivity(rule: testRule, projectName: "测试项目", code: "123456", sender: "测试发送方", deviceName: "测试设备")
    }

    private func timeStr() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }

    /// 启动灵动岛（同规则先结束旧的，避免重复）
    func startActivity(rule: CodeRule, projectName: String, code: String, sender: String, deviceName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[LiveActivity] activities not enabled (user may have disabled in Settings)")
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
            print("[LiveActivity] activity started successfully: project=\(projectName) code=\(code)")

            // 到时自动结束
            let ruleId = rule.id
            DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(minutes * 60)) { [weak self] in
                self?.endActivity(ruleId: ruleId)
            }
        } catch {
            print("[LiveActivity] failed to start activity: \(error.localizedDescription)")
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
