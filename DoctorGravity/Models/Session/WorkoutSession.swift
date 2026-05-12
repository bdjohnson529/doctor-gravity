import Foundation
import SwiftData

@Model
final class WorkoutSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var completedAt: Date?
    var isCompleted: Bool

    var template: WorkoutTemplate?

    @Relationship(deleteRule: .nullify)
    var snapshot: WorkoutSnapshot?

    @Relationship(deleteRule: .cascade, inverse: \SessionSet.session)
    var sets: [SessionSet] = []

    init(
        id: UUID = UUID(),
        startedAt: Date = .now,
        completedAt: Date? = nil,
        isCompleted: Bool = false,
        template: WorkoutTemplate? = nil,
        snapshot: WorkoutSnapshot? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.isCompleted = isCompleted
        self.template = template
        self.snapshot = snapshot
    }
}

extension WorkoutSession {
    var templateId: UUID? { template?.id }
    var snapshotId: UUID? { snapshot?.id }

    var orderedSets: [SessionSet] {
        sets.sorted { $0.order < $1.order }
    }

    var totalActualReps: Int {
        sets.reduce(0) { acc, set in
            acc + set.exercises.reduce(0) { $0 + ($1.actualReps ?? 0) }
        }
    }
}
