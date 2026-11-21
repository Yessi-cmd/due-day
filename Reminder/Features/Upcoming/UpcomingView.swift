import SwiftUI

struct UpcomingView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "还没有提醒",
                systemImage: "bell",
                description: Text("订阅、分期、房租……都可以放在这里。")
            )
            .navigationTitle("即将到期")
        }
    }
}

#Preview {
    UpcomingView()
}
