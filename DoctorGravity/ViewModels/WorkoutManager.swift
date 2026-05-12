import Foundation
import SwiftData
import SwiftUI
import Observation

/// Single source of truth for workout session state and snapshot invariants
/// (per CLAUDE.md Architecture Rule #2). Phase 3 surface: snapshot management
/// + session instantiation. Phase 4 will add active-session state and the
/// first-run edit write-through logic.
@Observable
@MainActor
final class WorkoutManager {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Sessions (PRD §5.2)

    /// Instantiate a new `WorkoutSession` from the template's active snapshot,
    /// mirroring the template's set/exercise structure into `SessionSet`/
    /// `SessionExercise` rows. Saves atomically (PRD §7 "Atomic saves").
    @discardableResult
    func startSession(for template: WorkoutTemplate) throws -> WorkoutSession {
        guard let snapshot = template.activeSnapshot else {
            throw WorkoutManagerError.noActiveSnapshot(templateTitle: template.title)
        }

        let session = WorkoutSession(
            startedAt: .now,
            template: template,
            snapshot: snapshot
        )

        for templateSet in template.orderedSets {
            let sessionSet = SessionSet(order: templateSet.order)
            sessionSet.session = session
            session.sets.append(sessionSet)

            for exercise in templateSet.orderedExercises {
                let sessionExercise = SessionExercise(workoutExercise: exercise)
                sessionExercise.set = sessionSet
                sessionSet.exercises.append(sessionExercise)
            }
        }

        modelContext.insert(session)
        try modelContext.save()
        return session
    }

    func discardSession(_ session: WorkoutSession) throws {
        modelContext.delete(session)
        try modelContext.save()
    }

    // MARK: - Progression / snapshots (PRD §6)

    /// Create a new snapshot by deep-copying the active snapshot's targets,
    /// then atomically swap `isActive` from the previous to the new snapshot.
    /// Invariant: exactly one snapshot per template has `isActive == true`.
    @discardableResult
    func createProgression(for template: WorkoutTemplate) throws -> WorkoutSnapshot {
        guard let previous = template.activeSnapshot else {
            throw WorkoutManagerError.noActiveSnapshot(templateTitle: template.title)
        }

        let next = WorkoutSnapshot(isActive: false)
        next.template = template

        for previousTarget in previous.targets {
            let copy = ExerciseTarget(
                targetReps: previousTarget.targetReps,
                targetDurationSeconds: previousTarget.targetDurationSeconds,
                workoutExercise: previousTarget.workoutExercise
            )
            copy.snapshot = next
            next.targets.append(copy)
        }

        modelContext.insert(next)
        try modelContext.save()
        return next
    }

    /// Activate `snapshot` for its template, deactivating any other active
    /// snapshot. Use after the user confirms a progression edit.
    func activate(_ snapshot: WorkoutSnapshot) throws {
        guard let template = snapshot.template else {
            throw WorkoutManagerError.detachedSnapshot
        }

        for existing in template.snapshots where existing.id != snapshot.id {
            existing.isActive = false
        }
        snapshot.isActive = true

        try modelContext.save()
        try assertSingleActive(for: template)
    }

    /// Roll back a previously-created progression that the user cancelled out of.
    func discardProgression(_ snapshot: WorkoutSnapshot) throws {
        // Only safe to delete if it never became active.
        if snapshot.isActive {
            throw WorkoutManagerError.cannotDiscardActiveSnapshot
        }
        modelContext.delete(snapshot)
        try modelContext.save()
    }

    // MARK: - Invariant check

    /// Defensive runtime check on the one-active-snapshot invariant. Throws if
    /// violated so callers can surface the error rather than silently corrupting
    /// future sessions.
    func assertSingleActive(for template: WorkoutTemplate) throws {
        let activeCount = template.snapshots.filter(\.isActive).count
        guard activeCount == 1 else {
            throw WorkoutManagerError.invariantViolated(
                "Template \(template.title) has \(activeCount) active snapshots; expected 1"
            )
        }
    }
}

// MARK: - Errors

enum WorkoutManagerError: Error, LocalizedError {
    case noActiveSnapshot(templateTitle: String)
    case detachedSnapshot
    case cannotDiscardActiveSnapshot
    case invariantViolated(String)

    var errorDescription: String? {
        switch self {
        case .noActiveSnapshot(let title):
            return "No active snapshot for template '\(title)'."
        case .detachedSnapshot:
            return "Snapshot has no associated template."
        case .cannotDiscardActiveSnapshot:
            return "Can't discard a snapshot that's currently active."
        case .invariantViolated(let message):
            return "Snapshot invariant violated: \(message)"
        }
    }
}

// MARK: - Environment injection

private struct WorkoutManagerKey: EnvironmentKey {
    @MainActor static let defaultValue: WorkoutManager? = nil
}

extension EnvironmentValues {
    var workoutManager: WorkoutManager? {
        get { self[WorkoutManagerKey.self] }
        set { self[WorkoutManagerKey.self] = newValue }
    }
}
