import SwiftUI

struct CalendarScreen: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "日历即将上线",
                systemImage: "calendar",
                description: Text("公历、农历、节气与节假日。")
            )
            .navigationTitle("日历")
        }
    }
}

#Preview {
    CalendarScreen()
}
