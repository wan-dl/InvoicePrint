import Foundation
import AppKit

public enum ItemKind: String, Codable, Sendable {
    case pdf
    case image

    public static func from(url: URL) -> ItemKind? {
        switch url.pathExtension.lowercased() {
        case "pdf": return .pdf
        case "png", "jpg", "jpeg", "heic", "tiff", "tif", "gif", "bmp", "webp": return .image
        default: return nil
        }
    }
}

public enum ItemOrigin: String, Codable, Sendable {
    case local
    case download

    public var title: String {
        switch self {
        case .local: return "本地"
        case .download: return "网络"
        }
    }
}

public struct InputItem: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let url: URL
    public let kind: ItemKind
    public let pageCount: Int
    public let origin: ItemOrigin

    public init(url: URL, kind: ItemKind, pageCount: Int, origin: ItemOrigin = .local) {
        self.url = url
        self.kind = kind
        self.pageCount = pageCount
        self.origin = origin
    }

    public var name: String { url.lastPathComponent }
}

public enum PaperSize: String, CaseIterable, Identifiable, Sendable {
    case a4Portrait
    case a4Landscape
    case a5Portrait
    case letterPortrait

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .a4Portrait: return "A4 纵向"
        case .a4Landscape: return "A4 横向"
        case .a5Portrait: return "A5 纵向"
        case .letterPortrait: return "Letter 纵向"
        }
    }

    /// 纸张尺寸，单位 pt（1pt = 1/72 inch）
    public var pointSize: CGSize {
        switch self {
        case .a4Portrait: return CGSize(width: 595.276, height: 841.89)
        case .a4Landscape: return CGSize(width: 841.89, height: 595.276)
        case .a5Portrait: return CGSize(width: 419.528, height: 595.276)
        case .letterPortrait: return CGSize(width: 612, height: 792)
        }
    }
}

public struct LayoutConfig: Equatable, Sendable {
    public var columns: Int
    public var rows: Int
    public var margin: Double
    public var spacing: Double
    public var scale: Double
    public var expandAllPDFPages: Bool
    public var paper: PaperSize

    public init(columns: Int = 1,
                rows: Int = 2,
                margin: Double = 18,
                spacing: Double = 10,
                scale: Double = 0.98,
                expandAllPDFPages: Bool = false,
                paper: PaperSize = .a4Portrait) {
        self.columns = columns
        self.rows = rows
        self.margin = margin
        self.spacing = spacing
        self.scale = scale
        self.expandAllPDFPages = expandAllPDFPages
        self.paper = paper
    }

    public var perPage: Int { max(1, columns * rows) }
}

public enum SortMode: String, CaseIterable, Identifiable, Sendable {
    case natural
    case name
    case addedOrder

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .natural: return "自然排序（1,2,10）"
        case .name: return "文件名排序"
        case .addedOrder: return "添加顺序"
        }
    }
}

public enum FileOrder {
    public static func naturalCompare(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.numeric, .caseInsensitive], range: nil, locale: nil) == .orderedAscending
    }
}
