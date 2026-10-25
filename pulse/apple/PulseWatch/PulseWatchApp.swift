import SwiftUI
import WatchKit

@main
struct PulseWatchApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var health = HealthReader()

    var body: some Scene {
        WindowGroup {
            WatchScaled {
                NavigationStack { WatchHomeView() }
            }
            .environmentObject(store)
            .environmentObject(health)
            .task { await bootstrap() }
        }
    }

    @MainActor
    private func bootstrap() async {
        // Sync with the iPhone.
        store.onChange = { Connectivity.shared.send($0) }
        Connectivity.shared.onSnapshot = { [store] remote in
            Task { @MainActor in store.merge(remote: remote) }
        }

        // Reminder actions (Done / Snooze) tapped on this Watch.
        // Daily reminders are scheduled by the iPhone and mirrored here.
        Notifier.shared.setup()
        Notifier.shared.onAction = { [store] action, id in
            Task { @MainActor in
                guard let reminder = store.snapshot.reminders.first(where: { $0.id == id }) else { return }
                if action == Notifier.ActionID.snooze { store.snooze(reminder) } else { store.complete(reminder) }
            }
        }
        _ = await Notifier.shared.requestAuthorization()
        await health.requestAccess()
    }
}
