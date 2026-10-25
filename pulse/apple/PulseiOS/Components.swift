import SwiftUI

struct Card<Content: View>: View {
    var tint: Color = Pulse.surface
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct PrimaryButton: View {
    var title: String
    var color: Color = Pulse.fuel
    var foreground: Color = .black
    var isEnabled = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .foregroundColor(foreground)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(color.opacity(isEnabled ? 1 : 0.35), in: Capsule())
        }
        .disabled(!isEnabled)
    }
}

struct Chip: View {
    var title: String
    var selected: Bool
    var color: Color = Pulse.fuel
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(selected ? .heavy : .semibold))
                .foregroundColor(Pulse.text)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(selected ? color.opacity(0.22) : Pulse.surface, in: Capsule())
                .overlay(Capsule().stroke(selected ? color : Pulse.surfaceRaised, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Wrapping row of chips.
struct ChipFlow<Item: Hashable>: View {
    var items: [Item]
    var label: (Item) -> String
    var isSelected: (Item) -> Bool
    var color: Color = Pulse.fuel
    var toggle: (Item) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Chip(title: label(item), selected: isSelected(item), color: color) { toggle(item) }
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(in: proposal.width ?? 320, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(in: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(in width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}

struct ScreenHeader: View {
    var eyebrow: String?
    var title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let eyebrow {
                Text(eyebrow).font(.footnote.weight(.semibold)).foregroundColor(Pulse.muted)
            }
            Text(title).font(.system(.largeTitle, design: .rounded).weight(.heavy))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    func screenBackground() -> some View {
        background(Pulse.background.ignoresSafeArea())
    }
}
