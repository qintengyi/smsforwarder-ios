import ActivityKit
import Foundation
import Observation

// MARK: - 灵动岛管理器

/// 根据订阅规则匹配短信，启动 / 更新 / 结束灵动岛 Live Activity
///
/// 关键机制：
/// - `Activity.request()` 只能在前台调用（iOS 限制）
/// - `activity.update()` 可在后台调用
/// - 前台时预启动"待命"Live Activity，后台收到验证码用 update 更新
/// - 用 `Activity.activities` 查询真实活动状态，不依赖可能失效的引用
/// - 后台无活动时存储 pending SMS，回前台时补显示
@Observable
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    /// 调试信息
    var lastDebugLog: String = ""
    var activitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// 供调试面板查看：待命活动是否存在
    var standbyActive: Bool = false
    /// 供调试面板查看：上次更新走的路径
    var lastUpdatePath: String = ""
    /// 供调试面板查看：待显示的验证码数量
    var pendingCount: Int = 0

    /// 去重：5 秒内相同内容的短信不重复处理
    private var lastProcessedContent: String = ""
    private var lastProcessedTime: Date = .distantPast

    /// 自动重置定时器
    private var resetTimer: Timer?

    /// 后台无法启动 Live Activity 时暂存，回前台补显示
    private var pendingSMS: PendingCode?

    struct PendingCode {
        let rule: CodeRule
        let projectName: String
        let code: String
        let sender: String
        let deviceName: String
        let timestamp: Date
    }

    // MARK: - 待命活动管理

    /// 前台调用：启动待命 Live Activity
    func startStandby() {
        guard activitiesEnabled else {
            print("[LiveActivity] cannot start standby: activities not enabled")
            return
        }

        // 检查系统是否已有活跃的活动
        let existing = Activity<CodeActivityAttributes>.activities.filter { $0.activityState == .active }
        if !existing.isEmpty {
            print("[LiveActivity] found \(existing.count) existing active activity(ies), using first")
            standbyActive = true
            // 更新为待命状态
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
            let activity = try Activity.request(
                attributes: attributes, content: content, pushType: nil
            )
            standbyActive = true
            lastDebugLog = "[\(timeStr())] 待命灵动岛已启动"
            print("[LiveActivity] standby activity started, id=\(activity.id)")
        } catch {
            standbyActive = false
            lastDebugLog = "[\(timeStr())] 启动待命失败: \(error.localizedDescription)"
            print("[LiveActivity] failed to start standby: \(error.localizedDescription)")
        }
    }

    /// 停止待命活动
    func stopStandby() {
        resetTimer?.invalidate()
        resetTimer = nil
        for activity in Activity<CodeActivityAttributes>.activities {
            Task { await activity.end(dismissalPolicy: .immediate) }
        }
        standbyActive = false
        print("[LiveActivity] standby stopped")
    }

    // MARK: - 短信处理

    func handleSMS(deviceId: Int, deviceName: String, sms: WSSmsRecord) {
        let content = sms.content ?? ""
        guard !content.isEmpty else {
            lastDebugLog = "[\(timeStr())] 收到空短信，跳过"
            return
        }

        // 去重
        let now = Date()
        if content == lastProcessedContent && now.timeIntervalSince(lastProcessedTime) < 5 {
            print("[LiveActivity] duplicate SMS skipped")
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

    // MARK: - 核心更新逻辑

    private func updateWithCode(rule: CodeRule, projectName: String, code: String, sender: String, deviceName: String) {
        let state = CodeActivityAttributes.ContentState(
            projectName: projectName, code: code, sender: sender,
            deviceName: deviceName, receivedTime: Date(), isIdle: false
        )
        let minutes = max(1, rule.autoEndMinutes)
        let staleDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        let content = ActivityContent(state: state, staleDate: staleDate)

        // 查询系统真实的活跃活动（不依赖可能失效的引用）
        let activeActivities = Activity<CodeActivityAttributes>.activities.filter { $0.activityState == .active }

        if let activity = activeActivities.first {
            // 有活跃活动：用 update 更新（前台后台都可用）
            lastUpdatePath = "update(活动数:\(activeActivities.count))"
            lastDebugLog = "[\(timeStr())] 显示验证码: \(projectName) \(code)"
            standbyActive = true
            print("[LiveActivity] updating existing activity id=\(activity.id)")
            Task { await activity.update(content) }
            scheduleResetToIdle(minutes: minutes)
        } else {
            // 无活跃活动：尝试 request（仅前台可用）
            standbyActive = false
            do {
                let attributes = CodeActivityAttributes(ruleId: rule.id)
                let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
                lastUpdatePath = "request(成功)"
                lastDebugLog = "[\(timeStr())] 验证码已显示: \(projectName) \(code)"
                standbyActive = true
                print("[LiveActivity] started new activity via request, id=\(activity.id)")
                scheduleResetToIdle(minutes: minutes)
            } catch {
                // request 失败（很可能在后台）：存储 pending，回前台补显示
                lastUpdatePath = "pending(请求失败)"
                pendingSMS = PendingCode(rule: rule, projectName: projectName, code: code, sender: sender, deviceName: deviceName, timestamp: Date())
                pendingCount = 1
                lastDebugLog = "[\(timeStr())] ⚠️无活动且request失败: \(error.localizedDescription)\n验证码 \(code) 已暂存，回前台将补显示"
                print("[LiveActivity] request failed, stored pending: \(error.localizedDescription)")
            }
        }
    }

    /// 回到前台时处理暂存的验证码
    func processPending() {
        guard let pending = pendingSMS else { return }
        pendingSMS = nil
        pendingCount = 0
        print("[LiveActivity] processing pending SMS: \(pending.code)")

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
            lastDebugLog = "[\(timeStr())] 补显示验证码: \(pending.projectName) \(pending.code)"
            standbyActive = true
            scheduleResetToIdle(minutes: minutes)
        } else {
            do {
                let attributes = CodeActivityAttributes(ruleId: pending.rule.id)
                let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
                lastUpdatePath = "pending→request"
                lastDebugLog = "[\(timeStr())] 补显示验证码: \(pending.projectName) \(pending.code)"
                standbyActive = true
                scheduleResetToIdle(minutes: minutes)
            } catch {
                lastUpdatePath = "pending→失败"
                lastDebugLog = "[\(timeStr())] 补显示也失败: \(error.localizedDescription)"
                print("[LiveActivity] pending request also failed: \(error.localizedDescription)")
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
        lastDebugLog = "[\(timeStr())] 灵动岛已重置为待命"
        print("[LiveActivity] reset to idle")
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
