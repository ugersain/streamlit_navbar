import Foundation
import SwiftUI

/// Walks through today's workout: set, rest, set, rest ... finished.
@MainActor
final class WorkoutFlow: ObservableObject {
    enum Phase { case ready, set, rest, finished }

    @Published private(set) var phase: Phase = .ready
    @Published private(set) var exerciseIndex = 0
    @Published private(set) var setIndex = 0
    @Published var weight: Double = 0
    @Published var reps: Int = 0
    @Published private(set) var restEnd = Date()
    @Published private(set) var restTotal: TimeInterval = 90
    @Published private(set) var startedAt: Date?
    @Published private(set) var finishedAt: Date?

    let session = WorkoutSessionManager()
    private var store: AppStore?
    private var dayID: UUID?

    func bind(_ store: AppStore) {
        self.store = store
        dayID = store.todaysWorkout?.id
    }

    var day: WorkoutDay? { store?.snapshot.plan.first { $0.id == dayID } }
    var exercise: Exercise? {
        guard let day, day.exercises.indices.contains(exerciseIndex) else { return nil }
        return day.exercises[exerciseIndex]
    }

    var setsDone: Int {
        day?.exercises.flatMap(\.sets).filter(\.isDoneToday).count ?? 0
    }
    var setsTotal: Int { day?.exercises.flatMap(\.sets).count ?? 0 }
    var volumeKg: Double {
        day?.exercises.flatMap(\.sets).filter(\.isDoneToday).reduce(0) { $0 + $1.weightKg * Double($1.reps) } ?? 0
    }
    var elapsed: TimeInterval {
        guard let startedAt else { return 0 }
        return (finishedAt ?? Date()).timeIntervalSince(startedAt)
    }

    /// Which exercises are complete, for the progress bar.
    var exerciseProgress: [Bool] {
        day?.exercises.map { $0.sets.allSatisfy(\.isDoneToday) } ?? []
    }

    // MARK: Actions

    func start() {
        startedAt = Date()
        if let next = firstUndone(fromExercise: 0, set: 0) {
            go(to: next)
            phase = .set
            Task { await session.start() }
        } else {
            finish()
        }
    }

    func completeSet() {
        guard let day, let exercise, exercise.sets.indices.contains(setIndex) else { return }
        store?.setSet(day: day.id, exercise: exercise.id, set: exercise.sets[setIndex].id,
                      weightKg: weight, reps: reps, done: true)
        guard let next = firstUndone(fromExercise: exerciseIndex, set: setIndex + 1) else {
            finish()
            return
        }
        restTotal = TimeInterval(exercise.restSeconds)
        restEnd = Date().addingTimeInterval(restTotal)
        go(to: next)
        phase = .rest
    }

    func skipExercise() {
        if let next = firstUndone(fromExercise: exerciseIndex + 1, set: 0) {
            go(to: next)
            phase = .set
        } else {
            finish()
        }
    }

    func endRest() { if phase == .rest { phase = .set } }

    func extendRest(by seconds: TimeInterval = 15) {
        restEnd = restEnd.addingTimeInterval(seconds)
        restTotal += seconds
    }

    func finish() {
        finishedAt = Date()
        phase = .finished
        Task { await session.end() }
    }

    // MARK: Helpers

    private func go(to position: (Int, Int)) {
        exerciseIndex = position.0
        setIndex = position.1
        if let set = exercise?.sets[safe: setIndex] {
            weight = set.weightKg
            reps = set.reps
        }
    }

    /// First set not yet done, scanning forward from the given position.
    private func firstUndone(fromExercise e: Int, set s: Int) -> (Int, Int)? {
        guard let day else { return nil }
        for ei in day.exercises.indices where ei >= e {
            let startSet = ei == e ? s : 0
            for si in day.exercises[ei].sets.indices where si >= startSet {
                if !day.exercises[ei].sets[si].isDoneToday { return (ei, si) }
            }
        }
        return nil
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
