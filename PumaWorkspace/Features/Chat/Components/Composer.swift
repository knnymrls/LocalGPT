import SwiftUI

/// The glass composer. One card, one control row, three modes:
/// text (field above the row), dictation (waveform in the row, words landing in
/// the field), and voice (the card collapses to the row and two glass circles
/// split off beside it). The `+` button and the row keep their identity across
/// modes, so switching is a single morph rather than a view swap.
struct Composer: View {
    @Environment(ChatSessionStore.self) private var chat
    @Environment(VoiceSessionController.self) private var voice
    @Environment(NavigationState.self) private var navigation

    @Namespace private var glass
    @FocusState private var focused: Bool
    @State private var lightTaps = 0
    @State private var mediumTaps = 0

    private static let buttonSize: CGFloat = Tokens.scaled(36)
    private static let glyphSize: CGFloat = 20
    private static let voiceGlyph: CGFloat = 24
    private static let voiceButtonSize: CGFloat = Tokens.scaled(48)
    private static let cardRadius: CGFloat = pt(24)
    private static let exitTint = Color(red: 18 / 255, green: 18 / 255, blue: 22 / 255, opacity: 0.78)
    private static let modeAnimation: Animation = .smooth(duration: 0.38)

    private enum PrimaryAction: CaseIterable { case send, stop, voice, confirm }

    private var primaryAction: PrimaryAction {
        if chat.isStreaming { return .stop }
        if voice.isDictating { return .confirm }
        return chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .voice : .send
    }

    var body: some View {
        VStack(spacing: pt(12)) {
            if let reason = voice.unavailableReason {
                statusHint(reason)
                    .transition(.opacity)
            }
            GlassEffectContainer(spacing: pt(9)) {
                HStack(alignment: .bottom, spacing: pt(9)) {
                    card
                    if voice.isActive {
                        voiceCluster
                    }
                }
            }
        }
        .animation(Self.modeAnimation, value: voice.isActive)
        .animation(Self.modeAnimation, value: voice.isDictating)
        .animation(.easeInOut(duration: 0.2), value: voice.unavailableReason)
        .sensoryFeedback(.impact(weight: .light), trigger: lightTaps)
        .sensoryFeedback(.impact(weight: .medium), trigger: mediumTaps)
    }

    // MARK: Card

    private var card: some View {
        let inset: CGFloat = voice.isActive ? pt(6) : pt(8)
        let shape = RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            if !voice.isActive, !chat.chatSources.isEmpty {
                SourceCards()
                    .padding(.bottom, pt(4))
                    .transition(.opacity)
            }
            if !voice.isActive {
                // The text sits 16pt from the card's left, right, and top edges
                // (the card's 8pt inset plus 8pt here), matching the plus glyph
                // below it. Under the text, 12pt plus the 8pt of clear space
                // inside the 36pt button frames gives 20pt to the glyphs.
                field
                    .padding(.horizontal, pt(8))
                    .padding(.top, pt(8))
                    .padding(.bottom, pt(12))
                    .transition(.opacity)
            }
            controls
        }
        .padding(inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(shape)
        .glassControl(in: shape)
        .glassEffectID("card", in: glass)
    }

    private var field: some View {
        @Bindable var chat = chat
        return TextField(
            "",
            text: $chat.draft,
            prompt: Text("Ask anything…").foregroundStyle(Tokens.foregroundSecondary),
            axis: .vertical
        )
        .font(.text)
        .foregroundStyle(Tokens.foreground)
        .tint(Tokens.foreground)
        .lineLimit(1...6)
        .focused($focused)
        .disabled(voice.isDictating)
        .accessibilityLabel(Text("Message"))
    }

    /// The one control row. Fixed height, so nothing in it moves when the
    /// field above grows or shrinks.
    private var controls: some View {
        HStack(spacing: pt(8)) {
            addButton

            Group {
                if voice.isActive {
                    voiceTranscript
                } else if voice.isDictating {
                    DictationBars()
                        .padding(.horizontal, pt(4))
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)

            if !voice.isActive {
                if !voice.isDictating {
                    modelLabel
                        .transition(.opacity)
                    micButton
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                primaryButton
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(height: Self.buttonSize)
    }

    /// Voice mode: the live transcript (the shared draft) and the keyboard
    /// handoff. Tapping either returns to typing without sending.
    private var voiceTranscript: some View {
        Text(chat.draft.isEmpty ? " " : chat.draft)
            .font(.text)
            .foregroundStyle(Tokens.foreground)
            .lineLimit(1)
            .truncationMode(.head)
            .padding(.trailing, pt(10))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                lightTaps += 1
                handoffToKeyboard()
            }
            .accessibilityLabel(Text(chat.draft.isEmpty ? "Use keyboard" : chat.draft))
            .accessibilityHint(Text("Switches to the keyboard"))
            .accessibilityAddTraits(.isButton)
    }

    // MARK: Controls

    /// The plus: opens the add surface, which `ChatScreen` draws over it.
    private var addButton: some View {
        Button {
            lightTaps += 1
            navigation.addMenuOpen.toggle()
        } label: {
            Icon(.add, size: Self.glyphSize)
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text("Add"))
    }

    /// Where the answer comes from. A plain label: with one on-device model
    /// there is nothing to choose, so there is nothing to open.
    private var modelLabel: some View {
        Text(chat.selectedModel?.shortName ?? "On-device")
            .font(.title)
            // Quiet until the model can actually answer.
            .foregroundStyle(chat.selectedModel?.availability == .ready ? Tokens.foreground : Tokens.foregroundMuted)
            .lineLimit(1)
            .padding(.horizontal, pt(6))
            .frame(height: Self.buttonSize)
            .accessibilityLabel(Text(chat.selectedModel?.availability.explanation ?? "Runs on this iPhone"))
            .onTapGesture { if let reason = chat.selectedModel?.availability.explanation { chat.operationError = reason } }
    }

    private var micButton: some View {
        Button {
            lightTaps += 1
            focused = false
            voice.startDictation()
        } label: {
            Icon(.microphone, size: Self.glyphSize)
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text("Dictate"))
    }

    /// One filled circle whose glyph crossfades in place. No layout is
    /// animated here, so emptying the field can never throw the button.
    private var primaryButton: some View {
        let action = primaryAction
        return Button {
            lightTaps += 1
            switch action {
            case .send: chat.send()
            case .stop: chat.stop()
            case .confirm: voice.stopDictation()
            case .voice:
                focused = false
                voice.start()
            }
        } label: {
            ZStack {
                Circle().fill(Tokens.foreground)
                ForEach(PrimaryAction.allCases, id: \.self) { candidate in
                    Icon(
                        Self.glyph(for: candidate), size: Self.glyphSize, color: Tokens.foregroundInverse,
                        // Stop is the solid square while a reply is running.
                        filled: candidate == .stop
                    )
                        .opacity(candidate == action ? 1 : 0)
                        .scaleEffect(candidate == action ? 1 : 0.6)
                }
            }
            .frame(width: Self.buttonSize, height: Self.buttonSize)
            .contentShape(Circle())
            .animation(.easeInOut(duration: 0.16), value: action)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text(Self.label(for: action)))
    }

    /// Mute and exit: two glass circles that split off the card.
    private var voiceCluster: some View {
        HStack(spacing: pt(9)) {
            Button {
                mediumTaps += 1
                voice.toggleMute()
            } label: {
                Icon(
                    voice.isMuted ? .microphoneSlash : .microphone,
                    size: Self.voiceGlyph,
                    color: voice.isMuted ? .white : Tokens.foreground
                )
                .frame(width: Self.voiceButtonSize, height: Self.voiceButtonSize)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassControl(in: Circle(), glass: muteGlass)
            .glassEffectID("mute", in: glass)
            .glassEffectTransition(.matchedGeometry)
            .animation(.easeInOut(duration: 0.2), value: voice.isMuted)
            .accessibilityLabel(Text(voice.unavailableReason != nil ? "Retry voice" : voice.isMuted ? "Unmute microphone" : "Mute microphone"))

            Button {
                lightTaps += 1
                voice.exit()
            } label: {
                Icon(.xmark, size: Self.voiceGlyph, color: .white)
                    .frame(width: Self.voiceButtonSize, height: Self.voiceButtonSize)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassControl(in: Circle(), glass: .regular.tint(Self.exitTint).interactive())
            .glassEffectID("exit", in: glass)
            .glassEffectTransition(.matchedGeometry)
            .accessibilityLabel(Text("Exit voice conversation"))
        }
    }

    private var muteGlass: Glass {
        voice.isMuted ? .regular.tint(Tokens.recording).interactive() : .regular.interactive()
    }

    private func statusHint(_ reason: String) -> some View {
        HStack(spacing: pt(6)) {
            Text(reason)
                .font(.caption)
                .foregroundStyle(Tokens.foregroundSecondary)
                .multilineTextAlignment(.center)
            Button {
                lightTaps += 1
                handoffToKeyboard()
            } label: {
                Icon(.keyboard, size: 20, color: Tokens.foregroundSecondary)
                    .frame(width: pt(32), height: pt(32))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(Text("Use keyboard"))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Actions

    /// Leaves voice mode with the transcript in the draft (never sends) and
    /// focuses the field once it is back in the hierarchy.
    private func handoffToKeyboard() {
        voice.handoffToKeyboard()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            focused = true
        }
    }

    private static func glyph(for action: PrimaryAction) -> NucleoIcon {
        switch action {
        case .send: .arrowUp
        case .stop: .stop
        case .voice: .waveform
        case .confirm: .done
        }
    }

    private static func label(for action: PrimaryAction) -> String {
        switch action {
        case .send: "Send message"
        case .stop: "Stop response"
        case .voice: "Start voice conversation"
        case .confirm: "Finish dictation"
        }
    }
}
