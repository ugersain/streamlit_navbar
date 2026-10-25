import SwiftUI

/// Siri-style popup: dimmed screen, glowing edge, and a compact pill with the orb,
/// live text and waveform. After you speak it turns into a small answer card.
struct AssistantOverlay: View {
    @EnvironmentObject private var store: AppStore
    @Binding var isPresented: Bool

    var body: some View {
        Content(store: store, isPresented: $isPresented)
    }

    private struct Content: View {
        @StateObject private var model: AssistantViewModel
        @StateObject private var speech = SpeechRecognizer()
        @Binding var isPresented: Bool
        @State private var glow = false
        @State private var typed = ""
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        init(store: AppStore, isPresented: Binding<Bool>) {
            _model = StateObject(wrappedValue: AssistantViewModel(store: store))
            _isPresented = isPresented
        }

        var body: some View {
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                    .accessibilityHidden(true)

                edgeGlow

                VStack(spacing: 12) {
                    if model.phase == .answered || model.phase == .failed {
                        answerCard.transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    pill
                    Button("Cancel") { close() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Pulse.text)
                        .padding(.horizontal, 18).frame(minHeight: 44)
                        .background(.white.opacity(0.1), in: Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.phase)
            .task {
                speech.onFinished = { text in Task { await model.submit(text) } }
                await speech.start()
            }
            .onAppear {
                guard !reduceMotion else { glow = true; return }
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { glow = true }
            }
        }

        // MARK: Pieces

        private var edgeGlow: some View {
            RoundedRectangle(cornerRadius: 48, style: .continuous)
                .strokeBorder(AngularGradient(colors: Pulse.brandGradient, center: .center), lineWidth: 8)
                .blur(radius: 16)
                .opacity(glow ? 0.9 : 0.4)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }

        private var pill: some View {
            HStack(spacing: 14) {
                PulseOrb(size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusLabel)
                        .font(.caption2.weight(.heavy)).tracking(0.4).foregroundColor(Pulse.muted)
                    if speech.errorMessage != nil || (!speech.isListening && model.phase == .idle) {
                        TextField("Type instead", text: $typed)
                            .submitLabel(.send)
                            .onSubmit {
                                let text = typed
                                typed = ""
                                Task { await model.submit(text) }
                            }
                            .font(.callout.weight(.semibold))
                    } else {
                        Text(displayedText)
                            .font(.callout.weight(.semibold)).foregroundColor(Pulse.text)
                            .lineLimit(3)
                    }
                }
                Spacer(minLength: 0)
                if speech.isListening { WaveformBars(height: 28, barWidth: 3) }
            }
            .padding(14)
            .background(Pulse.surface.opacity(0.94), in: RoundedCornerShape(radius: 34))
            .overlay(RoundedCornerShape(radius: 34).stroke(.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(statusLabel). \(displayedText)")
        }

        private var answerCard: some View {
            VStack(alignment: .leading, spacing: 12) {
                if model.phase == .failed {
                    Text("Sorry, I couldn't do that. Try again.")
                        .font(.body.weight(.semibold))
                } else if let reply = model.reply {
                    Text("“\(model.heard)”").font(.footnote.italic()).foregroundColor(Pulse.muted)
                    Text(reply.reply).font(.body.weight(.semibold))
                    if model.hasMealToConfirm {
                        VStack(spacing: 6) {
                            ForEach(model.pendingMeals, id: \.self) { item in
                                HStack {
                                    Text("\(trim(item.quantity)) × \(item.name.capitalized)")
                                        .font(.subheadline.weight(.semibold))
                                    if !item.confident {
                                        Text("check").font(.caption.weight(.bold)).foregroundColor(Pulse.power)
                                    }
                                    Spacer()
                                    Text("\(item.calories)").font(.subheadline.weight(.heavy)).foregroundColor(Pulse.fuel)
                                }
                                .padding(.horizontal, 12).frame(minHeight: 44)
                                .background(Pulse.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                        Text("Estimated from a food database. Amounts vary with portion and preparation.")
                            .font(.caption2).foregroundColor(Pulse.muted)
                        HStack(spacing: 8) {
                            PrimaryButton(title: "Save to diary") {
                                model.confirmMeals()
                                close()
                            }
                            Button {
                                model.dismiss()
                                Task { await speech.start() }
                            } label: {
                                Image(systemName: "mic.fill").foregroundColor(Pulse.text)
                                    .frame(width: 56, height: 56)
                                    .background(Pulse.surfaceRaised, in: Circle())
                            }
                            .accessibilityLabel("Correct by voice")
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Pulse.surface.opacity(0.95), in: RoundedCornerShape(radius: 30))
            .overlay(RoundedCornerShape(radius: 30).stroke(.white.opacity(0.12), lineWidth: 1))
        }

        // MARK: State

        private var statusLabel: String {
            switch model.phase {
            case .thinking: return "THINKING"
            case .answered: return "PULSE"
            case .failed: return "TRY AGAIN"
            case .idle: return speech.isListening ? "LISTENING" : "ASK PULSE"
            }
        }

        private var displayedText: String {
            switch model.phase {
            case .thinking, .answered, .failed: return model.heard
            case .idle: return speech.transcript.isEmpty ? "Say what you ate, or ask anything…" : speech.transcript
            }
        }

        private func trim(_ value: Double) -> String {
            value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value))" : String(value)
        }

        private func close() {
            speech.stop()
            isPresented = false
        }
    }
}

/// Continuous rounded rectangle usable as both fill shape and stroke overlay.
struct RoundedCornerShape: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
    }
}
