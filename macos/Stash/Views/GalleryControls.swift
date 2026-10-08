import SwiftUI

/// Floating controls at the bottom of the gallery: layout in the middle, zoom and sort on the right.
struct GalleryControls: View {
    @Binding var layoutStyle: GalleryLayoutStyle
    @Binding var scale: Double
    @Binding var sortOrder: GallerySortOrder

    var body: some View {
        ZStack {
            LayoutSwitcher(selection: $layoutStyle)
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

/// Text tabs with a pill that slides to the selected one. A segmented Picker
/// draws its own bezel, which clashes with the glass capsule around it.
private struct LayoutSwitcher: View {
    @Binding var selection: GalleryLayoutStyle
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(GalleryLayoutStyle.allCases) { style in
                let isSelected = selection == style

                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = style }
                } label: {
                    Text(style.title)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.14) : Color.white)
                                    .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.08), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "highlight", in: highlight)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Layout")
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
