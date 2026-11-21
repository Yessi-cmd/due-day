import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("关于") {
                    LabeledContent("版本", value: AppInfo.version)
                    LabeledContent("构建号", value: AppInfo.build)
                }
            }
            .navigationTitle("设置")
        }
    }
}

#Preview {
    SettingsView()
}
