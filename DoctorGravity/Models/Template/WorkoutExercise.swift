import Foundation
import SwiftData

@Model
final class WorkoutExercise {
    @Attribute(.unique) var id: UUID
    var name: String
    var order: Int
    var isTimed: Bool
    var notes: String?

    var set: WorkoutSet?

    init(
        id: UUID = UUID(),
        name: String,
        order: Int,
        isTimed: Bool,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.order = order
        self.isTimed = isTimed
        self.notes = notes
    }
}
