import SwiftUI

/// Floating controls at the bottom of the gallery: layout in the middle, zoom and sort on the right.
struct GalleryControls: View {
    @Binding var layoutStyle: GalleryLayoutStyle
    @Binding var scale: Double
    @Binding var sortOrder: GallerySortOrder

    var body: some View {
        ZStack {
            Picker("Layout", selection: $layoutStyle) {
                ForEach(GalleryLayoutStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(4)
            .floatingBackground(in: Capsule())

            HStack(spacing: 10) {
                Spacer()

                HStack(spacing: 8) {
                    Image(systemName: "plus.magnifyingglass")
                    Slider(value: $scale, in: 0.6...2)
                        .controlSize(.mini)
                        .frame(width: 100)
                        .accessibilityLabel("Zoom")
                    Text("×\(scale.formatted(.number.precision(.fractionLength(1))))")
                        .monospacedDigit()
                        .frame(width: 30, alignment: .leading)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .floatingBackground(in: Capsule())

                Menu {
                    Picker("Sort By", selection: $sortOrder) {
                        ForEach(GallerySortOrder.allCases) { order in
                            Text(order.title).tag(order)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Sort", systemImage: "line.3.horizontal.decrease")
                        .labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .frame(width: 34, height: 34)
                .floatingBackground(in: Circle())
                .help("Sort")
            }
        }
        .padding(.horizontal, 16)
    }
}

private extension View {
    @ViewBuilder
    func floatingBackground(in shape: some Shape) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay { shape.stroke(Color(nsColor: .separatorColor), lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.1), radius: 10, y: 3)
        }
    }
}
