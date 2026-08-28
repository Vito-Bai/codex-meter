import Foundation

enum TokenFormat {
    static func compact(_ value: Int64) -> String {
        let number = Double(value)
        if abs(number) >= 1_000_000 {
            return trim(number / 1_000_000) + "M"
        }
        if abs(number) >= 1_000 {
            return trim(number / 1_000) + "K"
        }
        return String(value)
    }

    static func full(_ value: Int64) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    static func duration(_ interval: TimeInterval) -> String {
        if interval < 60 { return "\(Int(interval)) 秒" }
        if interval < 3_600 { return "\(Int(interval / 60)) 分钟" }
        let hours = Int(interval / 3_600)
        let minutes = Int(interval.truncatingRemainder(dividingBy: 3_600) / 60)
        return "\(hours) 小时 \(minutes) 分钟"
    }

    static func relativeDate(_ date: Date, now: Date = .now) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    private static func trim(_ value: Double) -> String {
        if value >= 100 { return String(format: "%.0f", value) }
        if value >= 10 { return String(format: "%.1f", value) }
        return String(format: "%.2f", value)
    }
}
