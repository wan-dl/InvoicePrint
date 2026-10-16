import SwiftUI
import InvoicePrintCore

struct SidebarView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if state.items.isEmpty {
                emptyHint
            } else {
                fileList
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [.accentColor, .accentColor.opacity(0.65)],
                                         startPoint: .top, endPoint: .bottom))
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text("发票文件")
                    .font(.headline)
                Text(state.items.isEmpty ? "尚未添加" : "\(state.items.count) 个文件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Button { state.addFiles() } label: { Label("添加文件…", systemImage: "doc.badge.plus") }
                Button { state.addDirectory() } label: { Label("添加文件夹…", systemImage: "folder.badge.plus") }
                Button { state.isDownloadPresented = true } label: { Label("从链接下载…", systemImage: "arrow.down.to.line") }
                Divider()
                Menu("排序方式") {
                    ForEach(SortMode.allCases) { mode in
                        Button(mode.title) { state.sortItems(mode) }
                    }
                }
                Divider()
                Button(role: .destructive) { state.clear() } label: { Label("清空列表", systemImage: "trash") }
                    .disabled(state.items.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var fileList: some View {
        List {
            ForEach(state.items) { item in
                FileRow(item: item)
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
            }
            .onMove { state.move(from: $0, to: $1) }
            .onDelete { state.remove(at: $0) }
        }
        .listStyle(.sidebar)
    }

    private var emptyHint: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 42, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            VStack(spacing: 4) {
                Text("拖入发票文件")
                    .font(.callout.weight(.medium))
                Text("支持 PDF、PNG、JPG、HEIC、TIFF")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                state.addFiles()
            } label: {
                Label("添加文件", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct FileRow: View {
    @EnvironmentObject var state: AppState
    let item: InputItem
    @State private var hovering = false

    private var tint: Color { item.kind == .pdf ? .red : .blue }
    private var symbol: String { item.kind == .pdf ? "doc.richtext.fill" : "photo.fill" }

    private var originBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: item.origin == .download ? "globe" : "folder")
                .font(.system(size: 8, weight: .semibold))
            Text(item.origin.title)
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(item.origin == .download ? Color.orange : Color.secondary)
        .padding(.horizontal, 4)
        .padding(.vertical, 0.5)
        .background(
            Capsule().fill((item.origin == .download ? Color.orange : Color.secondary).opacity(0.12))
        )
        .help(item.origin == .download ? "从网络下载" : "从本地导入")
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(0.15))
                Image(systemName: symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(tint)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 5) {
                    Text(item.kind == .pdf ? "PDF" : "图片")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    if item.kind == .pdf && item.pageCount > 1 {
                        Text("· \(item.pageCount) 页")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    originBadge
                }
            }

            Spacer(minLength: 4)

            if let amount = state.amounts[item.id] {
                Text(AmountExtractor.format(amount))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help("识别金额")
            }

            if hovering {
                Button {
                    state.remove(item)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("移除")
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
