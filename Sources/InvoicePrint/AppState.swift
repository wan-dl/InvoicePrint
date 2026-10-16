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
    @Published var isDownloadPresented = false
    @Published var downloadURLText = ""
    @Published var isDownloading = false

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

    func append(urls: [URL], origin: ItemOrigin = .local) {
        let newItems = MergeEngine.loadInputItems(urls: urls, origin: origin)
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

    // MARK: - 从链接下载

    func startDownload() {
        let links = parseDownloadLinks()
        guard !links.isEmpty else {
            errorMessage = "请输入有效的 http/https 链接"
            return
        }
        let dir = Self.todayTempDirectory()
        isDownloading = true
        status = "正在下载 \(links.count) 个文件…"
        Task.detached(priority: .userInitiated) {
            var saved: [URL] = []
            var failures: String = ""
            for link in links {
                do {
                    let url = try await Self.download(link, into: dir)
                    saved.append(url)
                } catch {
                    failures += "\n• \(link.absoluteString)：\(error.localizedDescription)"
                }
            }
            let savedURLs = saved
            let failureText = failures
            await MainActor.run {
                self.isDownloading = false
                if !savedURLs.isEmpty {
                    self.append(urls: savedURLs, origin: .download)
                }
                if !failureText.isEmpty {
                    self.errorMessage = "部分链接下载失败：" + failureText
                } else if !savedURLs.isEmpty {
                    self.status = "已下载 \(savedURLs.count) 个文件到 \(dir.path)"
                }
            }
        }
    }

    private func parseDownloadLinks() -> [URL] {
        let separators = CharacterSet(charactersIn: "\n\r\t ,;，；")
        return downloadURLText
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap { URL(string: $0) }
            .filter { let s = $0.scheme?.lowercased(); return s == "http" || s == "https" }
    }

    /// 系统临时目录下的当天日期文件夹，例如 …/T/2026-10-16
    nonisolated static func todayTempDirectory() -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let name = f.string(from: Date())
        return FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
    }

    nonisolated static func download(_ link: URL, into dir: URL) async throws -> URL {
        var request = URLRequest(url: link)
        request.timeoutInterval = 60
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X) InvoicePrint", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw DownloadError.badStatus(http.statusCode)
        }
        guard !data.isEmpty else { throw DownloadError.emptyContent }

        let ext = resolvedExtension(for: link, response: response, data: data)
        let name = resolvedName(for: link, response: response, ext: ext)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = uniqueDestination(in: dir, name: name)
        try data.write(to: dest, options: .atomic)
        return dest
    }

    nonisolated static func resolvedExtension(for link: URL, response: URLResponse, data: Data) -> String {
        if ItemKind.from(url: link) != nil { return link.pathExtension.lowercased() }
        if let mime = response.mimeType?.lowercased() {
            switch true {
            case mime.contains("pdf"): return "pdf"
            case mime.contains("png"): return "png"
            case mime.contains("jpeg"), mime.contains("jpg"): return "jpg"
            case mime.contains("tiff"): return "tiff"
            case mime.contains("heic"): return "heic"
            case mime.contains("gif"): return "gif"
            case mime.contains("bmp"): return "bmp"
            case mime.contains("webp"): return "webp"
            default: break
            }
        }
        if data.count >= 4, data.prefix(4) == Data([0x25, 0x50, 0x44, 0x46]) { return "pdf" }
        if data.count >= 8, data.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return "png" }
        if data.count >= 3, data.prefix(3) == Data([0xFF, 0xD8, 0xFF]) { return "jpg" }
        let pathExt = link.pathExtension.lowercased()
        return pathExt.isEmpty ? "pdf" : pathExt
    }

    nonisolated static func resolvedName(for link: URL, response: URLResponse, ext: String) -> String {
        var base = response.suggestedFilename ?? link.lastPathComponent
        base = base.removingPercentEncoding ?? base
        if base.isEmpty { base = "invoice" }
        let ns = base as NSString
        if ns.pathExtension.isEmpty { return "\(base).\(ext)" }
        if ItemKind.from(url: URL(fileURLWithPath: base)) == nil {
            return "\(ns.deletingPathExtension).\(ext)"
        }
        return base
    }

    nonisolated static func uniqueDestination(in dir: URL, name: String) -> URL {
        let ns = name as NSString
        let base = ns.deletingPathExtension
        let ext = ns.pathExtension
        var candidate = dir.appendingPathComponent(name)
        var index = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let next = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            candidate = dir.appendingPathComponent(next)
            index += 1
        }
        return candidate
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }
}

enum DownloadError: LocalizedError {
    case badStatus(Int)
    case emptyContent

    var errorDescription: String? {
        switch self {
        case .badStatus(let code): return "服务器返回状态码 \(code)"
        case .emptyContent: return "下载内容为空"
        }
    }
}
