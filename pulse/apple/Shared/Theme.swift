import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// One color per job, on every device. Matches the design canvas.
enum Pulse {
    static let fuel = Color(hex: 0xFF8A4C)      // calories, food
    static let power = Color(hex: 0xC8F25A)     // protein, training
    static let move = Color(hex: 0x3DD6C6)      // activity, rest
    static let routine = Color(hex: 0x8E9BFF)   // habits, calendar

    static let background = Color(hex: 0x0B0D10)
    static let surface = Color(hex: 0x14181D)
    static let surfaceRaised = Color(hex: 0x1C2128)
    static let text = Color(hex: 0xF3F5F7)
    static let muted = Color(hex: 0x9AA4AF)

    static let brandGradient = [fuel, power, move, routine, fuel]
}

/// Concentric progress rings: calories (outer), protein (middle), move (inner).
struct ActivityRings: View {
    var calories: Double
    var protein: Double
    var move: Double
    var size: CGFloat = 84

    var body: some View {
        let line = size * 0.085
        ZStack {
            ring(progress: calories, color: Pulse.fuel, diameter: size, line: line)
            ring(progress: protein, color: Pulse.power, diameter: size * 0.74, line: line)
            ring(progress: move, color: Pulse.move, diameter: size * 0.48, line: line)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calories \(Int(calories * 100)) percent, protein \(Int(protein * 100)) percent, move \(Int(move * 100)) percent")
    }

    private func ring(progress: Double, color: Color, diameter: CGFloat, line: CGFloat) -> some View {
        ZStack {
            Circle().stroke(color.opacity(0.2), lineWidth: line)
            Circle()
                .trim(from: 0, to: min(max(progress, 0.001), 1))
                .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }
}

/// The assistant's animated orb. Swirling brand colors, a soft glow and a slow "breath".
struct PulseOrb: View {
    var size: CGFloat = 60
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false
    @State private var breathe = false

    var body: some View {
        ZStack {
            AngularGradient(colors: Pulse.brandGradient, center: .center)
                .frame(width: size, height: size)
                .clipShape(Circle())
                .blur(radius: size * 0.28)
                .opacity(0.65)
                .scaleEffect(1.5)
                .rotationEffect(.degrees(spin ? 360 : 0))

            Circle()
                .fill(Color.black)
                .overlay(
                    AngularGradient(colors: Pulse.brandGradient.reversed(), center: .center)
                        .scaleEffect(1.6)
                        .blur(radius: size * 0.16)
                        .rotationEffect(.degrees(spin ? -360 : 0))
                )
                .clipShape(Circle())

            Circle().fill(
                RadialGradient(
                    colors: [.white.opacity(0.75), .clear],
                    center: UnitPoint(x: 0.32, y: 0.25),
                    startRadius: 0,
                    endRadius: size * 0.5
                )
            )
        }
        .frame(width: size, height: size)
        .scaleEffect(breathe ? 1.06 : 0.94)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}

/// Colored bars that bounce while the assistant listens.
struct WaveformBars: View {
    var height: CGFloat = 24
    var barWidth: CGFloat = 4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var active = false
    private let colors = [Pulse.fuel, Pulse.power, Pulse.move, Pulse.routine, Pulse.move, Pulse.power, Pulse.fuel]

    var body: some View {
        HStack(spacing: barWidth) {
            ForEach(colors.indices, id: \.self) { index in
                Capsule()
                    .fill(colors[index])
                    .frame(width: barWidth, height: height)
                    .scaleEffect(y: active ? 1 : 0.3)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever().delay(Double(index) * 0.12),
                        value: active
                    )
            }
        }
        .accessibilityHidden(true)
        .onAppear { active = true }
    }
}
