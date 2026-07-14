import SwiftUI

// MARK: - 验证码订阅规则列表

struct CodeRulesView: View {
    @Environment(AppStateManager.self) private var appState
    @State private var ruleStore = RuleStore.shared
    @State private var showAddSheet = false
    @State private var editingRule: CodeRule?

    var body: some View {
        List {
            if ruleStore.rules.isEmpty {
                Section {
                    ContentUnavailableViewCompat(
                        title: "暂无订阅规则",
                        icon: "bell.slash",
                        description: "添加规则后，收到匹配的验证码将显示在灵动岛"
                    )
                    .padding(.vertical, 12)
                }
            } else {
                ForEach(ruleStore.rules) { rule in
                    ruleRow(rule)
                        .contextMenu {
                            Button { editingRule = rule } label: { Label("编辑", systemImage: "pencil") }
                            Button(role: .destructive) { ruleStore.delete(rule.id) } label: { Label("删除", systemImage: "trash") }
                        }
                }
            }
        }
        .navigationTitle("验证码灵动岛")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.bar, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddSheet = true } label: { Image(systemName: "plus") }
                    .disabled(appState.deviceStore.devices.isEmpty)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            RuleEditorSheet(rule: nil) {
                ruleStore.add($0)
                MonitoringCoordinator.shared.apply()
            }
        }
        .sheet(item: $editingRule) { rule in
            RuleEditorSheet(rule: rule) {
                ruleStore.update($0)
                MonitoringCoordinator.shared.apply()
            }
        }
    }

    private func ruleRow(_ rule: CodeRule) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { var r = rule; r.enabled = $0; ruleStore.update(r); MonitoringCoordinator.shared.apply() }
            ))
            .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "iphone")
                        .foregroundStyle(.blue)
                    Text(rule.deviceName)
                        .font(.body)
                }
                HStack(spacing: 4) {
                    Image(systemName: "text.magnifyingglass")
                        .font(.caption)
                    Text(rule.keyword.isEmpty ? "匹配所有短信" : "关键字：\(rule.keyword)")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(rule.autoEndMinutes)分钟")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 规则编辑表单

private struct RuleEditorSheet: View {
    let rule: CodeRule?
    let onSave: (CodeRule) -> Void

    @Environment(AppStateManager.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var deviceId: Int = 0
    @State private var deviceName: String = ""
    @State private var keyword: String = "验证码"
    @State private var autoEndMinutes: Int = 5
    @State private var enabled: Bool = true

    var body: some View {
        NavigationStack {
            Form {
                Section("订阅设备") {
                    if appState.deviceStore.devices.isEmpty {
                        Text("暂无可用设备，请先在仪表盘刷新设备列表")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("设备", selection: $deviceId) {
                            ForEach(appState.deviceStore.devices) { device in
                                Text(device.name).tag(device.id)
                            }
                        }
                        .onChange(of: deviceId) { _, newId in
                            if let d = appState.deviceStore.devices.first(where: { $0.id == newId }) {
                                deviceName = d.name
                            }
                        }
                    }
                }

                Section("匹配关键字") {
                    TextField("如：验证码", text: $keyword)
                        .autocorrectionDisabled()
                    Text("短信内容包含此关键字才触发灵动岛；留空则匹配该设备的所有短信。项目名会自动从【】中提取。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("灵动岛") {
                    Stepper("自动结束：\(autoEndMinutes) 分钟", value: $autoEndMinutes, in: 1...30)
                    Toggle("启用此规则", isOn: $enabled)
                }
            }
            .navigationTitle(rule == nil ? "新增规则" : "编辑规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        var r = rule ?? CodeRule(deviceId: deviceId, deviceName: deviceName)
                        r.deviceId = deviceId
                        r.deviceName = deviceName
                        r.keyword = keyword
                        r.autoEndMinutes = autoEndMinutes
                        r.enabled = enabled
                        onSave(r)
                        dismiss()
                    }
                    .disabled(appState.deviceStore.devices.isEmpty)
                }
            }
            .onAppear { loadInitial() }
        }
    }

    private func loadInitial() {
        if let rule = rule {
            deviceId = rule.deviceId
            deviceName = rule.deviceName
            keyword = rule.keyword
            autoEndMinutes = rule.autoEndMinutes
            enabled = rule.enabled
        } else if let first = appState.deviceStore.devices.first {
            deviceId = first.id
            deviceName = first.name
        }
    }
}

#Preview {
    NavigationStack {
        CodeRulesView()
            .environment(AppStateManager())
    }
}
