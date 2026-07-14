import SwiftUI
import Observation

/// 全局应用状态管理
@Observable
final class AppStateManager {
    var isLoggedIn: Bool

    private let store = SettingsStore.shared

    init() {
        isLoggedIn = store.settings.isLoggedIn
    }

    func refreshAuthState() {
        isLoggedIn = store.settings.isLoggedIn
    }

    func logout() {
        store.clearLogin()
        isLoggedIn = false
    }
}

/// SmsForwarder iOS 应用入口
@main
struct SmsForwarderApp: App {
    @State private var appState = AppStateManager()

    var body: some Scene {
        WindowGroup {
            if appState.isLoggedIn {
                ContentView()
                    .environment(appState)
            } else {
                LoginView()
                    .environment(appState)
                    .onAppear {
                        // 每次 LoginView 出现时刷新状态（处理从设置页退出登录后返回的情况）
                        appState.refreshAuthState()
                    }
            }
        }
    }
}
