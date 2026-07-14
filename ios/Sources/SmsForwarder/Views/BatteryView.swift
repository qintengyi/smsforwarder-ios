import SwiftUI
import Observation

// MARK: - 电量 ViewModel

@Observable
final class BatteryViewModel {
    var battery: BatteryInfo?
    var isLoading: Bool = false
    var errorMessage: String?
    var showError: Bool = false

    private let api = SmsForwarderAPI.shared

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            battery = try await api.queryBattery()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - 电量视图

struct BatteryView: View {
    @State private var vm = BatteryViewModel()

    var body: some View {
        Form {
            if let battery = vm.battery {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            batteryVisual(level: battery.level)
                            Text("\(battery.level ?? 0)%")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundStyle(BatteryLevelColor.color(battery.level))
                            Text(BatteryStatusLabel.text(battery.status))
                                .font(.subheadline)
                                .foregroundStyle(BatteryStatusLabel.color(battery.status))
                        }
                        Spacer()
                    }
                    .padding(.vertical, 16)
                }

                Section("电池信息") {
                    infoRow("健康状态", value: healthText(battery.health))
                    infoRow("电源状态", value: pluggedText(battery.plugged))
                    infoRow("电压", value: voltageText(battery.voltage))
                    infoRow("温度", value: temperatureText(battery.temperature))
                }
            } else if vm.isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("查询中...")
                        Spacer()
                    }
                    .padding(.vertical, 24)
                }
            } else {
                Section {
                    ContentUnavailableViewCompat(
                        title: "暂无电量信息",
                        icon: "battery.100",
                        description: "点击下方刷新获取"
                    )
                    .padding(.vertical, 24)
                }
            }

            Section {
                Button {
                    Task { await vm.refresh() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .disabled(vm.isLoading)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("电量")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.bar, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .refreshable {
            await vm.refresh()
        }
        .alert("出错", isPresented: $vm.showError, actions: {
            Button("好") {}
        }, message: {
            Text(vm.errorMessage ?? "")
        })
        .onAppear {
            if vm.battery == nil {
                Task { await vm.refresh() }
            }
        }
    }

    // MARK: - 子视图

    /// 电池可视化（简易 SF Symbol 填充比例）
    private func batteryVisual(level: Int?) -> some View {
        let pct = Double(max(0, min(100, level ?? 0))) / 100.0
        return ZStack(alignment: .leading) {
            // 外框
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.secondary, lineWidth: 2)
                .frame(width: 120, height: 56)
            // 电量填充
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(BatteryLevelColor.color(level))
                .frame(width: max(4, CGFloat(120 * pct) - 8), height: 48)
                .padding(.leading, 4)
            // 电池头
            Rectangle()
                .fill(Color.secondary)
                .frame(width: 6, height: 20)
                .offset(x: 123, y: 0)
        }
        .frame(width: 140, height: 60)
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(.primary)
        }
    }

    // MARK: - 文本转换

    private func healthText(_ health: String?) -> String {
        guard let h = health else { return "未知" }
        switch h.lowercased() {
        case "good": return "良好"
        case "overheat": return "过热"
        case "dead": return "已损坏"
        case "over_voltage", "overvoltage": return "电压过高"
        case "cold": return "过冷"
        case "unknown": return "未知"
        default: return h
        }
    }

    private func pluggedText(_ plugged: String?) -> String {
        guard let p = plugged else { return "未知" }
        switch p.lowercased() {
        case "ac": return "交流电源"
        case "usb": return "USB"
        case "wireless": return "无线充电"
        case "null", "": return "未接入"
        default: return p
        }
    }

    private func voltageText(_ voltage: Int?) -> String {
        guard let v = voltage else { return "-" }
        return String(format: "%d mV (%.2f V)", v, Double(v) / 1000.0)
    }

    private func temperatureText(_ temperature: Int?) -> String {
        guard let t = temperature else { return "-" }
        return String(format: "%.1f ℃", Double(t) / 10.0)
    }
}

#Preview {
    NavigationStack {
        BatteryView()
    }
}
