import SwiftUI

/// The chat surface: background, voice aura, feed, top bar, and composer.
///
/// The composer rides in the feed's bottom safe-area inset, so the feed's
/// bottom content inset always equals the composer's measured height plus
/// spacing, and the keyboard moves both together.
struct ChatScreen: View {
    @Environment(ChatSessionStore.self) private var chat
    @Environment(VoiceSessionController.self) private var voice
    @Environment(NavigationState.self) private var navigation

    var body: some View {
        ZStack {
            Tokens.background.ignoresSafeArea()

            if voice.isActive, voice.unavailableReason == nil {
                VoiceAura()
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.42)),
                        removal: .opacity.animation(.easeIn(duration: 0.3))
                    ))
            }

            ChatFeed()
                .safeAreaInset(edge: .top, spacing: 0) {
                    // Top bar row (40 + 8) below the safe top; the bar itself overlays.
                    Color.clear.frame(height: TopBar.barHeight + TopBar.bottomPadding)
                }
                .safeAreaInset(edge: .bottom, spacing: pt(12)) { bottomBar }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                TopBar()
                if SpeechReader.shared.speakingID != nil {
                    ReadAloudBar()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let notice = navigation.notice {
                    NoticeBar(text: notice)
                        .padding(.top, SpeechReader.shared.speakingID != nil ? pt(8) : 0)
                        .transition(.scale(scale: 0.92, anchor: .top).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.25), value: SpeechReader.shared.speakingID)
            .animation(.spring(duration: 0.32, bounce: 0.2), value: navigation.notice)
        }
        // The add surface: a tap anywhere else closes it.
        .overlay {
            if navigation.addMenuOpen {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { navigation.addMenuOpen = false }
                    .accessibilityLabel(Text("Close menu"))
                    .accessibilityAddTraits(.isButton)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if navigation.addMenuOpen {
                AddSurface {
                    navigation.addMenuOpen = false
                    navigation.filesPickerOpen = true
                } onClose: {
                    navigation.addMenuOpen = false
                }
                // Scales up out of the plus button, and back into it.
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.08, anchor: AddSurface.plusAnchor).combined(with: .opacity),
                    removal: .scale(scale: 0.2, anchor: AddSurface.plusAnchor).combined(with: .opacity)
                ))
            }
        }
        .animation(
            navigation.addMenuOpen ? .spring(duration: 0.32, bounce: 0.3) : .snappy(duration: 0.22),
            value: navigation.addMenuOpen
        )
        .sourceFileImporter(
            isPresented: Binding(get: { navigation.filesPickerOpen }, set: { navigation.filesPickerOpen = $0 }),
            chat: chat
        )
        .onChange(of: voice.isActive) { _, active in
            if active { navigation.addMenuOpen = false }
        }
    }

    private var showSuggestions: Bool {
        chat.isEmpty && !voice.isActive && chat.chatSources.isEmpty
            && chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showSuggestions {
                SuggestionList()
                    .padding(.horizontal, pt(16))
                    .padding(.bottom, pt(12))
                    .transition(.opacity.animation(Tokens.Motion.crossfade))
            }
            Composer()
                .padding(.horizontal, pt(16))
                .overlay(alignment: .top) {
                    // Transcript bottom sits 96pt above the composer's top edge.
                    FloatingTranscript()
                        .alignmentGuide(.top) { $0[.bottom] + 96 }
                }
        }
        .padding(.top, pt(8))
        .padding(.bottom, pt(8))
        // Jump to the latest message: a small glass chevron just above the
        // composer, shown whenever the feed is scrolled away from the end.
        .overlay(alignment: .top) {
            if !navigation.feedAtLatest, !chat.isEmpty, !voice.isActive {
                GlassCircleButton(
                    icon: .chevronDown, size: Tokens.scaled(34), iconSize: 16, accessibilityLabel: "Jump to latest"
                ) {
                    navigation.jumpToLatest += 1
                }
                .offset(y: -Tokens.scaled(34))
                .transition(.glass(scale: 0.85, anchor: .bottom))
            }
        }
        .animation(.easeOut(duration: 0.2), value: navigation.feedAtLatest)
        .background(alignment: .bottom) {
            // In voice mode the aura owns the bottom edge; the blur's page
            // wash would paint over it, so it steps aside.
            ProgressiveBlur(edge: .bottom)
                .padding(.top, -pt(28))
                .ignoresSafeArea(edges: .bottom)
                .opacity(voice.isActive ? 0 : 1)
                .animation(.easeInOut(duration: 0.3), value: voice.isActive)
        }
    }
}
