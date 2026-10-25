import SwiftUI
import WatchKit

struct WorkoutView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var flow = WorkoutFlow()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch flow.phase {
            case .ready: ReadyView(flow: flow)
            case .set: SetView(flow: flow)
            case .rest: RestView(flow: flow)
            case .finished: SummaryView(flow: flow) { dismiss() }
            }
        }
        .navigationBarBackButtonHidden(flow.phase == .set || flow.phase == .rest)
        .onAppear { flow.bind(store) }
    }
}

// MARK: - Ready

private struct ReadyView: View {
    @ObservedObject var flow: WorkoutFlow
    @Environment(\.metrics) private var m

    var body: some View {
        ScrollView {
            VStack(spacing: m.s(10)) {
                if let day = flow.day {
                    Text(day.title)
                        .font(.system(.title3, design: .rounded).weight(.heavy))
                    Text("\(day.exercises.count) exercises · \(flow.setsTotal) sets")
                        .font(.footnote).foregroundColor(Pulse.muted)
                    ForEach(day.exercises) { exercise in
                        WatchCard {
                            HStack {
                                Text(exercise.name).font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                                Spacer(minLength: 4)
                                Text("\(exercise.sets.count)×\(exercise.sets.first?.reps ?? 0)")
                                    .font(.caption2).foregroundColor(Pulse.muted)
                            }
                        }
                    }
                    Button(flow.setsDone > 0 ? "Resume" : "Start") { flow.start() }
                        .buttonStyle(WatchPrimaryButtonStyle(color: Pulse.power))
                } else {
                    Image(systemName: "bed.double.fill").font(.largeTitle).foregroundColor(Pulse.move)
                    Text("Rest day").font(.system(.title3, design: .rounded).weight(.heavy))
                    Text("Recovery is part of the plan.").font(.footnote).foregroundColor(Pulse.muted)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, m.s(4))
        }
        .navigationTitle("Workout")
    }
}

// MARK: - Set

private struct SetView: View {
    @ObservedObject var flow: WorkoutFlow
    @ObservedObject private var session: WorkoutSessionManager
    @Environment(\.metrics) private var m

    init(flow: WorkoutFlow) {
        self.flow = flow
        _session = ObservedObject(wrappedValue: flow.session)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: m.s(6)) {
                progress
                Text(flow.exercise?.name ?? "")
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text("Set \(flow.setIndex + 1) of \(flow.exercise?.sets.count ?? 0)" + restText)
                    .font(.caption2).foregroundColor(Pulse.muted)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(weightText).font(m.numeral(34)).minimumScaleFactor(0.6).lineLimit(1)
                    Text("kg").font(.caption).foregroundColor(Pulse.muted)
                    Text("×").font(.title3).foregroundColor(Pulse.muted)
                    Text("\(flow.reps)").font(m.numeral(34)).foregroundColor(Pulse.power).lineLimit(1)
                }
                .focusable()
                .digitalCrownRotation($flow.weight, from: 0, through: 400, by: 2.5,
                                      sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(weightText) kilograms, \(flow.reps) reps")
                .accessibilityHint("Turn the Digital Crown to change weight")

                HStack(spacing: m.s(6)) {
                    stepButton("minus", label: "Fewer reps") { flow.reps = max(0, flow.reps - 1) }
                    Label("Crown: weight", systemImage: "digitalcrown.horizontal.arrow.clockwise")
                        .labelStyle(.titleOnly)
                        .font(.system(size: 10)).foregroundColor(Pulse.muted)
                        .frame(maxWidth: .infinity)
                    stepButton("plus", label: "More reps") { flow.reps += 1 }
                }

                HStack(spacing: m.s(6)) {
                    Button { flow.skipExercise() } label: {
                        Image(systemName: "forward.end.fill")
                            .frame(minWidth: 32, minHeight: max(m.s(42), 40))
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Skip exercise")
                    Button("Done set") {
                        WKInterfaceDevice.current().play(.success)
                        flow.completeSet()
                    }
                    .buttonStyle(WatchPrimaryButtonStyle(color: Pulse.power))
                }
            }
            .padding(.horizontal, m.s(4))
        }
        .navigationTitle {
            Text(session.heartRate > 0 ? "♥ \(Int(session.heartRate))" : (flow.day?.title ?? "Workout"))
        }
    }

    private var weightText: String {
        flow.weight.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(flow.weight))" : String(format: "%.1f", flow.weight)
    }
    private var restText: String {
        (flow.exercise?.restSeconds).map { " · rest \($0)s" } ?? ""
    }

    private var progress: some View {
        HStack(spacing: 3) {
            ForEach(Array(flow.exerciseProgress.enumerated()), id: \.offset) { index, done in
                Capsule()
                    .fill(done ? Pulse.power : (index == flow.exerciseIndex ? Pulse.power.opacity(0.45) : Pulse.surfaceRaised))
                    .frame(height: 4)
            }
        }
        .accessibilityHidden(true)
    }

    private func stepButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 14, weight: .heavy))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(label)
    }
}

// MARK: - Rest

private struct RestView: View {
    @ObservedObject var flow: WorkoutFlow
    @Environment(\.metrics) private var m

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let remaining = max(0, flow.restEnd.timeIntervalSince(context.date))
            ScrollView {
                VStack(spacing: m.s(8)) {
                    ZStack {
                        Circle().stroke(Pulse.move.opacity(0.2), lineWidth: m.s(9))
                        Circle()
                            .trim(from: 0, to: flow.restTotal > 0 ? remaining / flow.restTotal : 0)
                            .stroke(Pulse.move, style: StrokeStyle(lineWidth: m.s(9), lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text(clock(remaining)).font(m.numeral(32)).monospacedDigit()
                            Text("rest").font(.caption2).foregroundColor(Pulse.muted)
                        }
                    }
                    .frame(width: m.s(112), height: m.s(112))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Rest, \(Int(remaining)) seconds left")

                    if let exercise = flow.exercise {
                        Text("Next · set \(flow.setIndex + 1) · \(Int(flow.weight)) kg × \(flow.reps)")
                            .font(.caption2).foregroundColor(Pulse.muted).multilineTextAlignment(.center)
                        Text(exercise.name).font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    HStack(spacing: m.s(6)) {
                        Button("+15s") { flow.extendRest() }.buttonStyle(.bordered)
                        Button("Skip") { flow.endRest() }
                            .buttonStyle(WatchPrimaryButtonStyle(color: Pulse.move))
                    }
                }
                .padding(.horizontal, m.s(4))
            }
            .onChange(of: remaining <= 0) { _, finished in
                if finished {
                    WKInterfaceDevice.current().play(.notification)
                    flow.endRest()
                }
            }
        }
        .navigationTitle("Rest")
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Summary

private struct SummaryView: View {
    @ObservedObject var flow: WorkoutFlow
    var close: () -> Void
    @Environment(\.metrics) private var m

    var body: some View {
        ScrollView {
            VStack(spacing: m.s(8)) {
                Image(systemName: "checkmark.seal.fill").font(.largeTitle).foregroundColor(Pulse.power)
                Text("Workout done").font(.system(.title3, design: .rounded).weight(.heavy))
                WatchCard {
                    VStack(alignment: .leading, spacing: 2) {
                        row("Sets", "\(flow.setsDone)/\(flow.setsTotal)")
                        row("Volume", "\(Int(flow.volumeKg)) kg")
                        row("Time", "\(Int(flow.elapsed / 60)) min")
                    }
                }
                Text("Saved to Apple Health").font(.caption2).foregroundColor(Pulse.muted)
                Button("Close", action: close).buttonStyle(WatchPrimaryButtonStyle(color: Pulse.power))
            }
            .padding(.horizontal, m.s(4))
        }
        .onAppear { WKInterfaceDevice.current().play(.success) }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.footnote).foregroundColor(Pulse.muted)
            Spacer()
            Text(value).font(.footnote.weight(.bold))
        }
    }
}
