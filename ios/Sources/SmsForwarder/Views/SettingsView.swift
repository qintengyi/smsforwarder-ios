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

    private let store = SettingsStore.shared
    private let api = SmsForwarderAPI.shared

    init() {
        let settings = store.settings
        self.serverURL = settings.serverURL
    }

    func save() {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        store.save(AppSettings(serverURL: trimmed))
        alertTitle = "已保存"
        alertMessage = "Web 面板地址已保存。"
        showAlert = true
    }

    func testConnection() async {
        isTesting = true
        defer { isTesting = false }
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        store.save(AppSettings(serverURL: trimmed))
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
}

// MARK: - 设置视图

struct SettingsView: View {
    @State private var vm = SettingsViewModel()

    var body: some View {
        Form {
            Section {
                TextField("http://192.168.1.100:5001", text: $vm.serverURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Web 面板地址")
            } footer: {
                Text("填入 SmsForwarder Web 控制面板的完整地址（含端口号）。iPhone 需与面板所在服务器网络互通。")
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
                Text("iOS App 通过 Web 面板的 JSON API 获取数据，面板内部管理 SmsForwarder 设备的 IP、端口和签名密钥。无需在手机端逐台配置设备。")
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
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
