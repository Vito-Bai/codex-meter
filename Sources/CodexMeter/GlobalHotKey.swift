import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}

struct CodexLogoView: View {
    static let menuBarImage: NSImage? = {
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/icon-codex-dark-color.png",
            "/Applications/ChatGPT.app/Contents/Resources/icon-codex-light.png"
        ]

        guard let source = candidates.lazy.compactMap(NSImage.init(contentsOfFile:)).first else {
            return nil
        }

        // The source asset has roughly 10% transparent padding on every edge.
        // Crop that padding before fitting the artwork to the same 18 pt optical
        // height used by the neighboring filled menu-bar app icons.
        let inset = min(source.size.width, source.size.height) * 0.095
        let sourceRect = NSRect(
            x: inset,
            y: inset,
            width: source.size.width - inset * 2,
            height: source.size.height - inset * 2
        )

        // Give the image its final intrinsic size before MenuBarExtra measures
        // the label; an outer frame alone does not constrain that measurement.
        return NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            source.draw(
                in: rect,
                from: sourceRect,
                operation: .sourceOver,
                fraction: 1
            )
            return true
        }
    }()

    var body: some View {
        Group {
            if let image = Self.menuBarImage {
                Image(nsImage: image)
                    .interpolation(.high)
            } else {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 16, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.indigo)
            }
        }
        .frame(width: 18, height: 18)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .accessibilityLabel("Codex")
    }
}
