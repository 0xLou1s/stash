import SwiftUI

struct RemoteImage: View {
    let url: URL
    /// `.fit` sizes itself from the image; `.fill` takes whatever frame it's given and crops.
    var contentMode: ContentMode = .fit
    var placeholderAspectRatio: CGFloat = 4 / 3

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
            switch phase {
            case .success(let image):
                if contentMode == .fill {
                    Color.clear
                        .overlay {
                            image
                                .resizable()
                                .scaledToFill()
                        }
                        .clipped()
                } else {
                    image
                        .resizable()
                        .scaledToFit()
                }
            case .failure:
                placeholder {
                    Image(systemName: "photo.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                }
            default:
                placeholder {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private func placeholder(@ViewBuilder content: () -> some View) -> some View {
        let base = Rectangle()
            .fill(.quaternary)
            .overlay { content() }

        if contentMode == .fill {
            base
        } else {
            base.aspectRatio(placeholderAspectRatio, contentMode: .fit)
        }
    }
}
