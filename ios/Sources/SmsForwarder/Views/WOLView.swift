import SwiftUI
import Observation

// MARK: - WOL ViewModel

@Observable
final class WOLViewModel {
    var mac: String = ""
    var ip: String = ""
    var port: Int = 9
    var isSending: Bool = false
    var successMessage: String?
    var showSuccess: Bool = false
    var errorMessage: String?
    var showError: Bool = false

    private let api = SmsForwarderAPI.shared

    var sendDisabled: Bool {
        let trimmed = mac.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || isSending
    }

    func send() async {
        isSending = true
        defer { isSending = false }
        do {
            let msg = try await api.sendWOL(
                mac: mac.trimmingCharacters(in: .whitespacesAndNewlines),
                ip: ip.trimmingCharacters(in: .whitespacesAndNewlines),
                port: port
            )
            successMessage = msg
            showSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - WOL 视图

struct WOLView: View {
    @State private var vm = WOLViewModel()

    var body: some View {
        Form {
            Section("远程唤醒参数") {
                TextField("MAC 地址（必填，如 AA:BB:CC:DD:EE:FF）", text: $vm.mac, axis: .vertical)
                    .keyboardType(.asciiCapable)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .lineLimit(1...2)
                TextField("IP 地址 / 子网广播（选填）", text: $vm.ip)
                    .keyboardType(.decimalPad)
                    .autocorrectionDisabled()
                Stepper("端口：\(vm.port)", value: $vm.port, in: 1...65535)
            }

            Section {
                Button {
                    Task { await vm.send() }
                } label: {
                    HStack {
                        if vm.isSending {
                            ProgressView()
                                .padding(.trailing, 4)
                        }
                        Text(vm.isSending ? "发送中..." : "发送唤醒指令")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(vm.sendDisabled)
            }

            Section("使用说明") {
                Text("1. 需要目标主机 BIOS/网卡支持 Wake-On-LAN 功能并已开启。\n2. MAC 地址格式为 6 段十六进制，可用冒号、短横或无分隔。\n3. 端口默认为 9，部分设备使用 7。\n4. IP 字段留空时使用广播地址。\n5. 设备需与目标主机处于同一局域网。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("远程唤醒")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.bar, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .alert("提示", isPresented: $vm.showSuccess, actions: {
            Button("好") {}
        }, message: {
            Text(vm.successMessage ?? "操作成功")
        })
        .alert("出错", isPresented: $vm.showError, actions: {
            Button("好") {}
        }, message: {
            Text(vm.errorMessage ?? "")
        })
    }
}

#Preview {
    NavigationStack {
        WOLView()
    }
}
