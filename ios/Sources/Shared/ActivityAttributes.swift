import ActivityKit
import Foundation

// MARK: - 灵动岛 / Live Activity 共享属性

/// 验证码灵动岛的活动属性
/// App 与 Widget Extension 共享此类型（各自编译一份），无需 App Group
struct CodeActivityAttributes: ActivityAttributes {
    /// 动态内容（可随时间更新）
    public struct ContentState: Codable, Hashable {
        /// 项目名，如「抖音」（从短信内容【】中提取）
        var projectName: String
        /// 验证码，如「2617」
        var code: String
        /// 发送方号码或名称
        var sender: String
        /// 设备名
        var deviceName: String
        /// 收到时间
        var receivedTime: Date
        /// 是否为待命状态（无验证码时显示"监听中"）
        var isIdle: Bool = false
    }

    /// 规则 ID，用于标识本次活动由哪条订阅规则触发
    var ruleId: String
}
