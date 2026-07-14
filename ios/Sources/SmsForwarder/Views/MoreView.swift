import SwiftUI

// MARK: - 更多视图

struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("设备") {
                    NavigationLink {
                        BatteryView()
                    } label: {
                        MoreRow(icon: "battery.100", title: "电量", subtitle: "查看电池状态与健康信息", color: .green)
                    }

                    NavigationLink {
                        LocationView()
                    } label: {
                        MoreRow(icon: "location.fill", title: "定位", subtitle: "查看设备位置与地图", color: .blue)
                    }
                }

                Section("工具") {
                    NavigationLink {
                        WOLView()
                    } label: {
                        MoreRow(icon: "powerplug", title: "远程唤醒", subtitle: "发送 Wake-On-LAN 唤醒包", color: .orange)
                    }
                }

                Section("配置") {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        MoreRow(icon: "gearshape.fill", title: "设置", subtitle: "面板地址与账号", color: .gray)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("更多")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.bar, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

private struct MoreRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.16))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    MoreView()
}
