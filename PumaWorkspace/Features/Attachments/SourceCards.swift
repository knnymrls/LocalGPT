import SwiftUI

/// What this chat can read, as a row of square cards inside the composer,
/// above the field. Photos are square thumbnails; files show their icon and
/// name. The row drags sideways, each card has an X, and removing one slides
/// the rest left to close the gap.
struct SourceCards: View {
    @Environment(ChatSessionStore.self) private var chat
    @Environment(NavigationState.self) private var navigation

    static let side: CGFloat = Tokens.scaled(104)
    private static let radius: CGFloat = pt(18)

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: pt(8)) {
                ForEach(chat.chatSources) { source in
                    card(source)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.3), value: chat.chatSources.map(\.id))
        }
        .scrollIndicators(.hidden)
        // Cards scroll out under the composer's own rounded edge.
        .scrollClipDisabled()
        .frame(height: Self.side)
    }

    private func card(_ source: Attachment) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        return ZStack(alignment: .topTrailing) {
            Button {
                navigation.present(.file(source.id))
            } label: {
                Group {
                    if source.kind == .image { photo(source) } else { file(source) }
                }
                .frame(width: Self.side, height: Self.side)
                .background(Tokens.hover, in: shape)
                .clipShape(shape)
                .contentShape(shape)
            }
            .buttonStyle(.plain)
            .disabled(source.readiness != .ready)
            .accessibilityLabel(Text("Open \(source.name)"))

            removeButton(source)
        }
        .frame(width: Self.side, height: Self.side)
        .opacity(source.readiness == .importing ? 0.5 : 1)
        .accessibilityElement(children: .contain)
    }

    /// A photo's square: its thumbnail, filling the card. Fixtures have no
    /// image, so they keep a quiet placeholder of the same shape.
    @ViewBuilder
    private func photo(_ source: Attachment) -> some View {
        if let data = source.thumbnail, let image = UIImage(data: data) {
            Color.clear.overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        } else {
            Icon(source.kind.icon, size: 26, color: Tokens.foregroundMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func file(_ source: Attachment) -> some View {
        VStack(alignment: .leading, spacing: pt(8)) {
            FileBadge(file: source)
            Text(source.name)
                .font(.caption)
                .foregroundStyle(Tokens.foreground)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(pt(12))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func removeButton(_ source: Attachment) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.3)) { chat.removeFromChat(source.id) }
        } label: {
            Icon(.xmark, size: 11, color: .white)
                .frame(width: pt(24), height: pt(24))
                .background(Color.black.opacity(0.55), in: Circle())
                // A comfortable target around the small circle.
                .padding(pt(6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text("Remove \(source.name)"))
    }
}

/// A Nucleo glyph for a native menu row. UIMenu only draws images, so the
/// vector icon is rasterised once and handed over as a template image.
struct MenuIcon: View {
    let icon: NucleoIcon
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if let image = MenuIconCache.image(for: icon, scale: displayScale) {
            Image(uiImage: image)
        }
    }
}

@MainActor
private enum MenuIconCache {
    private static var images: [NucleoIcon: UIImage] = [:]

    static func image(for icon: NucleoIcon, scale: CGFloat) -> UIImage? {
        if let cached = images[icon] { return cached }
        // 24pt, matching the system's own menu symbols.
        let renderer = ImageRenderer(content: Icon(icon, size: 24, color: .black))
        renderer.scale = scale
        guard let cgImage = renderer.cgImage else { return nil }
        let image = UIImage(cgImage: cgImage, scale: scale, orientation: .up)
            .withRenderingMode(.alwaysTemplate)
        images[icon] = image
        return image
    }
}
