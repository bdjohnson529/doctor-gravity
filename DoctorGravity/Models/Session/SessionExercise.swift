import Foundation
import SwiftData

@Model
final class SessionExercise {
    @Attribute(.unique) var id: UUID
    var actualReps: Int?
    var actualDurationSeconds: Int?

    var set: SessionSet?

    @Relationship(deleteRule: .nullify)
    var workoutExercise: WorkoutExercise?

    init(
        id: UUID = UUID(),
        actualReps: Int? = nil,
        actualDurationSeconds: Int? = nil,
        workoutExercise: WorkoutExercise? = nil
    ) {
        self.id = id
        self.actualReps = actualReps
        self.actualDurationSeconds = actualDurationSeconds
        self.workoutExercise = workoutExercise
    }
}

extension SessionExercise {
    var workoutExerciseId: UUID? { workoutExercise?.id }

    var isComplete: Bool {
        guard let exercise = workoutExercise else { return false }
        return exercise.isTimed ? actualDurationSeconds != nil : actualReps != nil
    }
}
