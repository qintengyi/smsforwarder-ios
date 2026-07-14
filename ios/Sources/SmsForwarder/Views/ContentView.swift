import SwiftUI
import Observation

/// TabView 主容器（底部 5 个 Tab）
struct ContentView: View {
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(selectedTab: $selectedTab)
                .tabItem {
                    Label("仪表盘", systemImage: "house.fill")
                }
                .tag(0)

            SMSView()
                .tabItem {
                    Label("短信", systemImage: "message.fill")
                }
                .tag(1)

            CallsView()
                .tabItem {
                    Label("通话", systemImage: "phone.fill")
                }
                .tag(2)

            ContactsView()
                .tabItem {
                    Label("联系人", systemImage: "person.fill")
                }
                .tag(3)

            MoreView()
                .tabItem {
                    Label("更多", systemImage: "ellipsis.circle.fill")
                }
                .tag(4)
        }
        .tint(.blue)
    }
}

#Preview {
    ContentView()
}
