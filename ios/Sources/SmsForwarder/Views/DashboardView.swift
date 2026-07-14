import SwiftUI
import Observation

// MARK: - 仪表盘 ViewModel

@Observable
final class DashboardViewModel {
    var isOnline: Bool = false
    var isChecking: Bool = false
    var config: DeviceConfig = DeviceConfig()
    var battery: BatteryInfo?
    var location: LocationInfo?
    var errorMessage: String?
    var showError: Bool = false

    private let api = SmsForwarderAPI.shared

    func checkDeviceStatus() async {
        isChecking = true
        defer { isChecking = false }
        do {
            let cfg = try await api.queryConfig()
            config = cfg
            isOnline = true
            // 顺带拉取电量与定位概览
            await fetchBattery()
            await fetchLocation()
        } catch {
            isOnline = false
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func fetchBattery() async {
        do {
            battery = try await api.queryBattery()
        } catch {
            battery = nil
        }
    }

    func fetchLocation() async {
        do {
            location = try await api.queryLocation()
        } catch {
            location = nil
        }
    }
}

// MARK: - 仪表盘视图

struct DashboardView: View {
    @State private var vm = DashboardViewModel()
    // 用于切换 ContentView 的 Tab
    @Binding var selectedTab: Int

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 设备状态卡片
                    statusCard

                    // 电量概览
                    batteryCard

                    // 定位概览
                    locationCard

                    // 快捷功能入口
                    quickActionsSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .navigationTitle("仪表盘")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.bar, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .refreshable {
                await vm.checkDeviceStatus()
            }
            .alert("无法连接设备", isPresented: $vm.showError, actions: {
                Button("好") {}
            }, message: {
                Text(vm.errorMessage ?? "")
            })
            .onAppear {
                Task {
                    if !vm.isOnline && !vm.isChecking {
                        await vm.checkDeviceStatus()
                    }
                }
            }
        }
    }

    // MARK: - 子视图

    private var statusCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(vm.isOnline ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: vm.isOnline ? "antenna.radiowaves.left.and.right" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(vm.isOnline ? .green : .red)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(vm.isOnline ? "设备在线" : "设备离线")
                    .font(.headline)
                if vm.isOnline {
                    if let model = vm.config.deviceModel, !model.isEmpty {
                        Text("型号：\(model)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let ver = vm.config.androidVersion, !ver.isEmpty {
                        Text("Android：\(ver)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("下拉刷新以重新连接设备")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if vm.isChecking {
                ProgressView()
            }
        }
        .cardStyle()
    }

    private var batteryCard: some View {
        Button {
            selectedTab = 4 // 切到「更多」Tab
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "battery.100")
                        .foregroundStyle(BatteryLevelColor.color(vm.battery?.level))
                    Text("电量概览")
                        .font(.headline)
                    Spacer()
                    Text(BatteryStatusLabel.text(vm.battery?.status))
                        .font(.caption)
                        .foregroundStyle(BatteryStatusLabel.color(vm.battery?.status))
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(vm.battery?.level ?? 0)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    Text("%")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(BatteryLevelColor.color(vm.battery?.level))

                if let plugged = vm.battery?.plugged, !plugged.isEmpty, plugged.lowercased() != "null" {
                    Text("电源：\(pluggedDisplay(plugged))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cardStyle()
    }

    private var locationCard: some View {
        Button {
            selectedTab = 4 // 切到「更多」Tab
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "location.fill")
                        .foregroundStyle(.blue)
                    Text("定位概览")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(vm.location?.address ?? "暂无定位信息")
                    .font(.subheadline)
                    .foregroundStyle(vm.location?.address == nil ? .secondary : .primary)
                    .lineLimit(3)
                HStack {
                    if let lat = vm.location?.latitude, let lng = vm.location?.longitude {
                        Text(String(format: "经纬度：%.6f, %.6f", lat, lng))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(DateUtil.format(timestamp: vm.location?.time))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cardStyle()
    }

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("快捷功能")
                .font(.headline)
                .padding(.horizontal, 4)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                Button { selectedTab = 1 } label: {
                    QuickActionItem(icon: "message.fill", title: "发短信", color: .green)
                }
                .buttonStyle(.plain)

                Button { selectedTab = 2 } label: {
                    QuickActionItem(icon: "phone.fill", title: "通话记录", color: .blue)
                }
                .buttonStyle(.plain)

                Button { selectedTab = 3 } label: {
                    QuickActionItem(icon: "person.fill", title: "联系人", color: .orange)
                }
                .buttonStyle(.plain)

                Button { selectedTab = 4 } label: {
                    QuickActionItem(icon: "powerplug", title: "远程唤醒", color: .purple)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }

    private func pluggedDisplay(_ plugged: String) -> String {
        switch plugged.lowercased() {
        case "ac": return "交流电源"
        case "usb": return "USB"
        case "wireless": return "无线充电"
        default: return plugged
        }
    }
}

// MARK: - 快捷功能项

struct QuickActionItem: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - 预览（提供默认 binding）

#Preview {
    DashboardView(selectedTab: .constant(0))
}
