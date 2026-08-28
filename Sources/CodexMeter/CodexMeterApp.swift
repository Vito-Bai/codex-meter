import SwiftUI

@main
struct CodexMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(store)
        } label: {
            MenuBarLabel()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(store)
                .frame(width: 520, height: 440)
        }
    }
}

private struct MenuBarLabel: View {
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        HStack(spacing: 3) {
            MenuBarQuotaIcon(
                remainingPercent: store.remainingPercent,
                available: store.quotaColorAvailable
            )
            Text(store.primaryWindow == nil ? "--%" : "\(store.remainingPercent)%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            store.primaryWindow == nil
                ? "Codex Meter，额度不可用"
                : "Codex Meter，剩余额度 \(store.remainingPercent)%"
        )
        .task { store.start() }
    }
}

private struct MenuBarQuotaIcon: View {
    let remainingPercent: Int
    let available: Bool

    private var progress: Double {
        min(max(Double(remainingPercent) / 100, 0), 1)
    }

    private var ringColor: NSColor {
        guard available else { return .systemGray }
        switch remainingPercent {
        case 81...: return NSColor(calibratedRed: 0.34, green: 0.95, blue: 0.72, alpha: 1)
        case 50...80: return NSColor(calibratedRed: 0.98, green: 0.82, blue: 0.34, alpha: 1)
        case 25...49: return NSColor(calibratedRed: 1, green: 0.55, blue: 0.25, alpha: 1)
        default: return NSColor(calibratedRed: 1, green: 0.33, blue: 0.38, alpha: 1)
        }
    }

    private var ringImage: NSImage {
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = 4.8

            NSColor.white.withAlphaComponent(0.28).setStroke()
            let track = NSBezierPath(ovalIn: NSRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            track.lineWidth = 1.8
            track.stroke()

            self.ringColor.setStroke()
            let indicator = NSBezierPath()
            indicator.lineWidth = 2.2
            indicator.lineCapStyle = .round

            if self.available {
                indicator.appendArc(
                    withCenter: center,
                    radius: radius,
                    startAngle: 90,
                    endAngle: 90 - 360 * self.progress,
                    clockwise: true
                )
            } else {
                indicator.appendArc(
                    withCenter: center,
                    radius: radius,
                    startAngle: 0,
                    endAngle: 360
                )
                indicator.setLineDash([1.4, 2.2], count: 2, phase: 0)
                indicator.lineWidth = 1.8
            }

            indicator.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }

    private var image: NSImage {
        let ring = ringImage
        let image = NSImage(size: NSSize(width: 33, height: 18), flipped: false) { _ in
            CodexLogoView.menuBarImage?.draw(
                in: NSRect(x: 0, y: 0, width: 18, height: 18),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            ring.draw(
                in: NSRect(x: 21, y: 3, width: 12, height: 12),
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
            .frame(width: 33, height: 18)
        .accessibilityHidden(true)
    }
}
