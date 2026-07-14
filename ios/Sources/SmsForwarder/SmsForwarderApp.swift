import SwiftUI
import Observation

/// 全局应用状态管理
@Observable
final class AppStateManager {
    var isLoggedIn: Bool
    var deviceStore: DeviceStore

    private let store = SettingsStore.shared

    init() {
        let ds = DeviceStore.shared
        ds.restoreFromStorage()
        self.deviceStore = ds
        self.isLoggedIn = store.settings.isLoggedIn
    }

    func refreshAuthState() {
        isLoggedIn = store.settings.isLoggedIn
    }

    /// 登录成功后初始化设备列表
    func onLoginSuccess() async {
        refreshAuthState()
        deviceStore.restoreFromStorage()
        try? await deviceStore.fetch()
    }

    func logout() {
        store.clearLogin()
        deviceStore.clear()
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
                        appState.refreshAuthState()
                    }
            }
        }
    }
}
