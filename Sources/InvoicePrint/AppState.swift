import Foundation
import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers
import InvoicePrintCore

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var items: [InputItem] = []
    @Published var config = LayoutConfig()
    @Published var previewPages: [NSImage] = []
    @Published var status: String = "拖入 PDF 或图片，或点击“添加文件”"
    @Published var errorMessage: String?
    @Published var isBuilding = false
    @Published var amounts: [UUID: Double] = [:]
    @Published var amountsLoading = false

    private var buildWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private var amountCache: [UUID: Double] = [:]
    private var amountChecked = Set<UUID>()

    var totalAmount: Double {
        items.compactMap { amounts[$0.id] }.reduce(0, +)
    }

    var detectedCount: Int {
        items.filter { amounts[$0.id] != nil }.count
    }

    init() {
        $config
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.scheduleBuild() }
            }
            .store(in: &cancellables)

        $items
            .dropFirst()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.recomputeAmounts() }
            }
            .store(in: &cancellables)
    }

    func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = MergeEngine.supportedTypes
        panel.title = "选择发票 PDF 或图片"
        guard panel.runModal() == .OK else { return }
        append(urls: panel.urls)
    }

    func addDirectory() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.title = "选择包含发票的文件夹"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        append(urls: urls)
    }

    func append(urls: [URL]) {
        let newItems = MergeEngine.loadInputItems(urls: urls)
        guard !newItems.isEmpty else {
            errorMessage = "未识别到支持的 PDF 或图片文件"
            return
        }
        let existing = Set(items.map { $0.url.standardizedFileURL })
        let filtered = newItems.filter { !existing.contains($0.url.standardizedFileURL) }
        items.append(contentsOf: filtered)
        sortItems(.natural, manually: false)
        scheduleBuild()
    }

    func remove(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        scheduleBuild()
    }

    func remove(_ item: InputItem) {
        items.removeAll { $0.id == item.id }
        scheduleBuild()
    }

    func clear() {
        items.removeAll()
        previewPages.removeAll()
        amounts.removeAll()
        amountCache.removeAll()
        amountChecked.removeAll()
        status = "列表已清空"
    }

    func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        scheduleBuild()
    }

    func sortItems(_ mode: SortMode, manually: Bool = true) {
        switch mode {
        case .natural:
            items.sort { FileOrder.naturalCompare($0.name, $1.name) }
        case .name:
            items.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .addedOrder:
            break
        }
        if manually { scheduleBuild() }
    }

    func scheduleBuild() {
        buildWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.rebuild() }
        }
        buildWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    func rebuild() {
        guard !items.isEmpty else {
            previewPages = []
            status = "拖入 PDF 或图片，或点击“添加文件”"
            return
        }
        isBuilding = true
        let items = self.items
        let config = self.config
        Task.detached(priority: .userInitiated) {
            do {
                let data = try MergeEngine.buildPDF(items: items, config: config)
                await MainActor.run {
                    self.apply(data: data, itemCount: items.count)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isBuilding = false
                }
            }
        }
    }

    private func apply(data: Data, itemCount: Int) {
        let pages = MergeEngine.renderPreviews(data: data)
        previewPages = pages
        status = "共 \(itemCount) 个文件 → \(pages.count) 页"
        isBuilding = false
    }

    func recomputeAmounts() {
        let items = self.items
        var merged: [UUID: Double] = [:]
        for item in items where item.kind == .pdf || item.kind == .image {
            if let cached = amountCache[item.id] { merged[item.id] = cached }
        }
        amounts = merged

        let pending = items.filter { !amountChecked.contains($0.id) }
        guard !pending.isEmpty else {
            amountsLoading = false
            return
        }
        amountsLoading = true
        Task.detached(priority: .utility) {
            var found: [UUID: Double] = [:]
            for item in pending {
                if let value = AmountExtractor.extract(url: item.url, kind: item.kind) {
                    found[item.id] = value
                }
            }
            let extracted = found
            await MainActor.run {
                for item in pending { self.amountChecked.insert(item.id) }
                for (id, value) in extracted { self.amountCache[id] = value }
                var updated = self.amounts
                for (id, value) in extracted { updated[id] = value }
                self.amounts = updated
                self.amountsLoading = false
            }
        }
    }

    func copyTotal() {
        let text = AmountExtractor.format(totalAmount)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        status = "已复制合计 \(text)"
    }

    func export() {
        guard !items.isEmpty else { return }
        do {
            let data = try MergeEngine.buildPDF(items: items, config: config)
            let stamp = Self.timestamp()
            PrintService.exportPDF(data: data, suggestedName: "合并_\(stamp).pdf")
            status = "已导出合并_\(stamp).pdf"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func printDocument() {
        guard !items.isEmpty else { return }
        do {
            let data = try MergeEngine.buildPDF(items: items, config: config)
            PrintService.print(data: data, paperSize: config.paper.pointSize)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }
}
