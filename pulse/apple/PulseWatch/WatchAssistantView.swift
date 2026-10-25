import SwiftUI
import WatchKit

/// Wrapper so the view model can be created with the shared store.
struct WatchAssistantView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Content(store: store)
    }

    private struct Content: View {
        @StateObject private var model: AssistantViewModel
        @Environment(\.metrics) private var m

        init(store: AppStore) {
            _model = StateObject(wrappedValue: AssistantViewModel(store: store))
        }

        var body: some View {
            ScrollView {
                VStack(spacing: m.s(8)) {
                    switch model.phase {
                    case .idle: idle
                    case .thinking: thinking
                    case .answered: answered
                    case .failed: failed
                    }
                }
                .padding(.horizontal, m.s(4))
            }
            .navigationTitle("Ask Pulse")
            .navigationBarTitleDisplayMode(.inline)
        }

        // MARK: States

        private var idle: some View {
            VStack(spacing: m.s(10)) {
                PulseOrb(size: m.s(66)).padding(.vertical, m.s(8))
                Text("Say what you ate, or ask a question")
                    .font(.footnote).foregroundColor(Pulse.muted).multilineTextAlignment(.center)
                speakButton("Speak")
            }
        }

        private var thinking: some View {
            VStack(spacing: m.s(8)) {
                PulseOrb(size: m.s(60)).padding(.vertical, m.s(8))
                Text("“\(model.heard)”")
                    .font(.footnote.weight(.semibold)).multilineTextAlignment(.center)
                    .lineLimit(4).minimumScaleFactor(0.8)
                ProgressView().tint(Pulse.fuel)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Thinking about: \(model.heard)")
        }

        private var answered: some View {
            VStack(alignment: .leading, spacing: m.s(8)) {
                HStack(spacing: 8) {
                    PulseOrb(size: m.s(24))
                    Text("Pulse").font(.system(.footnote, design: .rounded).weight(.heavy))
                    Spacer()
                }
                if let reply = model.reply {
                    WatchCard {
                        Text(reply.reply).font(.footnote.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if model.hasMealToConfirm {
                    ForEach(model.pendingMeals, id: \.self) { item in
                        WatchCard(tint: item.confident ? Pulse.surface : Pulse.surfaceRaised) {
                            HStack {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(item.name.capitalized).font(.footnote.weight(.semibold)).lineLimit(1)
                                    Text(quantityText(item)).font(.caption2).foregroundColor(Pulse.muted)
                                }
                                Spacer(minLength: 4)
                                if item.confident {
                                    Text("\(item.calories)").font(.footnote.weight(.heavy)).foregroundColor(Pulse.fuel)
                                } else {
                                    Text("check").font(.caption2.weight(.bold)).foregroundColor(Pulse.power)
                                }
                            }
                        }
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text("Total").font(.caption2).foregroundColor(Pulse.muted)
                        Spacer()
                        Text("\(model.pendingTotalCalories) kcal").font(.footnote.weight(.heavy))
                    }
                    Button("Save") {
                        model.confirmMeals()
                        WKInterfaceDevice.current().play(.success)
                    }
                    .buttonStyle(WatchPrimaryButtonStyle(color: Pulse.fuel))
                    Button("Dismiss") { model.dismiss() }.buttonStyle(.bordered)
                } else {
                    speakButton("Ask again")
                }
            }
        }

        private var failed: some View {
            VStack(spacing: m.s(8)) {
                Image(systemName: "exclamationmark.triangle.fill").font(.title2).foregroundColor(Pulse.power)
                Text("Couldn't understand that").font(.footnote.weight(.semibold))
                speakButton("Try again")
            }
        }

        // MARK: Pieces

        /// System dictation sheet. SFSpeechRecognizer is not available on watchOS.
        private func speakButton(_ title: String) -> some View {
            TextFieldLink(title, prompt: Text("What did you eat?")) { text in
                Task { await model.submit(text) }
            }
            .tint(Pulse.fuel)
        }

        private func quantityText(_ item: FoodEstimate) -> String {
            let q = item.quantity.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(item.quantity))" : String(item.quantity)
            return "\(q) \(item.unit)"
        }
    }
}
