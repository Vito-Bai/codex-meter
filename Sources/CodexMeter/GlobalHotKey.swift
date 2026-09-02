import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = UsageStore()
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        store.start()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(simulateFirstLaunch),
            name: .simulateCodexMeterFirstLaunch,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showSupport),
            name: .showCodexMeterSupport,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(bringSettingsToFront),
            name: .bringCodexMeterSettingsToFront,
            object: nil
        )

        if UserDefaults.standard.integer(forKey: PreferenceKey.onboardingVersion) < OnboardingFlow.currentVersion {
            DispatchQueue.main.async { [weak self] in
                self?.showOnboarding()
            }
        }
    }

    func showOnboarding(startingAt page: OnboardingPage = .welcome, restart: Bool = false) {
        if restart, let onboardingWindow {
            onboardingWindow.delegate = nil
            onboardingWindow.close()
            self.onboardingWindow = nil
        } else if let onboardingWindow {
            onboardingWindow.setIsVisible(true)
            onboardingWindow.makeKeyAndOrderFront(nil)
            onboardingWindow.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let content = OnboardingFlow(
            startingAt: page,
            onFinish: { [weak self] in
                UserDefaults.standard.set(OnboardingFlow.currentVersion, forKey: PreferenceKey.onboardingVersion)
                self?.onboardingWindow?.close()
            }
        )
        .environmentObject(store)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 470),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex Meter 使用引导"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: content)
        window.delegate = self
        window.center()
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func simulateFirstLaunch() {
        showOnboarding(startingAt: .welcome, restart: true)
    }

    @objc private func showSupport() {
        showOnboarding(startingAt: .completion, restart: true)
    }

    @objc private func bringSettingsToFront() {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self,
                  let window = NSApp.windows.first(where: {
                      $0 !== self.onboardingWindow &&
                      $0.isVisible &&
                      $0.styleMask.contains(.titled) &&
                      $0.canBecomeKey
                  })
            else { return }

            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === onboardingWindow else { return }
        onboardingWindow = nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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
