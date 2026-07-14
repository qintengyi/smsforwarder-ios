import Foundation
import SwiftUI

// MARK: - 日期格式化（北京时间）

enum DateUtil {
    /// 北京时间格式化器：yyyy-MM-dd HH:mm:ss
    static let beijingFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()

    /// 将毫秒时间戳格式化为北京时间字符串
    static func format(timestamp ms: Int64?) -> String {
        guard let ms = ms, ms > 0 else { return "-" }
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        return beijingFormatter.string(from: date)
    }

    /// 将毫秒时间戳格式化为短日期（仅年月日）
    static func formatShort(timestamp ms: Int64?) -> String {
        guard let ms = ms, ms > 0 else { return "-" }
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return f.string(from: date)
    }
}

// MARK: - 卡片容器修饰器

/// iOS 18 风格的圆角卡片背景
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

extension View {
    /// 应用 iOS 18 风格卡片背景
    func cardStyle() -> some View {
        modifier(CardBackground())
    }
}

// MARK: - SIM 标识

enum SIMLabel {
    static func text(_ simId: Int?) -> String {
        switch simId {
        case 0: return "SIM1"
        case 1: return "SIM2"
        default: return "SIM"
        }
    }
}

// MARK: - 通话类型显示

enum CallTypeLabel {
    static func text(_ type: Int?) -> String {
        switch type {
        case 1: return "呼入"
        case 2: return "呼出"
        case 3: return "未接"
        default: return "未知"
        }
    }

    static func color(_ type: Int?) -> Color {
        switch type {
        case 1: return .green
        case 2: return .blue
        case 3: return .red
        default: return .secondary
        }
    }
}

// MARK: - 电量状态显示

enum BatteryStatusLabel {
    static func text(_ status: String?) -> String {
        guard let s = status else { return "未知" }
        switch s.lowercased() {
        case "charging": return "充电中"
        case "discharging": return "使用中"
        case "full": return "已充满"
        case "not-charging", "notcharging": return "未充电"
        default: return s
        }
    }

    static func color(_ status: String?) -> Color {
        guard let s = status else { return .secondary }
        switch s.lowercased() {
        case "charging", "full": return .green
        case "discharging": return .orange
        default: return .secondary
        }
    }
}

// MARK: - 电量百分比颜色

enum BatteryLevelColor {
    static func color(_ level: Int?) -> Color {
        guard let l = level else { return .secondary }
        if l >= 50 { return .green }
        if l >= 20 { return .orange }
        return .red
    }
}
