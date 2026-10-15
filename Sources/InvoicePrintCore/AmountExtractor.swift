import Foundation
import AppKit
import CoreGraphics
import PDFKit
import Vision

/// 从发票 PDF / 图片中自动提取金额。
public enum AmountExtractor {

    /// 提取一个文件（取首页）的金额，失败返回 nil。
    public static func extract(url: URL, kind: ItemKind) -> Double? {
        let text = extractText(url: url, kind: kind)
        if let value = parseAmount(from: text) { return value }

        // 文本层损坏（字体无 ToUnicode 映射）时回退到 OCR
        if kind == .pdf, let doc = PDFDocument(url: url),
           let image = renderImage(page: doc.page(at: 0), maxWidth: 2000) {
            return parseAmount(from: ocr(image))
        }
        return nil
    }

    // MARK: - 文本获取

    static func extractText(url: URL, kind: ItemKind) -> String {
        switch kind {
        case .pdf:
            guard let doc = PDFDocument(url: url) else { return "" }
            var buffer = ""
            for i in 0..<min(2, doc.pageCount) {
                if let s = doc.page(at: i)?.string {
                    buffer += s + "\n"
                }
            }
            return buffer
        case .image:
            if let cg = loadImage(url) {
                return ocr(cg)
            }
            return ""
        }
    }

    private static func renderImage(page: PDFPage?, maxWidth: CGFloat) -> CGImage? {
        guard let page else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let scale = maxWidth / max(bounds.width, 1)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let thumbnail = page.thumbnail(of: size, for: .mediaBox)
        var rect = CGRect(origin: .zero, size: thumbnail.size)
        return thumbnail.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private static func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2400
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func ocr(_ image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([request])
        let observations = request.results ?? []
        return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    // MARK: - 金额解析

    /// 从识别文本中解析金额（人民币）。
    public static func parseAmount(from raw: String) -> Double? {
        let text = normalize(raw)

        // 1. 价税合计（小写）金额 —— 增值税发票最可靠
        if let value = amount(after: "价税合计", in: text) { return value }
        if let value = amount(after: "小写", in: text) { return value }

        // 2. 常见合计关键字
        for keyword in ["合计", "总计", "金额合计", "实收金额", "应收", "应付", "实付", "合计金额", "金额"] {
            if let value = amount(after: keyword, in: text) { return value }
        }

        // 3. 带货币符号的金额，取最大值
        let symbolAmounts = numbers(in: text, pattern: "[¥￥]\\s*([0-9][0-9,]*\\.?[0-9]{0,2})")
        if let max = symbolAmounts.max(), max > 0 { return max }

        // 4. 退而求其次：取文本中最大的带两位小数的数字
        let decimals = numbers(in: text, pattern: "([0-9][0-9,]*\\.[0-9]{2})")
        return decimals.max()
    }

    private static func amount(after keyword: String, in text: String) -> Double? {
        guard let range = text.range(of: keyword) else { return nil }
        let tail = String(text[range.upperBound...].prefix(80))
        if let value = numbers(in: tail, pattern: "[¥￥]\\s*([0-9][0-9,]*\\.?[0-9]{0,2})").first {
            return value
        }
        if let value = numbers(in: tail, pattern: "([0-9][0-9,]*\\.[0-9]{1,2})").first {
            return value
        }
        return nil
    }

    private static func numbers(in text: String, pattern: String) -> [Double] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { match in
            let groupIndex = match.numberOfRanges > 1 ? 1 : 0
            let raw = ns.substring(with: match.range(at: groupIndex))
            let cleaned = raw.replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespaces)
            return Double(cleaned)
        }
    }

    private static func normalize(_ raw: String) -> String {
        var result = raw
        let map: [Character: Character] = [
            "０": "0", "１": "1", "２": "2", "３": "3", "４": "4",
            "５": "5", "６": "6", "７": "7", "８": "8", "９": "9",
            "．": ".", "，": ",", "：": ":", "￥": "¥"
        ]
        result = String(result.map { map[$0] ?? $0 })
        return result
    }

    // MARK: - 格式化

    public static func format(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "¥"
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "¥%.2f", amount)
    }
}
