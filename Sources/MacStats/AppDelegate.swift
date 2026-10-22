import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private let stats = SystemStats()
    private let loginItem = LoginItemManager()
    private let storageState = StorageState()
    private var eventMonitor: Any?
    private var hotkeyMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    private let panelSize = NSSize(width: 308, height: 620)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        stats.start()
        setupStatusItem()
        setupPanel()
        setupEventMonitor()
        setupHotkeyMonitor()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: "MacStats")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePanel)
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        }

        stats.$cpuFraction
            .receive(on: DispatchQueue.main)
            .sink { [weak self] fraction in
                self?.statusItem.button?.title = "  \(Int(fraction * 100))%"
            }
            .store(in: &cancellables)
    }

    private func setupPanel() {
        let hosting = NSHostingController(rootView: ContentView(stats: stats, loginItem: loginItem, storageState: storageState))
        hosting.view.frame = NSRect(origin: .zero, size: panelSize)

        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        hosting.view.wantsLayer = true
        hosting.view.layer?.cornerRadius = 22
        hosting.view.layer?.masksToBounds = true
    }

    @objc private func togglePanel() {
        if panel.isVisible {
            closePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.frame)
        let x = buttonFrame.midX - panelSize.width / 2
        let y = buttonFrame.minY - panelSize.height - 6
        panel.setFrame(NSRect(x: x, y: y, width: panelSize.width, height: panelSize.height), display: false)

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        statusItem.button?.highlight(true)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func closePanel() {
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
    }

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
        }
    }

    /// Global shortcut: Cmd+Shift+M. Needs Input Monitoring permission (System Settings
    /// > Privacy & Security); if not granted, this silently does nothing rather than crashing.
    private func setupHotkeyMonitor() {
        hotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift],
                  event.keyCode == 46 else { return }
            Task { @MainActor in self?.togglePanel() }
        }
    }
}
