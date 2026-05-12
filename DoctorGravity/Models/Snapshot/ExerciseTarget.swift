import Foundation
import SwiftData

@Model
final class ExerciseTarget {
    @Attribute(.unique) var id: UUID
    var targetReps: Int?
    var targetDurationSeconds: Int?

    var snapshot: WorkoutSnapshot?

    @Relationship(deleteRule: .nullify)
    var workoutExercise: WorkoutExercise?

    init(
        id: UUID = UUID(),
        targetReps: Int? = nil,
        targetDurationSeconds: Int? = nil,
        workoutExercise: WorkoutExercise? = nil
    ) {
        self.id = id
        self.targetReps = targetReps
        self.targetDurationSeconds = targetDurationSeconds
        self.workoutExercise = workoutExercise
    }
}

extension ExerciseTarget {
    var snapshotId: UUID? { snapshot?.id }
    var workoutExerciseId: UUID? { workoutExercise?.id }

    /// True when exactly one of `targetReps` / `targetDurationSeconds` is non-nil
    /// and matches the parent `WorkoutExercise.isTimed`. Enforced by JSONParser
    /// on decode; also useful for runtime defensive checks.
    var isValid: Bool {
        guard let exercise = workoutExercise else { return false }
        if exercise.isTimed {
            return targetReps == nil && targetDurationSeconds != nil
        } else {
            return targetReps != nil && targetDurationSeconds == nil
        }
    }
}
