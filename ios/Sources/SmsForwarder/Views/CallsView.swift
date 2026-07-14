import SwiftUI
import Observation

// MARK: - 通话 ViewModel

@Observable
final class CallsViewModel {
    var queryType: Int = 0   // 0=全部, 1=呼入, 2=呼出, 3=未接
    var phoneNumber: String = ""
    var pageNum: Int = 1
    var pageSize: Int = 20

    var records: [CallRecord] = []
    var isLoading: Bool = false
    var errorMessage: String?
    var showError: Bool = false

    private let api = SmsForwarderAPI.shared

    func query() async {
        isLoading = true
        defer { isLoading = false }
        do {
            records = try await api.queryCalls(
                type: queryType,
                phoneNumber: phoneNumber,
                pageNum: pageNum,
                pageSize: pageSize
            )
            if records.isEmpty {
                errorMessage = "未查询到通话记录"
                showError = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - 通话视图

struct CallsView: View {
    @State private var vm = CallsViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section("查询条件") {
                        Picker("类型", selection: $vm.queryType) {
                            Text("全部").tag(0)
                            Text("呼入").tag(1)
                            Text("呼出").tag(2)
                            Text("未接").tag(3)
                        }
                        TextField("号码", text: $vm.phoneNumber)
                            .keyboardType(.phonePad)
                    }
                    Section("分页") {
                        Stepper("页码：\(vm.pageNum)", value: $vm.pageNum, in: 1...999)
                        Stepper("每页：\(vm.pageSize)", value: $vm.pageSize, in: 1...200)
                    }
                    Section {
                        Button {
                            Task { await vm.query() }
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
                            callRow(record)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        await vm.query()
                    }
                } else if !vm.isLoading {
                    ContentUnavailableViewCompat(
                        title: "暂无通话记录",
                        icon: "tray",
                        description: "配置查询条件后点击查询"
                    )
                    .padding(.top, 20)
                }
            }
            .navigationTitle("通话")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.bar, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("出错", isPresented: $vm.showError, actions: {
                Button("好") {}
            }, message: {
                Text(vm.errorMessage ?? "")
            })
        }
    }

    private func callRow(_ record: CallRecord) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(CallTypeLabel.color(record.type).opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: callIcon(record.type))
                    .foregroundStyle(CallTypeLabel.color(record.type))
            }
            VStack(alignment: .leading, spacing: 4) {
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
                Text(record.number ?? "-")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    Text(DateUtil.format(timestamp: record.dateLong))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("时长：\(record.duration ?? 0)秒")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                // 类型标签
                Text(CallTypeLabel.text(record.type))
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(CallTypeLabel.color(record.type).opacity(0.15))
                    .foregroundStyle(CallTypeLabel.color(record.type))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }

    private func callIcon(_ type: Int?) -> String {
        switch type {
        case 1: return "phone.arrow.down.left.fill"
        case 2: return "phone.arrow.up.right.fill"
        case 3: return "phone.down.fill"
        default: return "phone.fill"
        }
    }
}

#Preview {
    CallsView()
}
