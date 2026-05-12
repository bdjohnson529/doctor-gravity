import Foundation
import SwiftData

@Model
final class WorkoutTemplate {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var hasBeenCompleted: Bool

    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.template)
    var sets: [WorkoutSet] = []

    @Relationship(deleteRule: .cascade, inverse: \WorkoutSnapshot.template)
    var snapshots: [WorkoutSnapshot] = []

    @Relationship(deleteRule: .cascade, inverse: \WorkoutSession.template)
    var sessions: [WorkoutSession] = []

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        hasBeenCompleted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.hasBeenCompleted = hasBeenCompleted
    }
}

extension WorkoutTemplate {
    var orderedSets: [WorkoutSet] {
        sets.sorted { $0.order < $1.order }
    }

    var activeSnapshot: WorkoutSnapshot? {
        snapshots.first { $0.isActive }
    }
}
