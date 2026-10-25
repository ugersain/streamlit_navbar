import Foundation
import HealthKit

/// Reads today's active energy from Apple Health. Falls back gracefully if access is denied.
@MainActor
final class HealthReader: ObservableObject {
    @Published private(set) var activeCalories: Double = 0
    @Published private(set) var isAuthorized = false

    let store = HKHealthStore()

    static var readTypes: Set<HKObjectType> {
        [HKQuantityType(.activeEnergyBurned), HKQuantityType(.heartRate), HKObjectType.workoutType()]
    }
    static var shareTypes: Set<HKSampleType> { [HKObjectType.workoutType()] }

    func requestAccess() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
            isAuthorized = true
            await refresh()
        } catch {
            isAuthorized = false
        }
    }

    func refresh() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let value: Double = await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: HKQuantityType(.activeEnergyBurned),
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, _ in
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0)
            }
            store.execute(query)
        }
        activeCalories = value
    }
}
