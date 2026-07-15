import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Widget Bundle 入口

@main
struct SmsForwarderWidgetBundle: WidgetBundle {
    var body: some Widget {
        CodeLiveActivity()
    }
}

// MARK: - 验证码灵动岛 / Live Activity

struct CodeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CodeActivityAttributes.self) { context in
            // 锁屏 / 通知中心 Live Activity
            LockScreenView(state: context.state)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                // 展开模式
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "number.circle.fill")
                            .foregroundStyle(.green)
                        Text(s.projectName)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(s.code)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.green)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        Label(s.sender, systemImage: "person.crop.circle")
                            .lineLimit(1)
                        Spacer()
                        Label(s.deviceName, systemImage: "iphone")
                            .lineLimit(1)
                        Text(s.receivedTime, style: .time)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "number.circle.fill")
                    .foregroundStyle(.green)
            } compactTrailing: {
                Text(s.code)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.green)
            } minimal: {
                Text(s.code)
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.green)
            }
        }
    }
}

// MARK: - 锁屏 Live Activity 视图

private struct LockScreenView: View {
    let state: CodeActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            // 左：项目名
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "number.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                    Text(state.projectName)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Text("验证码")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(state.sender, systemImage: "person.crop.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            // 右：验证码
            VStack(alignment: .trailing, spacing: 4) {
                Text(state.code)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.green)
                HStack(spacing: 4) {
                    Image(systemName: "iphone")
                        .font(.caption2)
                    Text(state.deviceName)
                        .font(.caption2)
                    Text(state.receivedTime, style: .time)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
