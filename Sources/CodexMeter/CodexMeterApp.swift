import SwiftUI

@main
struct CodexMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(appDelegate.store)
        } label: {
            MenuBarLabel()
                .environmentObject(appDelegate.store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appDelegate.store)
                .frame(width: 520, height: 440)
        }
    }
}

private struct MenuBarLabel: View {
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        HStack(spacing: 3) {
            MenuBarQuotaIcon(
                weeklyRemaining: store.weeklyWindow?.remainingPercent,
                shortRemaining: store.shortWindow?.remainingPercent
            )
            Text(displayedText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .help(tooltipText)
        .task { store.start() }
    }

    private var shouldShowShortWindow: Bool {
        guard let short = store.shortWindow else { return false }
        return store.weeklyWindow == nil || short.remainingPercent < 25
    }

    private var displayedText: String {
        if store.hasUnreadOfficialResetNotice {
            return officialResetMenuText
        }
        if shouldShowShortWindow, let short = store.shortWindow {
            return "5h \(short.remainingPercent)%"
        }
        if let weekly = store.weeklyWindow {
            return "\(weekly.remainingPercent)%"
        }
        return "--%"
    }

    private var officialResetMenuText: String {
        guard let resetAt = store.officialResetNotice?.announcedResetAt else {
            return "官方重置"
        }
        let remaining = max(0, resetAt.timeIntervalSinceNow)
        if remaining >= 24 * 60 * 60 {
            return "官方重置 \(Int(ceil(remaining / (24 * 60 * 60))))天"
        }
        if remaining >= 60 * 60 {
            return "官方重置 \(Int(ceil(remaining / (60 * 60))))h"
        }
        return "官方重置 \(Int(ceil(remaining / 60)))m"
    }

    private var tooltipText: String {
        if store.hasUnreadOfficialResetNotice {
            return "OpenAI 发布了新的官方额度重置动态·点击查看"
        }
        let weekly = store.weeklyWindow.map { "1 周剩余 \($0.remainingPercent)%" } ?? "1 周额度不可用"
        let short = store.shortWindow.map { "5 小时剩余 \($0.remainingPercent)%" } ?? "5 小时额度不可用"
        return "\(weekly) · \(short)"
    }

    private var accessibilityText: String {
        "Codex Meter，\(tooltipText)"
    }
}

private struct MenuBarQuotaIcon: View {
    let weeklyRemaining: Int?
    let shortRemaining: Int?

    private func ringColor(remaining: Int, healthy: NSColor) -> NSColor {
        switch remaining {
        case 81...: return healthy
        case 50...80: return NSColor(calibratedRed: 0.98, green: 0.82, blue: 0.34, alpha: 1)
        case 25...49: return NSColor(calibratedRed: 1, green: 0.55, blue: 0.25, alpha: 1)
        default: return NSColor(calibratedRed: 1, green: 0.33, blue: 0.38, alpha: 1)
        }
    }

    private var ringImage: NSImage {
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            self.drawRing(
                center: center,
                radius: 5.7,
                lineWidth: 1.8,
                remaining: self.weeklyRemaining,
                healthy: NSColor(calibratedRed: 0.35, green: 0.78, blue: 1, alpha: 1)
            )
            self.drawRing(
                center: center,
                radius: 3.1,
                lineWidth: 1.35,
                remaining: self.shortRemaining,
                healthy: NSColor(calibratedRed: 0.34, green: 0.95, blue: 0.72, alpha: 1)
            )
            return true
        }
        image.isTemplate = false
        return image
    }

    private func drawRing(
        center: NSPoint,
        radius: CGFloat,
        lineWidth: CGFloat,
        remaining: Int?,
        healthy: NSColor
    ) {
        NSColor.white.withAlphaComponent(0.2).setStroke()
        let track = NSBezierPath(ovalIn: NSRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        track.lineWidth = lineWidth
        track.stroke()

        guard let remaining else { return }
        ringColor(remaining: remaining, healthy: healthy).setStroke()
        let indicator = NSBezierPath()
        indicator.lineWidth = lineWidth
        indicator.lineCapStyle = .round
        let progress = min(max(Double(remaining) / 100, 0), 1)
        indicator.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 90,
            endAngle: 90 - 360 * progress,
            clockwise: true
        )
        indicator.stroke()
    }

    private var image: NSImage {
        let ring = ringImage
        let image = NSImage(size: NSSize(width: 35, height: 18), flipped: false) { _ in
            CodexLogoView.menuBarImage?.draw(
                in: NSRect(x: 0, y: 0, width: 18, height: 18),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            ring.draw(
                in: NSRect(x: 20, y: 2, width: 14, height: 14),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            return true
        }
        image.isTemplate = false
        return image
    }

    var body: some View {
        Image(nsImage: image)
            .renderingMode(.original)
            .frame(width: 35, height: 18)
        .accessibilityHidden(true)
    }
}
