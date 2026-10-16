import SwiftUI
import AppKit

struct DownloadSheet: View {
    @EnvironmentObject var state: AppState
    @FocusState private var editorFocused: Bool

    private var isEmpty: Bool {
        state.downloadURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            editor
            footer
        }
        .padding(20)
        .frame(width: 480)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [.accentColor, .accentColor.opacity(0.65)],
                                         startPoint: .top, endPoint: .bottom))
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("从链接下载发票")
                    .font(.headline)
                Text("每行一个链接，支持 PDF 与图片")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $state.downloadURLText)
                .font(.system(.body, design: .monospaced))
                .focused($editorFocused)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.25))
                )

            if state.downloadURLText.isEmpty {
                Text("https://example.com/invoice.pdf\nhttps://example.com/invoice.png")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color.secondary.opacity(0.55))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 150)
        .onAppear { editorFocused = true }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("保存到 \(AppState.todayTempDirectory().path)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(AppState.todayTempDirectory().path)

            Spacer(minLength: 12)

            Button("取消") {
                state.isDownloadPresented = false
            }
            .keyboardShortcut(.cancelAction)

            Button("下载") {
                state.startDownload()
                state.isDownloadPresented = false
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isEmpty)
        }
    }
}
