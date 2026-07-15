import ActivityKit
import Foundation
import Observation

// MARK: - 灵动岛管理器

/// 根据订阅规则匹配短信，启动 / 更新 / 结束灵动岛 Live Activity
///
/// 关键机制：
/// - `Activity.request()` 只能在前台调用（iOS 限制）
/// - `activity.update()` 可在后台调用
/// - 所以前台时预启动一个"待命"Live Activity，后台收到验证码时 update 更新内容
@Observable
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    /// 待命活动（前台预启动，后台用 update 更新）
    private var standbyActivity: Activity<CodeActivityAttributes>?

    /// 调试信息
    var lastDebugLog: String = ""
    var activitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// 去重：5 秒内相同内容的短信不重复处理
    private var lastProcessedContent: String = ""
    private var lastProcessedTime: Date = .distantPast

    /// 自动重置定时器（验证码显示超时后回到待命状态）
    private var resetTimer: Timer?

    // MARK: - 待命活动管理

    /// 前台调用：启动待命 Live Activity
    /// 必须在 App 前台时调用（Activity.request() 限制）
    func startStandby() {
        guard activitiesEnabled else {
            print("[LiveActivity] cannot start standby: activities not enabled")
            return
        }

        // 如果已有待命活动，不重复启动
        if standbyActivity != nil {
            print("[LiveActivity] standby already exists")
            return
        }

        let attributes = CodeActivityAttributes(ruleId: "standby")
        let state = CodeActivityAttributes.ContentState(
            projectName: "",
            code: "",
            sender: "",
            deviceName: "",
            receivedTime: Date(),
            isIdle: true
        )

        do {
            let content = ActivityContent(state: state, staleDate: nil)
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            standbyActivity = activity
            lastDebugLog = "[\(timeStr())] 待命灵动岛已启动"
            print("[LiveActivity] standby activity started")
        } catch {
            lastDebugLog = "[\(timeStr())] 启动待命失败: \(error.localizedDescription)"
            print("[LiveActivity] failed to start standby: \(error.localizedDescription)")
        }
    }

    /// 停止待命活动
    func stopStandby() {
        resetTimer?.invalidate()
        resetTimer = nil
        if let activity = standbyActivity {
            Task { await activity.end(dismissalPolicy: .immediate) }
            standbyActivity = nil
            print("[LiveActivity] standby activity stopped")
        }
    }

    // MARK: - 短信处理

    /// 处理一条收到的实时短信
    func handleSMS(deviceId: Int, deviceName: String, sms: WSSmsRecord) {
        let content = sms.content ?? ""
        guard !content.isEmpty else {
            lastDebugLog = "[\(timeStr())] 收到空短信，跳过"
            return
        }

        // 去重：5 秒内相同内容跳过
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

        // 更新灵动岛显示验证码
        updateWithCode(
            rule: rule,
            projectName: projectName,
            code: code,
            sender: sender,
            deviceName: deviceName
        )
    }

    /// 手动测试灵动岛（不经过 WebSocket，直接更新）
    func testActivity() {
        let testRule = CodeRule(deviceId: 0, deviceName: "测试设备", keyword: "", enabled: true, autoEndMinutes: 2)
        updateWithCode(
            rule: testRule,
            projectName: "测试项目",
            code: "123456",
            sender: "测试发送方",
            deviceName: "测试设备"
        )
    }

    // MARK: - 核心更新逻辑

    /// 更新灵动岛显示验证码
    /// 如果有待命活动，用 update 更新（后台可用）；否则用 request 启动（仅前台）
    private func updateWithCode(rule: CodeRule, projectName: String, code: String, sender: String, deviceName: String) {
        lastDebugLog = "[\(timeStr())] 显示验证码: \(projectName) \(code)"

        let state = CodeActivityAttributes.ContentState(
            projectName: projectName,
            code: code,
            sender: sender,
            deviceName: deviceName,
            receivedTime: Date(),
            isIdle: false
        )

        if let activity = standbyActivity {
            // 待命活动存在：用 update 更新（后台也可用）
            let minutes = max(1, rule.autoEndMinutes)
            let staleDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
            let content = ActivityContent(state: state, staleDate: staleDate)
            Task { await activity.update(content) }
            print("[LiveActivity] updated standby activity: project=\(projectName) code=\(code)")

            // 设置超时后回到待命状态
            scheduleResetToIdle(minutes: minutes)
        } else {
            // 没有待命活动：尝试 request 启动（仅前台可用）
            startActivity(rule: rule, state: state)
        }
    }

    /// 前台启动新 Live Activity（无待命活动时的后备方案）
    private func startActivity(rule: CodeRule, state: CodeActivityAttributes.ContentState) {
        guard activitiesEnabled else {
            print("[LiveActivity] activities not enabled")
            return
        }

        let attributes = CodeActivityAttributes(ruleId: rule.id)
        let minutes = max(1, rule.autoEndMinutes)
        let staleDate = Date().addingTimeInterval(TimeInterval(minutes * 60))

        do {
            let content = ActivityContent(state: state, staleDate: staleDate)
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            // 保存为待命活动，超时后可重置
            standbyActivity = activity
            print("[LiveActivity] activity started via request: project=\(state.projectName) code=\(state.code)")
            lastDebugLog = "[\(timeStr())] 验证码已显示: \(state.projectName) \(state.code)"

            scheduleResetToIdle(minutes: minutes)
        } catch {
            print("[LiveActivity] request failed: \(error.localizedDescription)")
            lastDebugLog = "[\(timeStr())] 显示失败: \(error.localizedDescription)"
        }
    }

    // MARK: - 超时重置

    /// 超时后将灵动岛重置回待命状态
    private func scheduleResetToIdle(minutes: Int) {
        resetTimer?.invalidate()
        let ruleId = standbyActivity?.attributes.ruleId ?? ""
        resetTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: false) { [weak self] _ in
            self?.resetToIdle()
        }
    }

    /// 重置为待命状态
    private func resetToIdle() {
        guard let activity = standbyActivity else { return }
        let idleState = CodeActivityAttributes.ContentState(
            projectName: "",
            code: "",
            sender: "",
            deviceName: "",
            receivedTime: Date(),
            isIdle: true
        )
        let content = ActivityContent(state: idleState, staleDate: nil)
        Task { await activity.update(content) }
        lastDebugLog = "[\(timeStr())] 灵动岛已重置为待命"
        print("[LiveActivity] reset to idle")
    }

    // MARK: - 清理

    /// 结束所有活动（退出登录时调用）
    func endAll() {
        resetTimer?.invalidate()
        resetTimer = nil
        if let activity = standbyActivity {
            Task { await activity.end(dismissalPolicy: .immediate) }
            standbyActivity = nil
        }
    }

    /// 清理上次 App 运行残留的 Live Activity（启动时调用）
    func cleanupStale() {
        for activity in Activity<CodeActivityAttributes>.activities {
            Task { await activity.end(dismissalPolicy: .immediate) }
        }
        standbyActivity = nil
    }

    private func timeStr() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}
