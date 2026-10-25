import SwiftUI

#if DEBUG
/// Open this file in Xcode's canvas to check the layouts on every Watch size.
private let previewDevices = [
    "Apple Watch SE (40mm) (2nd generation)",
    "Apple Watch Series 9 (41mm)",
    "Apple Watch Series 9 (45mm)",
    "Apple Watch Ultra 2 (49mm)",
]

struct WatchSizes_Previews: PreviewProvider {
    static var previews: some View {
        ForEach(previewDevices, id: \.self) { name in
            Group {
                screen { WatchHomeView() }
                screen { WatchAssistantView() }
                screen { WorkoutView() }
            }
            .previewDevice(PreviewDevice(rawValue: name))
            .previewDisplayName(name)
        }
    }

    private static func screen<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        WatchScaled { NavigationStack { content() } }
            .environmentObject(AppStore(fileName: "preview.json"))
            .environmentObject(HealthReader())
    }
}
#endif
