import Foundation
import InvoicePrintCore

func printUsage() {
    let text = """
    invoiceprint — 把多个发票 PDF / 图片合并到一页纸上方便打印

    用法:
      invoiceprint <目录> [选项]              目录下所有 PDF/图片自动分组
      invoiceprint <文件1> <文件2> ... [选项]  指定文件合并
      invoiceprint <文件...> -o 输出.pdf      合并为单个 PDF

    选项:
      -o, --output <path>   输出文件（单页合并时使用，默认 合并_时间戳.pdf）
      -d, --outdir <dir>    目录模式输出目录（默认 merged）
      -r, --rows <n>        每页行数（默认 1）
      -c, --cols <n>        每页列数（默认 1）
      -s, --scale <f>       内容缩放 0~1（默认 1.0）
      -m, --margin <pt>     页边距，单位 pt（默认 18）
      -g, --gap <pt>        格子间距，单位 pt（默认 10）
      -p, --paper <name>    a4 | a4l | a5 | letter（默认 a4）
          --all             包含 PDF 的全部页面（默认只取首页）
      -A, --amounts         仅识别各文件金额并输出合计
      -h, --help            显示帮助
    """
    print(text)
}

struct Options {
    var output: String?
    var outdir: String = "merged"
    var config = LayoutConfig(columns: 1, rows: 1, margin: 18, spacing: 10, scale: 1.0)
}

func parsePaper(_ name: String) -> PaperSize? {
    switch name.lowercased() {
    case "a4": return .a4Portrait
    case "a4l", "a4landscape": return .a4Landscape
    case "a5": return .a5Portrait
    case "letter": return .letterPortrait
    default: return nil
    }
}

func timestamp() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyyMMdd_HHmmss_SSS"
    return f.string(from: Date())
}

let args = Array(CommandLine.arguments.dropFirst())
if args.isEmpty || args.contains("-h") || args.contains("--help") {
    printUsage()
    exit(args.isEmpty ? 1 : 0)
}

var options = Options()
var paths: [String] = []
var amountsOnly = false
var i = 0
while i < args.count {
    let arg = args[i]
    func value() -> String? {
        if i + 1 < args.count { i += 1; return args[i] }
        return nil
    }
    switch arg {
    case "-o", "--output": options.output = value()
    case "-d", "--outdir": options.outdir = value() ?? options.outdir
    case "-r", "--rows": options.config.rows = Int(value() ?? "") ?? options.config.rows
    case "-c", "--cols": options.config.columns = Int(value() ?? "") ?? options.config.columns
    case "-s", "--scale": options.config.scale = Double(value() ?? "") ?? options.config.scale
    case "-m", "--margin": options.config.margin = Double(value() ?? "") ?? options.config.margin
    case "-g", "--gap": options.config.spacing = Double(value() ?? "") ?? options.config.spacing
    case "-p", "--paper":
        if let name = value(), let paper = parsePaper(name) { options.config.paper = paper }
    case "--all": options.config.expandAllPDFPages = true
    case "-A", "--amounts": amountsOnly = true
    default:
        if arg.hasPrefix("-") {
            FileHandle.standardError.write("未知参数: \(arg)\n".data(using: .utf8)!)
            exit(2)
        }
        paths.append(arg)
    }
    i += 1
}

let fm = FileManager.default
guard !paths.isEmpty else {
    FileHandle.standardError.write("请指定目录或文件\n".data(using: .utf8)!)
    exit(2)
}

if amountsOnly {
    var files: [URL] = []
    var isDir: ObjCBool = false
    if paths.count == 1, fm.fileExists(atPath: paths[0], isDirectory: &isDir), isDir.boolValue {
        let dir = URL(fileURLWithPath: paths[0])
        files = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
            .filter { ItemKind.from(url: $0) != nil }
            .sorted { FileOrder.naturalCompare($0.lastPathComponent, $1.lastPathComponent) }
    } else {
        files = paths.map { URL(fileURLWithPath: $0) }
    }
    let items = MergeEngine.loadInputItems(urls: files)
    var total = 0.0
    var found = 0
    for item in items {
        let amount = AmountExtractor.extract(url: item.url, kind: item.kind)
        if let amount { total += amount; found += 1 }
        let text = amount.map { AmountExtractor.format($0) } ?? "未识别"
        print("\(text.padding(toLength: max(text.count, 12), withPad: " ", startingAt: 0))  \(item.name)")
    }
    print(String(repeating: "-", count: 40))
    print("合计: \(AmountExtractor.format(total))   (\(found)/\(items.count) 已识别)")
    exit(0)
}

do {
    let isDirectory = paths.count == 1 && {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: paths[0], isDirectory: &isDir) && isDir.boolValue
    }()

    if isDirectory {
        let dir = URL(fileURLWithPath: paths[0])
        let entries = (try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]))
            .filter { ItemKind.from(url: $0) != nil }
            .sorted { FileOrder.naturalCompare($0.lastPathComponent, $1.lastPathComponent) }
        guard !entries.isEmpty else {
            FileHandle.standardError.write("目录中没有 PDF 或图片: \(dir.path)\n".data(using: .utf8)!)
            exit(1)
        }
        let outDir = URL(fileURLWithPath: options.outdir)
        try fm.createDirectory(at: outDir, withIntermediateDirectories: true)
        let perPage = options.config.perPage
        var index = 0
        var group = 1
        while index < entries.count {
            let chunk = Array(entries[index..<min(index + perPage, entries.count)])
            let items = MergeEngine.loadInputItems(urls: chunk)
            let data = try MergeEngine.buildPDF(items: items, config: options.config)
            let out = outDir.appendingPathComponent("合并_\(group).pdf")
            try data.write(to: out)
            print("\(out.path)  <-  \(chunk.map { $0.lastPathComponent }.joined(separator: ", "))")
            index += perPage
            group += 1
        }
    } else {
        let urls = paths.map { URL(fileURLWithPath: $0) }
        let missing = urls.filter { !fm.fileExists(atPath: $0.path) }
        if let first = missing.first {
            FileHandle.standardError.write("文件不存在: \(first.path)\n".data(using: .utf8)!)
            exit(1)
        }
        let items = MergeEngine.loadInputItems(urls: urls)
        guard !items.isEmpty else {
            FileHandle.standardError.write("没有可识别的 PDF 或图片\n".data(using: .utf8)!)
            exit(1)
        }
        let data = try MergeEngine.buildPDF(items: items, config: options.config)
        let outPath = options.output ?? "合并_\(timestamp()).pdf"
        let out = URL(fileURLWithPath: outPath)
        try data.write(to: out)
        print("\(out.path)  <-  \(urls.map { $0.lastPathComponent }.joined(separator: ", "))")
    }
} catch {
    FileHandle.standardError.write("错误: \(error.localizedDescription)\n".data(using: .utf8)!)
    exit(1)
}
