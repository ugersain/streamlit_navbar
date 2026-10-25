import SwiftUI

/// A compact profile. Anything that needs typing (keys, passwords) is done on the iPhone.
struct WatchProfileView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.metrics) private var m

    private var initials: String { String((store.profile.name.isEmpty ? "?" : store.profile.name).prefix(2)).uppercased() }
    /// The iPhone shares the session token with the Watch. If it is here, the assistant can use the account's AI key.
    private var assistantOn: Bool { Keychain.get("pulse.token") != nil }

    var body: some View {
        ScrollView {
            VStack(spacing: m.s(8)) {
                Text(initials)
                    .font(.system(size: m.s(18), weight: .heavy, design: .rounded)).foregroundColor(Pulse.power)
                    .frame(width: m.s(52), height: m.s(52)).background(Pulse.surfaceRaised, in: Circle())
                    .overlay(Circle().stroke(Pulse.fuel.opacity(0.6), lineWidth: 3))
                Text(store.profile.name.isEmpty ? "Your profile" : store.profile.name)
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                row("Goal", "\(store.profile.calorieGoal) kcal", Pulse.fuel)
                row("Assistant", assistantOn ? "Account AI on" : "Built-in", assistantOn ? Pulse.move : Pulse.muted)
                row("Synced", store.snapshot.updatedAt == .distantPast ? "Not yet" : store.snapshot.updatedAt.formatted(.relative(presentation: .named)), Pulse.text)
                Text("Edit your profile and AI keys on iPhone")
                    .font(.caption2).foregroundColor(Pulse.muted).multilineTextAlignment(.center).padding(.top, 4)
            }
            .padding(.horizontal, m.s(4))
        }
        .navigationTitle("Profile")
    }

    private func row(_ title: String, _ value: String, _ color: Color) -> some View {
        WatchCard {
            HStack {
                Text(title).font(.caption2.weight(.semibold)).foregroundColor(Pulse.muted)
                Spacer(minLength: 4)
                Text(value).font(.caption.weight(.heavy)).foregroundColor(color).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }
}
