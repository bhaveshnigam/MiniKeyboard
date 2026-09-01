import SwiftUI
import AppKit
import MiniKeyboardKit

@main
struct MiniKeyboardApp: App {
    @State private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 760, minHeight: 520)
                .onAppear { model.connect() }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Device") {
                Button("Reconnect") { model.connect() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Read from Device") { model.readFromDevice() }
                    .keyboardShortcut("d", modifiers: .command)
                    .disabled(!model.isConnected)
                Divider()
                Button("Apply to Device") { model.apply() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!model.isConnected)
            }
        }
    }
}

/// SPM executables start as accessory processes; promote to a normal app so
/// the window takes focus and the menu bar appears.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
