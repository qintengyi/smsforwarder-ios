import SwiftUI
import Observation

// MARK: - 设置 ViewModel

@Observable
final class SettingsViewModel {
    var serverURL: String
    var isTesting: Bool = false
    var showAlert: Bool = false
    var alertTitle: String = ""
    var alertMessage: String = ""
    var showLogoutConfirm: Bool = false

    private let store = SettingsStore.shared
    private let api = SmsForwarderAPI.shared
    var appState: AppStateManager?

    init() {
        let settings = store.settings
        self.serverURL = settings.serverURL
    }

    func save() {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        var settings = store.settings
        settings.serverURL = trimmed
        store.save(settings)
        alertTitle = "已保存"
        alertMessage = "面板地址已保存。"
        showAlert = true
    }

    func testConnection() async {
        isTesting = true
        defer { isTesting = false }
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        var settings = store.settings
        settings.serverURL = trimmed
        store.save(settings)
        do {
            let devices = try await api.fetchDevices()
            alertTitle = "连接成功"
            alertMessage = "面板已响应，当前共有 \(devices.count) 台设备。"
            showAlert = true
        } catch {
            alertTitle = "连接失败"
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    func logout() {
        appState?.logout()
    }
}

// MARK: - 设置视图

struct SettingsView: View {
    @Environment(AppStateManager.self) private var appState
    @State private var vm = SettingsViewModel()
    @State private var monitoringEnabled: Bool = false

    var body: some View {
        Form {
            Section {
                TextField("https://smsf.xiaoyyua.top", text: $vm.serverURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("面板地址")
            } footer: {
                Text("填入 SmsForwarder 控制面板的完整地址。")
            }

            Section {
                Button {
                    vm.save()
                } label: {
                    Label("保存设置", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }

                Button {
                    Task { await vm.testConnection() }
                } label: {
                    HStack {
                        if vm.isTesting {
                            ProgressView()
                                .padding(.trailing, 4)
                        }
                        Label(vm.isTesting ? "测试中..." : "测试连接", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(vm.isTesting)
            }

            Section {
                if let username = SettingsStore.shared.settings.username {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .foregroundStyle(.blue)
                        Text(username)
                            .font(.body)
                        Spacer()
                        Text("已登录")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                Button(role: .destructive) {
                    vm.showLogoutConfirm = true
                } label: {
                    Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity)
                }
            } header: {
                Text("账号")
            }

            Section {
                Toggle(isOn: $monitoringEnabled) {
                    Label("后台监听验证码", systemImage: "wave.3.right")
                }
                .onChange(of: monitoringEnabled) { _, value in
                    UserDefaults.standard.set(value, forKey: "io.smsforwarder.monitoringEnabled")
                    MonitoringCoordinator.shared.apply()
                }

                NavigationLink {
                    CodeRulesView()
                } label: {
                    Label("订阅规则", systemImage: "list.bullet.rectangle")
                }
            } header: {
                Text("验证码灵动岛")
            } footer: {
                Text("开启后通过低功耗定位保持后台连接，收到匹配规则的验证码时在灵动岛显示。后台时通过本地通知可靠推送验证码，不会因系统限制丢失。")
            }

            Section {
                let ws = WebSocketClient.shared
                let poller = BackgroundPoller.shared
                let ka = KeepAliveManager.shared
                let la = LiveActivityManager.shared
                let mc = MonitoringCoordinator.shared
                let rs = RuleStore.shared

                HStack {
                    Text("监听开关")
                    Spacer()
                    Text(mc.enabled ? "已开启" : "未开启")
                        .foregroundStyle(mc.enabled ? .green : .secondary)
                }
                HStack {
                    Text("订阅规则")
                    Spacer()
                    Text(rs.rules.isEmpty ? "无（需添加）" : "\(rs.rules.count) 条")
                        .foregroundStyle(rs.rules.isEmpty ? .red : .secondary)
                }
                if !rs.rules.isEmpty {
                    HStack {
                        Text("订阅设备")
                        Spacer()
                        Text(rs.subscribedDeviceIds.isEmpty ? "无" : rs.subscribedDeviceIds.map { String($0) }.joined(separator: ","))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("定位保活")
                    Spacer()
                    Text(ka.isKeepingAlive ? "运行中" : "未运行")
                        .foregroundStyle(ka.isKeepingAlive ? .green : .red)
                }
                if ka.isKeepingAlive {
                    HStack {
                        Text("保活启动于")
                        Spacer()
                        Text(ka.startedAt).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("定位授权")
                        Spacer()
                        Text(ka.authStatus).foregroundStyle(.secondary)
                    }
                    if !ka.lastWakeTime.isEmpty {
                        HStack {
                            Text("最近唤醒")
                            Spacer()
                            Text(ka.lastWakeTime).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text("唤醒次数")
                        Spacer()
                        Text("\(ka.wakeCount)").foregroundStyle(.secondary)
                    }
                }
                if !ka.lastError.isEmpty {
                    HStack {
                        Text("保活错误")
                        Spacer()
                        Text(ka.lastError).font(.caption).foregroundStyle(.red).lineLimit(2)
                    }
                }
                HStack {
                    Text("WS 连接")
                    Spacer()
                    Text(ws.isConnected ? "已连接" : "未连接")
                        .foregroundStyle(ws.isConnected ? .green : .red)
                }
                HStack {
                    Text("后台轮询")
                    Spacer()
                    Text(poller.isPolling ? "运行中" : "已停止")
                        .foregroundStyle(poller.isPolling ? .green : .secondary)
                }
                if poller.isPolling {
                    HStack {
                        Text("轮询次数")
                        Spacer()
                        Text("\(poller.pollCount)").foregroundStyle(.secondary)
                    }
                    if !poller.lastPollTime.isEmpty {
                        HStack {
                            Text("上次轮询")
                            Spacer()
                            Text(poller.lastPollTime).foregroundStyle(.secondary)
                        }
                    }
                }
                HStack {
                    Text("WS 连接次数")
                    Spacer()
                    Text("\(ws.connectCount)").foregroundStyle(.secondary)
                }
                HStack {
                    Text("灵动岛可用")
                    Spacer()
                    Text(la.activitiesEnabled ? "是" : "否（系统设置中未开启）")
                        .foregroundStyle(la.activitiesEnabled ? .green : .red)
                }
                HStack {
                    Text("通知权限")
                    Spacer()
                    Text(la.notificationAuthorized ? "已授权" : "未授权")
                        .foregroundStyle(la.notificationAuthorized ? .green : .red)
                }
                if !la.lastUpdatePath.isEmpty {
                    HStack {
                        Text("更新路径")
                        Spacer()
                        Text(la.lastUpdatePath).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if la.pendingCount > 0 {
                    HStack {
                        Text("待显示")
                        Spacer()
                        Text("\(la.pendingCount) 条待显示").foregroundStyle(.orange)
                    }
                }
                if let err = ws.lastError, !err.isEmpty {
                    HStack {
                        Text("WS 错误")
                        Spacer()
                        Text(err).font(.caption).foregroundStyle(.red).lineLimit(2)
                    }
                }
                if !ws.lastReceivedSMSContent.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("最后收到短信").font(.caption).foregroundStyle(.secondary)
                        Text("[\(ws.lastReceivedSMSTime)] \(ws.lastReceivedSMSContent)")
                            .font(.caption2)
                            .lineLimit(3)
                    }
                }
                if !la.lastDebugLog.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("灵动岛日志").font(.caption).foregroundStyle(.secondary)
                        Text(la.lastDebugLog).font(.caption2).lineLimit(5)
                    }
                }

                Button {
                    la.testActivity()
                } label: {
                    Label("测试灵动岛", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
            } header: {
                Text("调试信息")
            } footer: {
                Text("前台 WebSocket + HTTP 轮询双保险，后台仅 HTTP 轮询。定位保活使用基站定位（极低功耗）。收到匹配规则的验证码时在灵动岛显示。")
            }

            Section {
                Text("iOS App 通过控制面板的 JSON API 获取数据。面板管理多台 SmsForwarder 设备，登录后可在仪表盘切换设备。所有数据请求通过面板代理转发到设备。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("说明")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.bar, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .alert(vm.alertTitle, isPresented: $vm.showAlert, actions: {
            Button("好") {}
        }, message: {
            Text(vm.alertMessage)
        })
        .alert("退出登录", isPresented: $vm.showLogoutConfirm, actions: {
            Button("取消", role: .cancel) {}
            Button("退出", role: .destructive) {
                vm.logout()
            }
        }, message: {
            Text("退出后将返回登录页面，需要重新输入用户名和密码。")
        })
        .onAppear {
            vm.appState = appState
            monitoringEnabled = UserDefaults.standard.object(forKey: "io.smsforwarder.monitoringEnabled") as? Bool ?? false
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(AppStateManager())
    }
}
