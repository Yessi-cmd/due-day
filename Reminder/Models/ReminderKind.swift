import Foundation

enum ReminderKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case subscription
    case installment
    case rent
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .subscription: "订阅"
        case .installment: "分期"
        case .rent: "房租"
        case .custom: "自定义"
        }
    }

    var subtitle: String {
        switch self {
        case .subscription: "会员、云服务、App 续费"
        case .installment: "信用卡、花呗、手机分期"
        case .rent: "月付、季付、年付房租"
        case .custom: "任何需要按时记得的事"
        }
    }

    var defaultSymbol: String {
        switch self {
        case .subscription: "arrow.triangle.2.circlepath"
        case .installment: "creditcard"
        case .rent: "house"
        case .custom: "bell"
        }
    }

    var defaultColorIndex: Int {
        switch self {
        case .subscription: 1
        case .installment: 2
        case .rent: 0
        case .custom: 4
        }
    }

    var titlePlaceholder: String {
        switch self {
        case .subscription: "如：视频会员"
        case .installment: "如：手机分期"
        case .rent: "如：公寓房租"
        case .custom: "如：交物业费"
        }
    }

    var dateLabel: String {
        switch self {
        case .subscription: "下次扣费日"
        case .installment: "首期还款日"
        case .rent: "交租日"
        case .custom: "日期"
        }
    }

    /// Action wording: things with money are "paid", others are "done".
    var settleVerb: String { self == .custom ? "完成" : "已付" }
}
