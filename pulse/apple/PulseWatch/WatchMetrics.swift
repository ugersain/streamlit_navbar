import SwiftUI

/// Apple Watch screens run from 162 pt wide (40 mm, SE) to 208 pt wide (46 mm / Ultra 49 mm).
/// Graphics scale from a 198 pt (45 mm) baseline, text uses Dynamic Type styles, and every
/// screen scrolls, so nothing is clipped on small watches or with large text.
struct WatchMetrics: Equatable {
    var width: CGFloat = 198

    var scale: CGFloat { min(max(width / 198, 0.8), 1.12) }
    var isCompact: Bool { width < 180 }

    func s(_ value: CGFloat) -> CGFloat { value * scale }

    /// For large numerals only. Body text should use Dynamic Type styles instead.
    func numeral(_ size: CGFloat) -> Font {
        .system(size: size * scale, weight: .heavy, design: .rounded)
    }
}

private struct WatchMetricsKey: EnvironmentKey {
    static let defaultValue = WatchMetrics()
}

extension EnvironmentValues {
    var metrics: WatchMetrics {
        get { self[WatchMetricsKey.self] }
        set { self[WatchMetricsKey.self] = newValue }
    }
}

/// Measures the real screen width once at the root and shares it with every view below.
struct WatchScaled<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            content()
                .environment(\.metrics, WatchMetrics(width: proxy.size.width))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
    }
}

/// Shared look for cards on the Watch.
struct WatchCard<Content: View>: View {
    @Environment(\.metrics) private var m
    var tint: Color = Pulse.surface
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, m.s(10))
            .padding(.vertical, m.s(8))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint, in: RoundedRectangle(cornerRadius: m.s(16), style: .continuous))
    }
}

struct WatchPrimaryButtonStyle: ButtonStyle {
    var color: Color
    var foreground: Color = .black
    @Environment(\.metrics) private var m

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.heavy))
            .foregroundColor(foreground)
            .frame(maxWidth: .infinity, minHeight: max(m.s(42), 40))
            .background(color.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
    }
}
