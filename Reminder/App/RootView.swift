import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            UpcomingView()
                .tabItem { Label("即将到期", systemImage: "clock") }

            CalendarScreen()
                .tabItem { Label("日历", systemImage: "calendar") }

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
    }
}

#Preview {
    RootView()
}
