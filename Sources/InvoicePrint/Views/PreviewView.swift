import SwiftUI
import InvoicePrintCore

struct PreviewView: View {
    @EnvironmentObject var state: AppState

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 22)]

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.white
                    .ignoresSafeArea()

                if state.previewPages.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 28) {
                            ForEach(Array(state.previewPages.enumerated()), id: \.offset) { index, image in
                                PageCard(index: index + 1, image: image)
                            }
                        }
                        .padding(32)
                    }
                }

                if state.isBuilding {
                    ProgressView("正在生成预览…")
                        .padding(.horizontal, 22)
                        .padding(.vertical, 16)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                }
            }

            statusBar
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(state.status)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if !state.previewPages.isEmpty {
                Text("每页 \(state.config.columns)×\(state.config.rows) · 共 \(state.config.perPage) 张")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Divider().frame(height: 12)
            }
            amountSummary
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(Color.white)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder
    private var amountSummary: some View {
        if state.detectedCount > 0 {
            Button {
                state.copyTotal()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "yensign.circle.fill")
                        .foregroundStyle(Color.green)
                    Text("合计 \(AmountExtractor.format(state.totalAmount))")
                        .font(.callout.weight(.semibold).monospacedDigit())
                    Text("(\(state.detectedCount)/\(state.items.count))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .help("点击复制合计金额")
        } else if state.amountsLoading {
            HStack(spacing: 5) {
                ProgressView().controlSize(.small)
                Text("识别金额…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("未识别到金额")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "printer.dotmatrix.fill")
                .font(.system(size: 60, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text("发票合并打印")
                    .font(.title2.weight(.semibold))
                Text("添加多个 PDF 或图片，自动排版到一张纸上方便打印")
                    .foregroundStyle(.secondary)
            }
            Button {
                state.addFiles()
            } label: {
                Label("添加文件", systemImage: "plus")
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PageCard: View {
    let index: Int
    let image: NSImage

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 9, x: 0, y: 4)

            Text("第 \(index) 页")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.secondary.opacity(0.12)))
        }
    }
}
