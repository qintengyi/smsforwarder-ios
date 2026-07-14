import SwiftUI
import Observation

// MARK: - 短信 ViewModel

@Observable
final class SMSViewModel {
    enum Mode: Int, CaseIterable, Identifiable {
        case send = 0
        case query = 1
        var id: Int { rawValue }
        var title: String { self == .send ? "发送" : "查询" }
    }

    // 当前模式
    var mode: Mode = .send

    // 发送表单
    var sendSimSlot: Int = 1
    var sendPhoneNumbers: String = ""
    var sendContent: String = ""

    // 查询表单
    var queryType: Int = 1   // 1=接收, 2=发送
    var queryKeyword: String = ""
    var queryPageNum: Int = 1
    var queryPageSize: Int = 20

    // 结果
    var records: [SmsRecord] = []
    var isLoading: Bool = false
    var isSending: Bool = false
    var errorMessage: String?
    var showError: Bool = false
    var successMessage: String?
    var showSuccess: Bool = false

    private let api = SmsForwarderAPI.shared

    var sendDisabled: Bool {
        sendPhoneNumbers.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        sendContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        isSending
    }

    func sendSMS() async {
        isSending = true
        defer { isSending = false }
        do {
            let msg = try await api.sendSMS(
                simSlot: sendSimSlot,
                phoneNumbers: sendPhoneNumbers,
                msgContent: sendContent
            )
            successMessage = msg
            showSuccess = true
            sendContent = ""
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func querySMS() async {
        isLoading = true
        defer { isLoading = false }
        do {
            records = try await api.querySMS(
                type: queryType,
                pageNum: queryPageNum,
                pageSize: queryPageSize,
                keyword: queryKeyword
            )
            if records.isEmpty {
                errorMessage = "未查询到短信记录"
                showError = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - 短信视图

struct SMSView: View {
    @State private var vm = SMSViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $vm.mode) {
                    ForEach(SMSViewModel.Mode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                if vm.mode == .send {
                    sendForm
                } else {
                    queryForm
                }
            }
            .navigationTitle("短信")
            .navigationBarTitleDisplayMode(.large)
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

    // MARK: - 发送表单

    private var sendForm: some View {
        Form {
            Section("SIM 卡") {
                Picker("卡槽", selection: $vm.sendSimSlot) {
                    Text("SIM1").tag(1)
                    Text("SIM2").tag(2)
                }
                .pickerStyle(.segmented)
            }
            Section("接收号码") {
                TextField("多号码用分号(;)分隔", text: $vm.sendPhoneNumbers, axis: .vertical)
                    .keyboardType(.phonePad)
                    .lineLimit(1...3)
            }
            Section("短信内容") {
                TextEditor(text: $vm.sendContent)
                    .frame(minHeight: 120)
            }
            Section {
                Button {
                    Task { await vm.sendSMS() }
                } label: {
                    HStack {
                        if vm.isSending {
                            ProgressView()
                                .padding(.trailing, 4)
                        }
                        Text(vm.isSending ? "发送中..." : "发送短信")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(vm.sendDisabled)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - 查询表单

    private var queryForm: some View {
        VStack(spacing: 0) {
            Form {
                Section("查询条件") {
                    Picker("类型", selection: $vm.queryType) {
                        Text("接收").tag(1)
                        Text("发送").tag(2)
                    }
                    TextField("关键字", text: $vm.queryKeyword)
                        .keyboardType(.default)
                }
                Section("分页") {
                    Stepper("页码：\(vm.queryPageNum)", value: $vm.queryPageNum, in: 1...999)
                    Stepper("每页：\(vm.queryPageSize)", value: $vm.queryPageSize, in: 1...200)
                }
                Section {
                    Button {
                        Task { await vm.querySMS() }
                    } label: {
                        HStack {
                            if vm.isLoading {
                                ProgressView()
                                    .padding(.trailing, 4)
                            }
                            Text(vm.isLoading ? "查询中..." : "查询")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(vm.isLoading)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))

            if !vm.records.isEmpty {
                List {
                    ForEach(vm.records) { record in
                        smsRow(record)
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    await vm.querySMS()
                }
            } else if !vm.isLoading {
                ContentUnavailableViewCompat(
                    title: "暂无短信记录",
                    icon: "tray",
                    description: "配置查询条件后点击查询"
                )
                .padding(.top, 20)
            }
        }
    }

    private func smsRow(_ record: SmsRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(record.name ?? "未知联系人")
                    .font(.headline)
                Spacer()
                Text(SIMLabel.text(record.sim_id))
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
            }
            HStack(spacing: 4) {
                Image(systemName: "number")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(record.number ?? "-")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(record.content ?? "")
                .font(.subheadline)
                .lineLimit(4)
            HStack {
                Spacer()
                Text(DateUtil.format(timestamp: record.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - ContentUnavailableView 兼容（iOS 17 可用原生）

@available(iOS 17.0, *)
struct ContentUnavailableViewCompat: View {
    let title: String
    let icon: String
    let description: String?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            if let desc = description {
                Text(desc)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }
}

#Preview {
    SMSView()
}
