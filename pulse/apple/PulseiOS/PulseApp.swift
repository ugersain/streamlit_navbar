import SwiftUI

@main
struct PulseApp: App {
    @StateObject private var store: AppStore
    @StateObject private var cloud: CloudAccount
    @StateObject private var health = HealthReader()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = AppStore()
        _store = StateObject(wrappedValue: store)
        _cloud = StateObject(wrappedValue: CloudAccount(store: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(health)
                .environmentObject(cloud)
                .preferredColorScheme(.dark)
                .tint(Pulse.fuel)
                .task { await bootstrap() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await cloud.pull() } }
                }
        }
    }

    @MainActor
    private func bootstrap() async {
        store.onChange = { [cloud] snapshot in
            Connectivity.shared.send(snapshot)
            Task { @MainActor in cloud.schedulePush() }
        }
        Connectivity.shared.onSnapshot = { [store] remote in
            Task { @MainActor in store.merge(remote: remote) }
        }
        Notifier.shared.setup()
        Notifier.shared.onAction = { [store] action, id in
            Task { @MainActor in
                guard let reminder = store.snapshot.reminders.first(where: { $0.id == id }) else { return }
                if action == Notifier.ActionID.snooze { store.snooze(reminder) } else { store.complete(reminder) }
            }
        }
        await cloud.pull()
        if store.profile.onboarded {
            await health.refresh()
            Connectivity.shared.send(store.snapshot)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        if store.profile.onboarded {
            MainTabs()
        } else {
            OnboardingFlow()
        }
    }
}

struct MainTabs: View {
    @EnvironmentObject private var store: AppStore
    @State private var tab = 0
    @State private var assistantOpen = false

    var body: some View {
        ZStack {
            TabView(selection: $tab) {
                TodayView(openAssistant: { assistantOpen = true }).tag(0)
                    .tabItem { Label("Today", systemImage: "circle.circle") }
                FoodView().tag(1)
                    .tabItem { Label("Food", systemImage: "fork.knife") }
                TrainView().tag(2)
                    .tabItem { Label("Train", systemImage: "dumbbell.fill") }
                RoutineView().tag(3)
                    .tabItem { Label("Routine", systemImage: "calendar") }
            }
            .tint(Pulse.text)

            if !assistantOpen {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button { assistantOpen = true } label: {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 24, weight: .bold)).foregroundColor(.black)
                                .frame(width: 60, height: 60)
                                .background(Pulse.fuel, in: Circle())
                                .shadow(color: Pulse.fuel.opacity(0.4), radius: 14, y: 6)
                        }
                        .accessibilityLabel("Ask Pulse")
                        .padding(.trailing, 20).padding(.bottom, 64)
                    }
                }
            }

            if assistantOpen {
                AssistantOverlay(isPresented: $assistantOpen)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: assistantOpen)
        .onChange(of: store.snapshot.reminders) { _, reminders in
            Notifier.shared.scheduleDaily(reminders, quietStart: store.profile.quietStart, quietEnd: store.profile.quietEnd)
        }
    }
}
