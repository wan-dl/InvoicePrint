import SwiftUI
import InvoicePrintCore

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 400)
        } detail: {
            VStack(spacing: 0) {
                if !state.items.isEmpty {
                    SettingsBar()
                }
                PreviewView()
            }
            .frame(minWidth: 480)
            .background(Color.white)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar { toolbarContent }
        .sheet(isPresented: $state.isDownloadPresented) {
            DownloadSheet()
                .environmentObject(state)
        }
        .overlay { dropOverlay }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .onReceive(NotificationCenter.default.publisher(for: .didOpenFiles)) { note in
            if let urls = note.userInfo?["urls"] as? [URL] {
                state.append(urls: urls)
            }
        }
        .alert("出错了", isPresented: errorBinding) {
            Button("好", role: .cancel) { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                state.addFiles()
            } label: {
                Label("添加文件", systemImage: "plus")
            }
            .help("添加 PDF 或图片（⌘O）")
            .disabled(state.isBuilding)
        }

        ToolbarItem(placement: .navigation) {
            Button {
                state.isDownloadPresented = true
            } label: {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 10, weight: .regular))
            }
            .help("从 URL 下载发票到临时目录")
            .disabled(state.isDownloading)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                state.export()
            } label: {
                Label("导出 PDF", systemImage: "square.and.arrow.down")
            }
            .help("导出合并后的 PDF（⌘S）")
            .disabled(state.items.isEmpty)

            Button {
                state.printDocument()
            } label: {
                Label("打印", systemImage: "printer")
            }
            .help("打印（⌘P）")
            .disabled(state.items.isEmpty)
        }
    }

    private var dropOverlay: some View {
        Group {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 7]))
                    .background(Color.accentColor.opacity(0.08))
                    .overlay {
                        VStack(spacing: 10) {
                            Image(systemName: "tray.and.arrow.down.fill")
                                .font(.system(size: 44))
                                .symbolRenderingMode(.hierarchical)
                            Text("松开以添加文件")
                                .font(.title3.weight(.medium))
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    .padding(14)
                    .allowsHitTesting(false)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        for provider in providers where provider.hasItemConformingToTypeIdentifier("public.file-url") {
            group.enter()
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                defer { group.leave() }
                var url: URL?
                if let data = data as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let u = data as? URL {
                    url = u
                }
                if let url {
                    lock.lock(); urls.append(url); lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            let collected = urls.flatMap { url -> [URL] in
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    return (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                }
                return [url]
            }
            state.append(urls: collected)
        }
        return true
    }
}
