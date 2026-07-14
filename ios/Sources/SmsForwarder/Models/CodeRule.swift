import Foundation
import Observation

// MARK: - 验证码订阅规则

/// 一条「验证码灵动岛」订阅规则
struct CodeRule: Codable, Identifiable, Equatable {
    var id: String
    var deviceId: Int          // 订阅的设备 ID
    var deviceName: String     // 设备名（显示用，设备改名后可手动刷新）
    var keyword: String        // 短信内容需包含的关键字（如「验证码」），留空则匹配所有短信
    var enabled: Bool
    var autoEndMinutes: Int    // 灵动岛自动结束分钟

    init(id: String = UUID().uuidString,
         deviceId: Int,
         deviceName: String,
         keyword: String = "验证码",
         enabled: Bool = true,
         autoEndMinutes: Int = 5) {
        self.id = id
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.keyword = keyword
        self.enabled = enabled
        self.autoEndMinutes = autoEndMinutes
    }
}

// MARK: - 规则存储

/// 验证码订阅规则持久化（UserDefaults）
@Observable
final class RuleStore {
    static let shared = RuleStore()
    private let key = "io.smsforwarder.codeRules.v1"
    private let defaults: UserDefaults

    var rules: [CodeRule] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([CodeRule].self, from: data) else {
            rules = []
            return
        }
        rules = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(rules) {
            defaults.set(data, forKey: key)
        }
    }

    func add(_ rule: CodeRule) {
        rules.append(rule)
        persist()
    }

    func update(_ rule: CodeRule) {
        guard let idx = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[idx] = rule
        persist()
    }

    func delete(_ id: String) {
        rules.removeAll { $0.id == id }
        persist()
    }

    /// 查找匹配某设备某短信内容的启用规则
    func matchingRules(deviceId: Int, content: String) -> [CodeRule] {
        rules.filter { rule in
            guard rule.enabled, rule.deviceId == deviceId else { return false }
            if rule.keyword.isEmpty { return true }
            return content.localizedCaseInsensitiveContains(rule.keyword)
        }
    }

    /// 当前所有启用规则涉及的设备 ID
    var subscribedDeviceIds: Set<Int> {
        Set(rules.filter(\.enabled).map(\.deviceId))
    }
}

// MARK: - 验证码 / 项目名提取

enum CodeExtractor {
    /// 从短信内容提取项目名（中文方括号【】内的文字），回退用联系人名
    static func projectName(from content: String, fallback: String?) -> String {
        if let regex = try? NSRegularExpression(pattern: "【([^】]+)】"),
           let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
           match.numberOfRanges >= 2,
           let r = Range(match.range(at: 1), in: content) {
            let name = String(content[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        if let fb = fallback, !fb.isEmpty { return fb }
        return "验证码"
    }

    /// 从短信内容提取验证码
    /// 优先匹配「验证码/校验码/动态码」附近的 4-8 位数字，否则取首个 4-8 位数字
    static func code(from content: String) -> String? {
        let patterns = [
            "验证码[^0-9]{0,6}(\\d{4,8})",
            "校验码[^0-9]{0,6}(\\d{4,8})",
            "动态码[^0-9]{0,6}(\\d{4,8})",
            "code[^0-9]{0,4}(\\d{4,8})",
            "\\b(\\d{4,8})\\b"
        ]
        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
               match.numberOfRanges >= 2,
               let r = Range(match.range(at: 1), in: content) {
                return String(content[r])
            }
        }
        return nil
    }
}
