import SwiftUI
import UIKit

struct RootShell: View {
    @State private var chat: ChatSessionStore
    @State private var voice: VoiceSessionController
    @State private var reader: SpeechReader
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigation = NavigationState()

    init(container: AppContainer, reader: SpeechReader = .shared) {
        _reader = State(initialValue: reader)
        let chat = ChatSessionStore(container: container)
        _chat = State(initialValue: chat)
        _voice = State(initialValue: VoiceSessionController(speech: container.speech, chat: chat, stopReading: { reader.stop() }))
    }

    var body: some View {
        DrawerReveal()
            .overlay {
                if navigation.searchOpen {
                    SearchScreen()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: navigation.searchOpen)
            .workspaceSheets()
            .alert("Workspace", isPresented: Binding(get: { chat.operationError != nil }, set: { if !$0 { chat.operationError = nil } })) {
                Button("OK") { chat.operationError = nil }
            } message: { Text(chat.operationError ?? "") }
            .onChange(of: chat.conversationStore.error) { _, reason in
                if let reason { chat.operationError = reason; chat.conversationStore.error = nil }
            }
            .onChange(of: chat.attachmentStore.error) { _, reason in
                if let reason { chat.operationError = reason; chat.attachmentStore.error = nil }
            }
            .onChange(of: reader.failure) { _, reason in
                if let reason { chat.operationError = reason }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await chat.refreshAvailability() } }
                else { chat.flush(); if phase == .background { voice.pause(); reader.stop() } }
            }
            .onChange(of: navigation.drawerOpen) { _, open in
                guard open else { return }
                navigation.addMenuOpen = false
                // The composer slides away with the surface; drop the keyboard.
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
                )
            }
            .onChange(of: chat.activeID) { _, _ in
                // Inspecting an output or opening the drawer does not hang up the call.
                // Changing conversations does, so speech cannot land in another chat.
                voice.pause()
            }
            .task {
                await chat.load()
                #if DEBUG
                DebugLaunchState.apply(chat: chat, voice: voice, navigation: navigation)
                #endif
            }
            .environment(reader)
            .environment(chat)
            .environment(voice)
            .environment(navigation)
    }
}

/// The sidebar push-reveal: the drawer is a still back layer and the
/// whole chat surface translates right to reveal it. `progress` (0...1) drives
/// offset, corner radius, and shadow together, so open/close animate as one
/// motion and a horizontal drag can scrub it interactively.
private struct DrawerReveal: View {
    @Environment(NavigationState.self) private var navigation
    @Environment(\.colorScheme) private var colorScheme

    @State private var progress: CGFloat = 0
    @State private var dragStart: CGFloat?

    private static let maxWidth: CGFloat = pt(280)
    private static let widthShare: CGFloat = 0.72
    private static let surfaceRadius: CGFloat = pt(30)
    private static let edgeGrab: CGFloat = pt(24)

    var body: some View {
        GeometryReader { proxy in
            let drawerWidth = min(Self.maxWidth, proxy.size.width * Self.widthShare)
            let open = navigation.drawerOpen

            ZStack(alignment: .topLeading) {
                // What shows around the pushed chat surface belongs to the drawer.
                Tokens.drawerBackground.ignoresSafeArea()

                ChatDrawer()
                    .frame(width: drawerWidth)
                    .frame(maxHeight: .infinity)
                    .ignoresSafeArea(.keyboard)
                    .allowsHitTesting(open)
                    // Hidden when closed, and when search covers everything.
                    .accessibilityHidden(!open || navigation.searchOpen)

                surface(open: open, drawerWidth: drawerWidth)
                    .highPriorityGesture(dragGesture(drawerWidth: drawerWidth), including: open ? .all : .subviews)
                    .simultaneousGesture(edgeGesture(drawerWidth: drawerWidth))
            }
            .onChange(of: open, initial: true) { _, isOpen in
                withAnimation(Tokens.Motion.drawer) { progress = isOpen ? 1 : 0 }
            }
        }
    }

    private func surface(open: Bool, drawerWidth: CGFloat) -> some View {
        let shape = surfaceShape
        return ChatScreen()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { Tokens.background.ignoresSafeArea() }
            .accessibilityHidden(open || navigation.searchOpen)
            .overlay {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { navigation.closeDrawer() }
                    .allowsHitTesting(open)
                    .accessibilityElement()
                    .accessibilityLabel(Text("Close navigation"))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { navigation.closeDrawer() }
                    .accessibilityHidden(!open)
            }
            // Mask through the safe areas: a plain clip stops at the safe-area
            // frame and cuts off the edge blurs, leaving bare bands.
            .mask { shape.ignoresSafeArea() }
            .background {
                shape
                    .fill(Tokens.background)
                    .shadow(color: .black.opacity(shadowOpacity * progress), radius: 16, x: -4, y: 0)
                    .ignoresSafeArea()
            }
            .offset(x: drawerWidth * progress)
    }

    private var surfaceShape: UnevenRoundedRectangle {
        let radius = Self.surfaceRadius * progress
        return UnevenRoundedRectangle(
            topLeadingRadius: radius,
            bottomLeadingRadius: radius,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    /// A soft lift, not a drop: just enough to separate the surface from the drawer.
    private var shadowOpacity: Double { colorScheme == .dark ? 0.16 : 0.06 }

    /// Drag the open surface left to close it.
    private func dragGesture(drawerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                guard navigation.drawerOpen else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if dragStart == nil { dragStart = progress }
                let base = dragStart ?? 1
                progress = min(1, max(0, base + value.translation.width / drawerWidth))
            }
            .onEnded { value in
                guard dragStart != nil else { return }
                dragStart = nil
                settle(value: value, drawerWidth: drawerWidth)
            }
    }

    /// Drag in from the left edge to open it.
    private func edgeGesture(drawerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                guard !navigation.drawerOpen else { return }
                guard value.startLocation.x < Self.edgeGrab else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if dragStart == nil { dragStart = progress }
                progress = min(1, max(0, value.translation.width / drawerWidth))
            }
            .onEnded { value in
                guard dragStart != nil else { return }
                dragStart = nil
                settle(value: value, drawerWidth: drawerWidth)
            }
    }

    private func settle(value: DragGesture.Value, drawerWidth: CGFloat) {
        let projected = progress + value.predictedEndTranslation.width / drawerWidth * 0.3
        let shouldOpen = projected > 0.5
        if shouldOpen == navigation.drawerOpen {
            withAnimation(Tokens.Motion.drawer) { progress = shouldOpen ? 1 : 0 }
        } else {
            navigation.drawerOpen = shouldOpen
        }
    }
}
