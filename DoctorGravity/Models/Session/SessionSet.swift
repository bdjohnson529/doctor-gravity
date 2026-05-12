import Foundation
import SwiftData

@Model
final class SessionSet {
    @Attribute(.unique) var id: UUID
    var order: Int

    var session: WorkoutSession?

    @Relationship(deleteRule: .cascade, inverse: \SessionExercise.set)
    var exercises: [SessionExercise] = []

    init(
        id: UUID = UUID(),
        order: Int
    ) {
        self.id = id
        self.order = order
    }
}

extension SessionSet {
    var orderedExercises: [SessionExercise] {
        exercises.sorted { ($0.workoutExercise?.order ?? 0) < ($1.workoutExercise?.order ?? 0) }
    }
}
