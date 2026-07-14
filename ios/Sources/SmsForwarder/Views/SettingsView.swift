import SwiftUI
import Observation

// MARK: - 设置 ViewModel

@Observable
final class SettingsViewModel {
    var deviceIP: String
    var devicePort: Int
    var secretKey: String
    var isTesting: Bool = false
    var showAlert: Bool = false
    var alertTitle: String = ""
    var alertMessage: String = ""

    private let store = SettingsStore.shared
    private let api = SmsForwarderAPI.shared

    init() {
        let settings = store.settings
        self.deviceIP = settings.deviceIP
        self.devicePort = settings.devicePort
        self.secretKey = settings.secretKey
    }

    var portText: String {
        get { String(devicePort) }
        set { devicePort = Int(newValue) ?? devicePort }
    }

    func save() {
        store.save(AppSettings(
            deviceIP: deviceIP.trimmingCharacters(in: .whitespacesAndNewlines),
            devicePort: devicePort,
            secretKey: secretKey
        ))
        alertTitle = "已保存"
        alertMessage = "设备连接配置已保存。"
        showAlert = true
    }

    func testConnection() async {
        isTesting = true
        defer { isTesting = false }
        store.save(AppSettings(
            deviceIP: deviceIP.trimmingCharacters(in: .whitespacesAndNewlines),
            devicePort: devicePort,
            secretKey: secretKey
        ))
        do {
            _ = try await api.queryConfig()
            alertTitle = "连接成功"
            alertMessage = "设备已响应 config/query。"
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
            Section("设备地址") {
                TextField("设备 IP", text: $vm.deviceIP)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("端口", value: $vm.devicePort, format: .number)
                    .keyboardType(.numberPad)
            } footer: {
                Text("默认地址为 192.168.1.16:5000，请确保 iPhone 与 SmsForwarder 设备在同一局域网。")
            }

            Section("安全密钥") {
                SecureField("Secret Key", text: $vm.secretKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                Text("该密钥用于生成 HMAC-SHA256 签名，需要与 SmsForwarder 服务端配置一致。")
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
