import SwiftUI
import Observation

// MARK: - 登录 ViewModel

@Observable
final class LoginViewModel {
    var serverURL: String
    var username: String
    var password: String = ""
    var isLoggingIn: Bool = false
    var errorMessage: String?
    var showError: Bool = false

    // Turnstile 状态
    var turnstileEnabled: Bool = false
    var turnstileSiteKey: String = ""
    var turnstileToken: String? = nil
    var isCheckingTurnstile: Bool = false
    var turnstileError: String? = nil

    // 登录方式
    var loginMode: LoginMode = .oidc

    private let store = SettingsStore.shared
    private let api = SmsForwarderAPI.shared
    var appState: AppStateManager?

    init() {
        let settings = store.settings
        self.serverURL = settings.serverURL
        self.username = settings.username ?? ""
    }

    var canLogin: Bool {
        let trimmedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, !isLoggingIn else { return false }

        switch loginMode {
        case .oidc:
            // OIDC 登录只需面板地址
            return true
        case .password:
            return !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                   !password.isEmpty &&
                   (!turnstileEnabled || (turnstileToken != nil && !(turnstileToken?.isEmpty ?? true)))
        }
    }

    /// 检查 Turnstile 配置
    func checkTurnstile() async {
        let trimmedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }

        isCheckingTurnstile = true
        turnstileError = nil
        turnstileEnabled = false
        turnstileToken = nil

        do {
            let config = try await api.fetchTurnstileConfig(serverURL: trimmedURL)
            turnstileEnabled = config.enabled
            turnstileSiteKey = config.siteKey
        } catch {
            // 如果无法获取 Turnstile 配置，不阻止登录（可能面板未启用）
            turnstileEnabled = false
        }
        isCheckingTurnstile = false
    }

    func onTurnstileToken(_ token: String?) {
        turnstileToken = token
    }

    func login() async {
        switch loginMode {
        case .oidc:
            await oidcLogin()
        case .password:
            await passwordLogin()
        }
    }

    // MARK: - OIDC 登录

    private func oidcLogin() async {
        isLoggingIn = true
        defer { isLoggingIn = false }

        let trimmedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)

        // 保存面板地址
        var settings = store.settings
        settings.serverURL = trimmedURL
        store.save(settings)

        do {
            let result = try await OIDCManager.shared.startOIDCLogin(panelURL: trimmedURL)
            store.saveLogin(token: result.jwt, username: result.username)
            await appState?.onLoginSuccess()
        } catch let err as OIDCError {
            if case .userCancelled = err { return } // 用户取消不显示错误
            errorMessage = err.errorDescription ?? "OIDC 登录失败"
            showError = true
        } catch let err as APIError {
            errorMessage = err.errorDescription ?? "登录失败"
            showError = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    // MARK: - 密码登录

    private func passwordLogin() async {
        isLoggingIn = true
        defer { isLoggingIn = false }

        let trimmedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)

        // 先保存面板地址
        var settings = store.settings
        settings.serverURL = trimmedURL
        store.save(settings)

        // 如果 Turnstile 启用但未完成验证
        if turnstileEnabled && (turnstileToken == nil || turnstileToken?.isEmpty ?? true) {
            errorMessage = "请先完成人机验证"
            showError = true
            return
        }

        do {
            let token = try await api.login(
                username: trimmedUser,
                password: password,
                turnstileToken: turnstileToken ?? "",
                serverURL: trimmedURL
            )
            store.saveLogin(token: token, username: trimmedUser)
            password = ""
            turnstileToken = nil
            await appState?.onLoginSuccess()
        } catch let err as APIError {
            errorMessage = err.errorDescription ?? "登录失败"
            showError = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - 登录方式

enum LoginMode: String, CaseIterable {
    case oidc = "QQ验证登录"
    case password = "账号密码"

    var icon: String {
        switch self {
        case .oidc: return "person.badge.shield.checkmark.fill"
        case .password: return "person.badge.key"
        }
    }
}

// MARK: - 登录视图

struct LoginView: View {
    @Environment(AppStateManager.self) private var appState
    @State private var vm = LoginViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Logo 区域
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.12))
                                .frame(width: 80, height: 80)
                            Image(systemName: "envelope.badge.shield.half.filled.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.blue)
                        }
                        Text("SmsForwarder")
                            .font(.title2.bold())
                        Text("短信转发控制面板")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 20)

                    // 登录方式切换
                    Picker("登录方式", selection: $vm.loginMode) {
                        ForEach(LoginMode.allCases, id: \.self) { mode in
                            Label(mode.rawValue, systemImage: mode.icon)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 4)

                    // 服务器地址（两种模式共用）
                    VStack(alignment: .leading, spacing: 6) {
                        Text("服务器地址")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("https://smsf.xiaoyyua.top", text: $vm.serverURL)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 4)

                    // 根据登录方式显示不同表单
                    switch vm.loginMode {
                    case .oidc:
                        oidcForm
                    case .password:
                        passwordForm
                    }

                    // 登录按钮
                    Button {
                        Task { await vm.login() }
                    } label: {
                        HStack {
                            if vm.isLoggingIn {
                                ProgressView()
                                    .tint(.white)
                                    .padding(.trailing, 4)
                            }
                            Text(vm.isLoggingIn ? "登录中..." : "登录")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(vm.canLogin ? Color.blue : Color.gray.opacity(0.3))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(!vm.canLogin)
                    .padding(.horizontal, 4)

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 24)
            }
            .navigationTitle("登录")
            .navigationBarTitleDisplayMode(.inline)
            .alert("登录失败", isPresented: $vm.showError, actions: {
                Button("好") {}
            }, message: {
                Text(vm.errorMessage ?? "")
            })
            .onAppear {
                vm.appState = appState
                Task { await vm.checkTurnstile() }
            }
            .onChange(of: vm.serverURL) { _, _ in
                // 服务器地址变化时重新检查 Turnstile
                vm.turnstileEnabled = false
                vm.turnstileToken = nil
            }
        }
    }

    // MARK: - OIDC 登录表单

    private var oidcForm: some View {
        VStack(spacing: 16) {
            // 说明卡片
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "shield.checkered")
                        .foregroundStyle(.blue)
                    Text("QQ 验证登录")
                        .font(.subheadline.bold())
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. 点击「登录」后自动打开验证页面")
                    Text("2. 在页面中输入你的 QQ 号")
                    Text("3. QQ 机器人会发送一条验证链接")
                    Text("4. 在 QQ 中点击该链接完成验证")
                    Text("5. App 自动完成登录，无需密码")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(Color.blue.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 账号密码登录表单

    private var passwordForm: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("用户名")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("用户名", text: $vm.username)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("密码")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("密码", text: $vm.password)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.go)
                    .onSubmit {
                        if vm.canLogin {
                            Task { await vm.login() }
                        }
                    }
            }

            // Turnstile 人机验证
            if vm.isCheckingTurnstile {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("正在检查人机验证配置…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if vm.turnstileEnabled && !vm.turnstileSiteKey.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("人机验证")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TurnstileView(
                        siteKey: vm.turnstileSiteKey,
                        serverURL: vm.serverURL,
                        onTokenChange: { token in
                            vm.onTurnstileToken(token)
                        }
                    )
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

#Preview {
    LoginView()
        .environment(AppStateManager())
}
