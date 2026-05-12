import Foundation
import SwiftData

@Model
final class WorkoutSet {
    @Attribute(.unique) var id: UUID
    var order: Int
    var restSeconds: Int

    var template: WorkoutTemplate?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.set)
    var exercises: [WorkoutExercise] = []

    init(
        id: UUID = UUID(),
        order: Int,
        restSeconds: Int = 60
    ) {
        self.id = id
        self.order = order
        self.restSeconds = restSeconds
    }
}

extension WorkoutSet {
    var orderedExercises: [WorkoutExercise] {
        exercises.sorted { $0.order < $1.order }
    }
}
