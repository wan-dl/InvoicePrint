import Foundation
import AppKit
import PDFKit

enum PrintService {
    static func exportPDF(data: Data, suggestedName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        panel.title = "导出合并后的 PDF"
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    static func print(data: Data, paperSize: CGSize, jobName: String = "发票打印") {
        guard let doc = PDFDocument(data: data) else {
            presentError("无法生成打印文档")
            return
        }
        let printInfo = NSPrintInfo.shared
        printInfo.paperSize = paperSize
        printInfo.orientation = paperSize.width > paperSize.height ? .landscape : .portrait
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .fit
        printInfo.leftMargin = 0
        printInfo.rightMargin = 0
        printInfo.topMargin = 0
        printInfo.bottomMargin = 0
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = true

        let printView = PDFPrintView(document: doc, pageSize: paperSize)
        let op = NSPrintOperation(view: printView, printInfo: printInfo)
        op.jobTitle = jobName
        if let window = NSApp.keyWindow {
            op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            op.run()
        }
    }

    private static func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

/// 用于打印的视图：NSPrintOperation 会按页范围逐页调用 draw。
final class PDFPrintView: NSView {
    private let document: PDFDocument
    private let pageSize: NSSize
    private var currentPage = 0

    init(document: PDFDocument, pageSize: CGSize) {
        self.document = document
        self.pageSize = pageSize
        super.init(frame: NSRect(origin: .zero, size: pageSize))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { false }

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        range.pointee = NSRange(location: 1, length: document.pageCount)
        return true
    }

    override func rectForPage(_ page: Int) -> NSRect {
        currentPage = page - 1
        return NSRect(origin: .zero, size: pageSize)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let page = document.page(at: currentPage),
              let ctx = NSGraphicsContext.current?.cgContext else { return }
        page.draw(with: .mediaBox, to: ctx)
    }
}
