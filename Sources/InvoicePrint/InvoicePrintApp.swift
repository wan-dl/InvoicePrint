import SwiftUI

@main
struct InvoicePrintApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        Window("发票合并打印", id: "main") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 820, minHeight: 520)
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 860, height: 540)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("添加文件…") { state.addFiles() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("添加文件夹…") { state.addDirectory() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button("导出 PDF…") { state.export() }
                    .keyboardShortcut("s", modifiers: .command)
                Button("打印…") { state.printDocument() }
                    .keyboardShortcut("p", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func application(_ application: NSApplication, open urls: [URL]) {
        let urls = urls
        Task { @MainActor in
            AppState.shared.append(urls: urls)
        }
    }
}

extension Notification.Name {
    static let didOpenFiles = Notification.Name("InvoicePrint.didOpenFiles")
}
