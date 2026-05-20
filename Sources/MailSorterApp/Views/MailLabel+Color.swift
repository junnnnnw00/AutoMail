import SwiftUI
import SharedKit

public extension MailLabel {
    var color: Color {
        switch self {
        case .important:
            return Color(red: 0.95, green: 0.72, blue: 0.2) // Premium Amber Gold
        case .normal:
            return Color(red: 0.25, green: 0.5, blue: 0.9)  // Deep Sapphire Blue
        case .newsletter:
            return Color(red: 0.18, green: 0.68, blue: 0.45) // Emerald Green
        case .ad:
            return Color(red: 0.88, green: 0.38, blue: 0.22) // Coral/Warm Orange
        }
    }
}
