import Foundation
import AppKit
import CoreGraphics
import PDFKit
import ImageIO
import UniformTypeIdentifiers

public enum MergeError: LocalizedError {
    case noInput
    case cannotCreateContext
    case cannotLoad(URL)

    public var errorDescription: String? {
        switch self {
        case .noInput: return "没有可合并的文件"
        case .cannotCreateContext: return "无法创建 PDF 输出上下文"
        case .cannotLoad(let u): return "无法读取文件：\(u.lastPathComponent)"
        }
    }
}

/// 一个待绘制的页面来源：PDF 的某一页，或一张图片。
private enum PageSource {
    case pdf(PDFDocument, Int)
    case image(CGImage)

    var contentSize: CGSize {
        switch self {
        case .pdf(let doc, let index):
            guard let page = doc.page(at: index) else { return .zero }
            var size = page.bounds(for: .mediaBox).size
            if page.rotation % 180 != 0 {
                size = CGSize(width: size.height, height: size.width)
            }
            return size
        case .image(let cg):
            return CGSize(width: cg.width, height: cg.height)
        }
    }

    func draw(in rect: CGRect, context: CGContext) {
        switch self {
        case .pdf(let doc, let index):
            guard let page = doc.page(at: index) else { return }
            let bounds = page.bounds(for: .mediaBox)
            let scaleX = rect.width / max(bounds.width, 1)
            let scaleY = rect.height / max(bounds.height, 1)
            context.saveGState()
            context.translateBy(x: rect.minX, y: rect.minY)
            context.scaleBy(x: scaleX, y: scaleY)
            context.translateBy(x: -bounds.minX, y: -bounds.minY)
            page.draw(with: .mediaBox, to: context)
            context.restoreGState()
        case .image(let cg):
            context.saveGState()
            context.interpolationQuality = .high
            context.draw(cg, in: rect)
            context.restoreGState()
        }
    }
}

public enum MergeEngine {

    // MARK: - Public

    /// 把若干输入文件按配置渲染合并为一个 PDF 数据。
    public static func buildPDF(items: [InputItem], config: LayoutConfig) throws -> Data {
        let sources = try expand(items: items, expandAllPDFPages: config.expandAllPDFPages)
        guard !sources.isEmpty else { throw MergeError.noInput }

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw MergeError.cannotCreateContext
        }
        let pageSize = config.paper.pointSize
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw MergeError.cannotCreateContext
        }

        let perPage = config.perPage
        var index = 0
        while index < sources.count {
            let slice = Array(sources[index..<min(index + perPage, sources.count)])
            context.beginPDFPage(nil)
            drawPage(sources: slice, mediaBox: &mediaBox, context: context, config: config)
            context.endPDFPage()
            index += perPage
        }
        context.closePDF()
        return data as Data
    }

    /// 把结果 PDF 的每一页渲染成缩略图用于预览。
    public static func renderPreviews(data: Data, maxWidth: CGFloat = 520) -> [NSImage] {
        guard let doc = PDFDocument(data: data) else { return [] }
        var images: [NSImage] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale = maxWidth / max(bounds.width, 1)
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            images.append(page.thumbnail(of: size, for: .mediaBox))
        }
        return images
    }

    // MARK: - Layout

    private static func drawPage(sources: [PageSource], mediaBox: inout CGRect, context: CGContext, config: LayoutConfig) {
        let pageSize = mediaBox.size
        let margin = CGFloat(config.margin)
        let spacing = CGFloat(config.spacing)
        let columns = max(1, config.columns)
        let rows = max(1, config.rows)

        let usableWidth = pageSize.width - margin * 2 - spacing * CGFloat(columns - 1)
        let usableHeight = pageSize.height - margin * 2 - spacing * CGFloat(rows - 1)
        let cellWidth = max(usableWidth / CGFloat(columns), 1)
        let cellHeight = max(usableHeight / CGFloat(rows), 1)

        for (i, source) in sources.enumerated() {
            let col = i % columns
            let row = i / columns
            let cellX = margin + CGFloat(col) * (cellWidth + spacing)
            let cellTop = pageSize.height - margin - CGFloat(row) * (cellHeight + spacing)
            let cell = CGRect(x: cellX, y: cellTop - cellHeight, width: cellWidth, height: cellHeight)

            let content = source.contentSize
            guard content.width > 0, content.height > 0 else { continue }
            let fit = min(cell.width / content.width, cell.height / content.height) * CGFloat(config.scale)
            let drawWidth = content.width * fit
            let drawHeight = content.height * fit
            let drawX = cell.minX + (cell.width - drawWidth) / 2
            let drawY = cell.minY + (cell.height - drawHeight) / 2
            source.draw(in: CGRect(x: drawX, y: drawY, width: drawWidth, height: drawHeight), context: context)
        }
    }

    // MARK: - Loading

    private static func expand(items: [InputItem], expandAllPDFPages: Bool) throws -> [PageSource] {
        var result: [PageSource] = []
        for item in items {
            switch item.kind {
            case .pdf:
                guard let doc = PDFDocument(url: item.url) else { throw MergeError.cannotLoad(item.url) }
                let count = expandAllPDFPages ? doc.pageCount : min(1, doc.pageCount)
                for i in 0..<count {
                    result.append(.pdf(doc, i))
                }
            case .image:
                if let cg = loadImage(item.url) {
                    result.append(.image(cg))
                } else {
                    throw MergeError.cannotLoad(item.url)
                }
            }
        }
        return result
    }

    private static func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4000,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    // MARK: - File import helpers

    public static func loadInputItems(urls: [URL]) -> [InputItem] {
        urls.compactMap { url in
            guard url.isFileURL, let kind = ItemKind.from(url: url) else { return nil }
            let pages: Int
            switch kind {
            case .pdf:
                pages = PDFDocument(url: url)?.pageCount ?? 1
            case .image:
                pages = 1
            }
            return InputItem(url: url, kind: kind, pageCount: pages)
        }
    }

    public static let supportedTypes: [UTType] = [.pdf, .png, .jpeg, .tiff, .gif, .bmp, .heic, .webP]
}
