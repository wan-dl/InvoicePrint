import SwiftUI
import InvoicePrintCore

struct LayoutPreset: Identifiable, Hashable {
    let columns: Int
    let rows: Int

    var id: String { "\(columns)x\(rows)" }
    var title: String { "\(columns)×\(rows)" }

    static let all: [LayoutPreset] = [
        LayoutPreset(columns: 1, rows: 1),
        LayoutPreset(columns: 2, rows: 1),
        LayoutPreset(columns: 1, rows: 2),
        LayoutPreset(columns: 2, rows: 2),
        LayoutPreset(columns: 3, rows: 1),
        LayoutPreset(columns: 1, rows: 3),
        LayoutPreset(columns: 3, rows: 2),
        LayoutPreset(columns: 2, rows: 3),
        LayoutPreset(columns: 3, rows: 3)
    ]

    static func matching(rows: Int, columns: Int) -> LayoutPreset? {
        all.first { $0.rows == rows && $0.columns == columns }
    }
}

struct SettingsBar: View {
    @EnvironmentObject var state: AppState

    private var presetBinding: Binding<LayoutPreset> {
        Binding(
            get: {
                LayoutPreset.matching(rows: state.config.rows, columns: state.config.columns)
                    ?? LayoutPreset(columns: state.config.columns, rows: state.config.rows)
            },
            set: { preset in
                state.config.columns = preset.columns
                state.config.rows = preset.rows
            }
        )
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            singleRow
            stackedRows
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var singleRow: some View {
        HStack(spacing: 14) {
            presetControl
            divider
            paperControl
            divider
            scaleSlider
            marginSlider
            divider
            multiPageToggle
            Spacer(minLength: 0)
        }
    }

    private var stackedRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                presetControl
                paperControl
                Spacer(minLength: 0)
                multiPageToggle
            }
            HStack(spacing: 14) {
                scaleSlider
                marginSlider
                Spacer(minLength: 0)
            }
        }
    }

    private var divider: some View {
        Divider().frame(height: 20)
    }

    private var presetControl: some View {
        Picker(selection: presetBinding) {
            ForEach(LayoutPreset.all) { preset in
                Text("\(preset.title)　每页 \(preset.columns * preset.rows) 张").tag(preset)
            }
        } label: {
            Label("宫格", systemImage: "square.grid.2x2")
        }
        .pickerStyle(.menu)
        .fixedSize()
        .help("每页排版（列×行）")
    }

    private var paperControl: some View {
        Picker(selection: $state.config.paper) {
            ForEach(PaperSize.allCases) { size in
                Text(size.title).tag(size)
            }
        } label: {
            Label("纸张", systemImage: "doc")
        }
        .pickerStyle(.menu)
        .fixedSize()
        .help("纸张")
    }

    private var scaleSlider: some View {
        slider(icon: "arrow.up.left.and.arrow.down.right",
               value: $state.config.scale,
               range: 0.4...1.0,
               text: String(format: "%.0f%%", state.config.scale * 100),
               help: "内容缩放")
    }

    private var marginSlider: some View {
        slider(icon: "square.dashed",
               value: $state.config.margin,
               range: 0...60,
               text: "\(Int(state.config.margin))pt",
               help: "页边距")
    }

    private var multiPageToggle: some View {
        Toggle(isOn: $state.config.expandAllPDFPages) {
            Text("含多页")
                .font(.callout)
        }
        .toggleStyle(.checkbox)
        .fixedSize()
        .help("包含 PDF 的全部页面")
    }

    private func slider(icon: String,
                        value: Binding<Double>,
                        range: ClosedRange<Double>,
                        text: String,
                        help: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Slider(value: value, in: range)
                .frame(width: 84)
            Text(text)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .leading)
        }
        .fixedSize()
        .help(help)
    }
}
