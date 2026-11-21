import SwiftUI

/// Design tokens (AGENTS.md §9). Views never hard-code colors or radii.
enum Theme {
    static let accent = Color.accentColor
    static let overdue = Color.red
    static let soon = Color.orange

    static let cornerRadius: CGFloat = 16
    static let spacing: CGFloat = 12

    /// Reminder colors; index stored on the model.
    static let palette: [Color] = [
        Color(red: 0.17, green: 0.71, blue: 0.63), // mint (accent)
        Color(red: 0.29, green: 0.56, blue: 0.95), // blue
        Color(red: 0.96, green: 0.58, blue: 0.20), // orange
        Color(red: 0.93, green: 0.38, blue: 0.52), // pink
        Color(red: 0.55, green: 0.45, blue: 0.90), // purple
        Color(red: 0.42, green: 0.48, blue: 0.55), // slate
    ]

    static func color(_ index: Int) -> Color { palette[((index % palette.count) + palette.count) % palette.count] }

    static let symbols = [
        "arrow.triangle.2.circlepath", "play.tv", "music.note", "icloud", "gamecontroller", "globe",
        "creditcard", "iphone", "laptopcomputer", "car", "house", "building.2",
        "bolt", "drop", "wifi", "phone", "heart", "bell",
    ]
}

struct ReminderIcon: View {
    let symbol: String
    let colorIndex: Int
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.color(colorIndex), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct DueBadge: View {
    let days: Int

    var body: some View {
        Text(Formatting.relativeDays(days))
            .font(.footnote.weight(days <= 0 ? .semibold : .regular))
            .foregroundStyle(days < 0 ? Theme.overdue : days == 0 ? Theme.accent : days <= 3 ? Theme.soon : .secondary)
    }
}

extension View {
    func cardStyle() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}
