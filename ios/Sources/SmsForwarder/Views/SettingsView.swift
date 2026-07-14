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
        alertMessage = "Web 面板地址已保存。"
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
            _ = try await api.queryConfig()
            alertTitle = "连接成功"
            alertMessage = "Web 面板已响应，设备配置获取正常。"
            showAlert = true
        } catch {
            alertTitle = "连接失败"
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    func logout() {
        store.clearLogin()
        appState?.logout()
    }
}

// MARK: - 设置视图

struct SettingsView: View {
    @Environment(AppStateManager.self) private var appState
    @State private var vm = SettingsViewModel()

    var body: some View {
        Form {
            Section {
                TextField("https://smsf.xiaoyyua.top", text: $vm.serverURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Web 面板地址")
            } footer: {
                Text("填入 SmsForwarder Web 控制面板的完整地址。")
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
                Text("iOS App 通过 Web 面板的 JSON API 获取数据，登录后自动携带认证 token。面板内部管理 SmsForwarder 设备的 IP、端口和签名密钥。")
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
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(AppStateManager())
    }
}
