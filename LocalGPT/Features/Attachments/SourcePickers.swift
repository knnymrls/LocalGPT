import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The plus button's surface: one glass shape drawn by the app.
///
/// It scales up out of the plus as a menu (Camera, Photos, Files) sitting over
/// the button. The menu follows the finger loosely when dragged and springs
/// back; a swipe down sends it back into the plus. Choosing Photos or Camera
/// stretches the same shape, from its bottom-left corner, into the photo grid
/// or the viewfinder.
struct AddSurface: View {
    enum Mode { case menu, photos, camera }

    let onFiles: () -> Void
    let onClose: () -> Void

    @Environment(ChatSessionStore.self) private var chat
    /// Every opening starts as the menu.
    @State private var mode: Mode = .menu
    /// The finger's travel while it drags the menu.
    @State private var drag: CGSize = .zero
    @State private var isDragging = false
    @State private var dragEnded = Date.distantPast
    /// Photos ticked in the grid, in order. Nothing joins the chat until Add.
    @State private var picked: [(id: String, image: UIImage)] = []
    @State private var showAllPhotos = false
    @State private var allPhotos: [PhotosPickerItem] = []
    @State private var camera = CameraSession()

    private static let panelHeight: CGFloat = pt(505)
    private static let panelMargin: CGFloat = pt(12)
    private static let menuWidth: CGFloat = Tokens.scaled(196)
    /// One inset for the menu's glyphs: from its top, bottom, and left edges.
    private static let inset: CGFloat = pt(18)
    private static let rowHeight: CGFloat = Tokens.scaled(48)
    private static let glyph: CGFloat = 22
    /// The glyph sits centred in its row, so the menu's vertical padding is
    /// the inset minus that slack.
    private static var menuPadding: CGFloat {
        max(0, inset - (rowHeight - glyph * Tokens.uiScale) / 2)
    }
    private static var menuHeight: CGFloat { rowHeight * 3 + menuPadding * 2 }

    /// The menu sits on the composer's bottom-left corner, over the plus.
    private static let menuLeading: CGFloat = pt(16)
    private static let menuBottom: CGFloat = pt(8)
    /// The menu's rectangle inside the panel's frame.
    private static var menuInsetX: CGFloat { menuLeading - panelMargin }
    private static var menuInsetY: CGFloat { menuBottom + bottomSafeInset - panelMargin }

    private static var screenWidth: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.bounds.width }
            .first ?? 402
    }
    private static var panelWidth: CGFloat { screenWidth - panelMargin * 2 }

    private static var bottomSafeInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom }
            .first ?? 0
    }

    /// Where the plus button's centre falls inside the surface's frame; the
    /// surface scales in and out around it.
    static var plusAnchor: UnitPoint {
        let plus = pt(8) + Tokens.scaled(36) / 2
        return UnitPoint(
            x: (menuLeading + plus) / screenWidth,
            y: 1 - (menuBottom + plus) / (panelHeight + panelMargin - bottomSafeInset)
        )
    }

    private var expanded: Bool { mode != .menu }

    var body: some View {
        // One glass shape in one fixed frame. The shape stretches from the
        // menu's rectangle to the whole frame; what it holds swaps inside
        // it. Nothing is re-laid-out or moved while it stretches.
        let shape = SurfaceShape(
            progress: expanded ? 1 : 0,
            menuSize: CGSize(width: Self.menuWidth, height: Self.menuHeight),
            menuLeading: Self.menuInsetX, menuBottom: Self.menuInsetY
        )
        ZStack(alignment: .bottomLeading) {
            switch mode {
            case .menu:
                menu
                    .padding(.leading, Self.menuInsetX)
                    .padding(.bottom, Self.menuInsetY)
                    .transition(.opacity)
            case .photos, .camera:
                panelContent
                    .frame(width: Self.panelWidth, height: Self.panelHeight)
                    .transition(.scale(scale: 0.6, anchor: .bottomLeading).combined(with: .opacity))
            }
        }
        .frame(width: Self.panelWidth, height: Self.panelHeight, alignment: .bottomLeading)
        .clipShape(shape)
        // Glass does not draw inside a clipped view, so the surface's glass
        // and its controls sit outside the clip.
        .glassControl(in: shape)
        .overlay(alignment: .bottom) {
            if expanded {
                GlassEffectContainer { controls }
                    // In late and out early, so the controls never ride the
                    // glass while it changes size.
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.18).delay(0.2)),
                        removal: .opacity.animation(.easeOut(duration: 0.08))
                    ))
            }
        }
        // The menu rides the finger: it shrinks a little toward the plus as
        // it is pulled down, and moves a fraction of the finger's travel.
        .scaleEffect(expanded ? 1 : Self.dragScale(drag), anchor: Self.plusAnchor)
        .offset(expanded ? .zero : Self.dragOffset(drag))
        // The frame runs to the screen's bottom edge, past the safe area.
        .padding(.leading, Self.panelMargin)
        .padding(.bottom, Self.panelMargin - Self.bottomSafeInset)
        .frame(maxWidth: .infinity, alignment: .bottomLeading)
        // Growing has a little spring; folding back to the menu is plain.
        .animation(expanded ? .spring(duration: 0.4, bounce: 0.18) : .smooth(duration: 0.3), value: mode)
        // Have the recent photos ready before Photos is tapped, when access
        // was already given; this never prompts.
        .task { RecentPhotos.shared.loadIfAllowed() }
        .photosPicker(isPresented: $showAllPhotos, selection: $allPhotos, matching: .images)
        .onChange(of: allPhotos) { _, items in
            guard !items.isEmpty else { return }
            allPhotos = []
            for item in items { add(item) }
            onClose()
        }
    }

    @ViewBuilder
    private var panelContent: some View {
        if mode == .camera { viewfinder } else { photos }
    }

    // MARK: Menu

    private var menu: some View {
        VStack(alignment: .leading, spacing: 0) {
            row("Camera", icon: .camera) { grow(to: .camera) }
            row("Photos", icon: .images) { grow(to: .photos) }
            row("Files", icon: .folder, action: onFiles)
        }
        .padding(.vertical, Self.menuPadding)
        .frame(width: Self.menuWidth)
        .contentShape(Rectangle())
        // Measured against the screen, not the menu, because the menu moves
        // under the finger.
        .simultaneousGesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .global)
                .onChanged { value in
                    isDragging = true
                    drag = value.translation
                }
                .onEnded { value in
                    isDragging = false
                    dragEnded = Date()
                    // A pull or a flick downward sends it back into the plus.
                    if value.translation.height > 70 || value.predictedEndTranslation.height > 180 {
                        onClose()
                    } else {
                        withAnimation(.spring(duration: 0.45, bounce: 0.32)) { drag = .zero }
                    }
                }
        )
    }

    private func row(_ title: String, icon: NucleoIcon, action: @escaping () -> Void) -> some View {
        Button {
            // A release that ends a drag is not a choice.
            guard !isDragging, Date().timeIntervalSince(dragEnded) > 0.2 else { return }
            action()
        } label: {
            HStack(spacing: pt(12)) {
                Icon(icon, size: Self.glyph, color: Tokens.foreground)
                Text(title)
                    .font(.text)
                    .foregroundStyle(Tokens.foreground)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Self.inset)
            .frame(height: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowStyle(quiet: isDragging))
    }

    private func grow(to target: Mode) {
        // The grown surface takes the keyboard's place.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        mode = target
    }

    /// The menu moves a fraction of the finger's travel, easing off the
    /// further it is pulled.
    private static func dragOffset(_ drag: CGSize) -> CGSize {
        func eased(_ distance: CGFloat) -> CGFloat {
            let limit: CGFloat = 90
            return limit * (1 - 1 / (abs(distance) * 0.55 / limit + 1)) * (distance < 0 ? -1 : 1)
        }
        return CGSize(width: eased(drag.width), height: eased(drag.height))
    }

    private static func dragScale(_ drag: CGSize) -> CGFloat {
        1 - min(0.12, max(0, drag.height) / 900)
    }

    // MARK: Photos and camera

    private var photos: some View {
        RecentPhotosGrid(selected: Set(picked.map(\.id)), onTap: toggle)
    }

    private var viewfinder: some View {
        CameraPreview(session: camera.session)
            .background(Color.black)
            .overlay {
                if !camera.isAvailable {
                    VStack(spacing: pt(10)) {
                        Icon(.camera, size: 28, color: .white.opacity(0.5))
                        Text("No camera on this device")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .task {
                guard await AVCaptureDevice.requestAccess(for: .video) else { return }
                camera.start()
            }
            .onDisappear { camera.stop() }
    }

    private var controls: some View {
        ZStack {
            HStack {
                GlassCircleButton(icon: .chevronLeft, accessibilityLabel: "Back") {
                    picked = []
                    mode = .menu
                }
                Spacer()
                if mode == .photos { photosButton }
            }
            if mode == .camera {
                // A glass ring like the back button's, with the white
                // shutter inset inside it.
                Button(action: capture) {
                    Circle()
                        .fill(.white)
                        .frame(width: pt(56), height: pt(56))
                        .padding(pt(4))
                        .glassControl(in: Circle(), interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Take photo"))
            }
        }
        .padding(.horizontal, pt(22))
        .padding(.bottom, pt(22))
    }

    /// The label changes to "Add 3 photos" when there is a selection.
    /// Both states keep the same system glass appearance.
    private var photosButton: some View {
        let count = picked.count
        return Button {
            if count == 0 { showAllPhotos = true } else { addPicked() }
        } label: {
            Text(count == 0 ? "All Photos" : "Add \(count) \(count == 1 ? "photo" : "photos")")
                .font(.title)
                .monospacedDigit()
                .foregroundStyle(Tokens.foreground)
                .contentTransition(.numericText(value: Double(count)))
                .padding(.horizontal, pt(18))
                .frame(height: Tokens.scaled(44))
                .glassControl(in: Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.25), value: count)
    }

    // MARK: Adding

    private func toggle(_ id: String, _ image: UIImage) {
        withAnimation(.smooth(duration: 0.25)) {
            if let index = picked.firstIndex(where: { $0.id == id }) {
                picked.remove(at: index)
            } else {
                picked.append((id, image))
            }
        }
    }

    private func addPicked() {
        let origin = chat.activeID
        for item in picked {
            Task {
                do {
                    let data = try await PhotoOriginal.load(id: item.id)
                    try await addPhoto(data, conversationID: origin)
                } catch { chat.operationError = error.localizedDescription }
            }
        }
        onClose()
    }

    private func add(_ item: PhotosPickerItem) {
        let origin = chat.activeID
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw WorkspaceError.message("The photo could not be read.")
                }
                try await addPhoto(data, conversationID: origin)
            } catch { chat.operationError = error.localizedDescription }
        }
    }

    private func addPhoto(_ data: Data, conversationID: UUID) async throws {
        let thumbnail = await Thumbnail.make(from: data)
        let url = try await Task.detached { try ImportStaging.store(data, named: "Photo.jpg") }.value
        withAnimation(.smooth(duration: 0.3)) {
            _ = chat.addAttachment(name: "Photo.jpg", kind: .image, thumbnail: thumbnail, fileURL: url, conversationID: conversationID)
        }
    }

    private func capture() {
        guard camera.isAvailable else {
            chat.operationError = "A camera is not available on this Simulator. Add an image from Files or Photos."
            onClose()
            return
        }
        let origin = chat.activeID
        camera.capture { data in
            Task { @MainActor in
                do { try await addPhoto(data, conversationID: origin) }
                catch { chat.operationError = error.localizedDescription }
                onClose()
            }
        }
    }

}

// MARK: - Recent photos

/// The library's most recent photos as a tight three-column grid.
private struct RecentPhotosGrid: View {
    let selected: Set<String>
    let onTap: (String, UIImage) -> Void

    private var library: RecentPhotos { .shared }

    private static let gap: CGFloat = pt(4)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.gap), count: 3), spacing: Self.gap) {
                ForEach(library.assets, id: \.localIdentifier) { asset in
                    PhotoCell(asset: asset, isSelected: selected.contains(asset.localIdentifier), onTap: onTap)
                }
            }
            // The last row clears the floating controls.
            .padding(.bottom, Tokens.scaled(44) + pt(44))
        }
        .scrollIndicators(.hidden)
        .overlay {
            if library.denied {
                Text("Allow photo access in Settings to see recent photos here, or use All Photos.")
                    .font(.caption)
                    .foregroundStyle(Tokens.foregroundMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, pt(40))
            }
        }
        .task { await library.requestAndLoad() }
    }
}

/// The library's most recent photos and their thumbnails, kept for the life
/// of the app so the grid has them the moment it appears.
@MainActor
@Observable
private final class RecentPhotos {
    static let shared = RecentPhotos()

    private(set) var assets: [PHAsset] = []
    private(set) var denied = false
    @ObservationIgnored private let thumbnails = NSCache<NSString, UIImage>()

    /// Loads without prompting; does nothing until access has been given.
    func loadIfAllowed() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .authorized || status == .limited { load() }
    }

    func requestAndLoad() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        if status == .authorized || status == .limited { load() } else { denied = true }
    }

    func thumbnail(for asset: PHAsset) -> UIImage? {
        thumbnails.object(forKey: asset.localIdentifier as NSString)
    }

    func loadThumbnail(for asset: PHAsset, then done: @escaping @MainActor (UIImage) -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = false
        let key = asset.localIdentifier as NSString
        PHImageManager.default().requestImage(
            for: asset, targetSize: CGSize(width: 420, height: 420), contentMode: .aspectFill, options: options
        ) { result, _ in
            guard let result else { return }
            Task { @MainActor in
                self.thumbnails.setObject(result, forKey: key)
                done(result)
            }
        }
    }

    private func load() {
        guard assets.isEmpty else { return }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 90
        let result = PHAsset.fetchAssets(with: .image, options: options)
        assets = result.objects(at: IndexSet(integersIn: 0..<result.count))
        // Warm the first screenful.
        for asset in assets.prefix(15) { loadThumbnail(for: asset) { _ in } }
    }
}

private struct PhotoCell: View {
    let asset: PHAsset
    let isSelected: Bool
    let onTap: (String, UIImage) -> Void

    @State private var image: UIImage?

    init(asset: PHAsset, isSelected: Bool, onTap: @escaping (String, UIImage) -> Void) {
        self.asset = asset
        self.isSelected = isSelected
        self.onTap = onTap
        _image = State(initialValue: RecentPhotos.shared.thumbnail(for: asset))
    }

    var body: some View {
        Button {
            if let image { onTap(asset.localIdentifier, image) }
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Tokens.hover
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: pt(4), style: .continuous))
                .overlay {
                    if isSelected { Color.black.opacity(0.3) }
                }
                .overlay(alignment: .bottomTrailing) {
                    if isSelected {
                        Icon(.done, size: 13, color: .black)
                            .frame(width: pt(24), height: pt(24))
                            .background(.white, in: Circle())
                            .padding(pt(8))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Photo"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .task(id: asset.localIdentifier) {
            RecentPhotos.shared.loadThumbnail(for: asset) { image = $0 }
        }
    }
}

extension View {
    /// The system file browser for the add menu's Files; picked files join the chat.
    func sourceFileImporter(isPresented: Binding<Bool>, chat: ChatSessionStore) -> some View {
        fileImporter(isPresented: isPresented, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            let origin = chat.activeID
            Task {
                for url in urls {
                    do {
                        let kind = Attachment.Kind(fileExtension: url.pathExtension)
                        let copy = try await Task.detached { try ImportStaging.copy(url) }.value
                        let thumbnail: Data?
                        if kind == .image {
                            let data = try await Task.detached { try Data(contentsOf: copy) }.value
                            thumbnail = await Thumbnail.make(from: data)
                        } else { thumbnail = nil }
                        withAnimation(.smooth(duration: 0.3)) {
                            _ = chat.addAttachment(name: url.lastPathComponent, kind: kind, thumbnail: thumbnail,
                                                   fileURL: copy, conversationID: origin)
                        }
                    } catch { chat.operationError = error.localizedDescription }
                }
            }
        }
    }
}

/// A small encoded copy of a picked image, sized for a source card.
private enum Thumbnail {
    private static let shortSide: CGFloat = 360

    nonisolated static func make(from data: Data) async -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let short = min(image.size.width, image.size.height)
        guard short > 0 else { return nil }
        let ratio = min(1, shortSide / short)
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        return (image.preparingThumbnail(of: size) ?? image).jpegData(compressionQuality: 0.8)
    }
}

// MARK: - Camera

/// One back-camera capture session for the panel's viewfinder and shutter.
private final class CameraSession: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "localgpt.camera")
    private var configured = false
    private var onPhoto: (@Sendable (Data) -> Void)?

    let isAvailable = AVCaptureDevice.default(for: .video) != nil

    func start() {
        queue.async { [self] in
            if !configured {
                configured = true
                guard let device = AVCaptureDevice.default(for: .video),
                      let input = try? AVCaptureDeviceInput(device: device),
                      session.canAddInput(input), session.canAddOutput(output) else { return }
                session.beginConfiguration()
                session.sessionPreset = .photo
                session.addInput(input)
                session.addOutput(output)
                session.commitConfiguration()
            }
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func capture(_ done: @escaping @Sendable (Data) -> Void) {
        queue.async { [self] in
            guard session.isRunning else { return }
            onPhoto = done
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation() else { return }
        queue.async { [self] in
            onPhoto?(data)
            onPhoto = nil
        }
    }
}

/// A menu row's pressed mark: a small rounded container inset from the
/// menu's edge, shown only while the row is held.
private struct MenuRowStyle: ButtonStyle {
    /// No mark while the menu is being dragged.
    let quiet: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: pt(16), style: .continuous)
                    .fill(Tokens.pressWash)
                    .padding(.horizontal, pt(6))
                    .opacity(configuration.isPressed && !quiet ? 1 : 0)
            }
            .animation(.easeOut(duration: configuration.isPressed ? 0.06 : 0.2), value: configuration.isPressed)
    }
}

/// The surface's outline: the menu's rounded rectangle at `progress` 0, the
/// whole frame at 1, stretching from the bottom-left corner in between.
private struct SurfaceShape: InsettableShape {
    var progress: CGFloat
    let menuSize: CGSize
    let menuLeading: CGFloat
    let menuBottom: CGFloat
    var inset: CGFloat = 0

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        func mix(_ from: CGFloat, _ to: CGFloat) -> CGFloat { from + (to - from) * progress }
        let width = mix(menuSize.width, rect.width)
        let height = mix(menuSize.height, rect.height)
        let frame = CGRect(
            x: rect.minX + mix(menuLeading, 0),
            y: rect.maxY - mix(menuBottom, 0) - height,
            width: width, height: height
        ).insetBy(dx: inset, dy: inset)
        let top = max(0, mix(pt(24), pt(40)) - inset)
        let bottom = max(0, mix(pt(24), pt(50)) - inset)
        return UnevenRoundedRectangle(
            topLeadingRadius: top, bottomLeadingRadius: bottom,
            bottomTrailingRadius: bottom, topTrailingRadius: top, style: .continuous
        ).path(in: frame)
    }

    func inset(by amount: CGFloat) -> SurfaceShape {
        var copy = self
        copy.inset += amount
        return copy
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        // swiftlint:disable:next force_cast
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
