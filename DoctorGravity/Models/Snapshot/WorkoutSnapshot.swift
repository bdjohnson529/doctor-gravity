import Foundation
import SwiftData

@Model
final class WorkoutSnapshot {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var isActive: Bool

    var template: WorkoutTemplate?

    @Relationship(deleteRule: .cascade, inverse: \ExerciseTarget.snapshot)
    var targets: [ExerciseTarget] = []

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        isActive: Bool = true
    ) {
        self.id = id
        self.createdAt = createdAt
        self.isActive = isActive
    }
}

extension WorkoutSnapshot {
    var templateId: UUID? { template?.id }

    func target(for exercise: WorkoutExercise) -> ExerciseTarget? {
        targets.first { $0.workoutExercise?.id == exercise.id }
    }
}
