import SwiftUI
import Observation

// MARK: - 联系人 ViewModel

@Observable
final class ContactsViewModel {
    enum Mode: Int, CaseIterable, Identifiable {
        case query = 0
        case add = 1
        var id: Int { rawValue }
        var title: String { self == .query ? "查询" : "添加" }
    }

    var mode: Mode = .query

    // 查询表单
    var queryPhoneNumber: String = ""
    var queryName: String = ""

    // 添加表单
    var addPhoneNumber: String = ""
    var addName: String = ""

    // 结果
    var contacts: [Contact] = []
    var isLoading: Bool = false
    var isAdding: Bool = false
    var errorMessage: String?
    var showError: Bool = false
    var successMessage: String?
    var showSuccess: Bool = false

    private let api = SmsForwarderAPI.shared

    var addDisabled: Bool {
        addPhoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAdding
    }

    func query() async {
        isLoading = true
        defer { isLoading = false }
        do {
            contacts = try await api.queryContacts(
                phoneNumber: queryPhoneNumber,
                name: queryName
            )
            if contacts.isEmpty {
                errorMessage = "未查询到联系人"
                showError = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func add() async {
        isAdding = true
        defer { isAdding = false }
        do {
            let msg = try await api.addContact(
                phoneNumber: addPhoneNumber,
                name: addName
            )
            successMessage = msg
            showSuccess = true
            addPhoneNumber = ""
            addName = ""
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - 联系人视图

struct ContactsView: View {
    @State private var vm = ContactsViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $vm.mode) {
                    ForEach(ContactsViewModel.Mode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                if vm.mode == .query {
                    queryForm
                } else {
                    addForm
                }
            }
            .navigationTitle("联系人")
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

    // MARK: - 查询表单

    private var queryForm: some View {
        VStack(spacing: 0) {
            Form {
                Section("查询条件") {
                    TextField("号码", text: $vm.queryPhoneNumber)
                        .keyboardType(.phonePad)
                    TextField("姓名", text: $vm.queryName)
                        .keyboardType(.default)
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

            if !vm.contacts.isEmpty {
                List {
                    ForEach(vm.contacts) { contact in
                        contactRow(contact)
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    await vm.query()
                }
            } else if !vm.isLoading {
                ContentUnavailableViewCompat(
                    title: "暂无联系人",
                    icon: "person.crop.circle.badge.questionmark",
                    description: "输入号码或姓名后查询"
                )
                .padding(.top, 20)
            }
        }
    }

    // MARK: - 添加表单

    private var addForm: some View {
        Form {
            Section("添加联系人") {
                TextField("号码（必填，多个号码用分号分隔）", text: $vm.addPhoneNumber, axis: .vertical)
                    .keyboardType(.phonePad)
                    .lineLimit(1...3)
                TextField("姓名（选填）", text: $vm.addName)
                    .keyboardType(.default)
            }
            Section {
                Button {
                    Task { await vm.add() }
                } label: {
                    HStack {
                        if vm.isAdding {
                            ProgressView()
                                .padding(.trailing, 4)
                        }
                        Text(vm.isAdding ? "添加中..." : "添加联系人")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(vm.addDisabled)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
    }

    private func contactRow(_ contact: Contact) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "person.fill")
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(contact.name ?? "未命名")
                    .font(.headline)
                Text(contact.phone_number ?? "-")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContactsView()
}
