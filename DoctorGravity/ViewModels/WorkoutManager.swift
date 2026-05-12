import Foundation
import SwiftData
import SwiftUI
import Observation

/// Single source of truth for workout session state and snapshot invariants
/// (per CLAUDE.md Architecture Rule #2). Owns: session instantiation, snapshot
/// progression, active execution state machine, and first-run edit write-through.
@Observable
@MainActor
final class WorkoutManager {
    private let modelContext: ModelContext

    // MARK: - Execution state (Phase 4)

    enum ExecutionState {
        case idle
        case exercise(SessionExercise)
        case rest(secondsRemaining: Int)
        case complete
    }

    private(set) var state: ExecutionState = .idle
    private(set) var activeSession: WorkoutSession?
    private(set) var timedRemaining: Int = 0

    /// (set index, exercise-within-set index). Only meaningful while
    /// `activeSession != nil`.
    private var currentSetIndex: Int = 0
    private var currentExerciseIndex: Int = 0
    private var countdownTask: Task<Void, Never>?

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

    // MARK: - Execution lifecycle (Phase 4)

    /// Enter execution mode for `session`. Resumes at the first un-logged
    /// `SessionExercise`, or transitions straight to `.complete` if all are
    /// already logged. Cancels any prior countdown.
    func beginExecution(_ session: WorkoutSession) {
        cancelCountdown()
        activeSession = session

        for (setIdx, set) in session.orderedSets.enumerated() {
            for (exIdx, ex) in set.orderedExercises.enumerated() where !ex.isComplete {
                currentSetIndex = setIdx
                currentExerciseIndex = exIdx
                enterExerciseState(ex)
                return
            }
        }
        state = .complete
    }

    /// Tear down execution state without finishing the session. The session row
    /// remains in SwiftData in its current (possibly partial) state so it can be
    /// resumed later via `beginExecution(_:)`.
    func pauseExecution() {
        cancelCountdown()
        state = .idle
        activeSession = nil
    }

    /// Force-flush the model context. Call from `scenePhase → .background` so
    /// in-progress session state survives an app kill (PRD §7).
    func flush() {
        try? modelContext.save()
    }

    // MARK: - Targets

    /// Resolve the current target for a session exercise by joining
    /// `session.snapshot → ExerciseTarget` (PRD §5.3).
    func target(for sessionExercise: SessionExercise) -> ExerciseTarget? {
        guard let snapshot = activeSession?.snapshot,
              let exercise = sessionExercise.workoutExercise else { return nil }
        return snapshot.target(for: exercise)
    }

    // MARK: - Progress reporting

    var totalSetCount: Int { activeSession?.orderedSets.count ?? 0 }
    var totalExerciseCount: Int {
        activeSession?.orderedSets.reduce(0) { $0 + $1.exercises.count } ?? 0
    }
    var currentSetNumber: Int { currentSetIndex + 1 }
    var currentExerciseNumberInSet: Int { currentExerciseIndex + 1 }
    var currentSetExerciseCount: Int {
        activeSession?.orderedSets[safe: currentSetIndex]?.orderedExercises.count ?? 0
    }

    /// True if `state == .exercise` and the current exercise has its actual
    /// value logged (or is timed — in which case the timer logs on completion).
    var canAdvance: Bool {
        switch state {
        case .exercise(let sessionExercise):
            guard let exercise = sessionExercise.workoutExercise else { return false }
            if exercise.isTimed { return true }
            return sessionExercise.actualReps != nil
        case .rest, .complete:
            return true
        case .idle:
            return false
        }
    }

    // MARK: - State transitions

    /// Advance the state machine. For `.exercise`: validate that reps are logged
    /// (rep-based) and either move to the next exercise in the same set, enter
    /// rest after a completed set, or finish the session. For `.rest`: enter the
    /// first exercise of the next set. Saves on every transition (PRD §7).
    func advance() throws {
        switch state {
        case .exercise(let sessionExercise):
            try commitExerciseLog(sessionExercise)
            try advanceFromExercise()
        case .rest:
            try advanceFromRest()
        case .idle, .complete:
            return
        }
    }

    /// Skip the rest countdown immediately and enter the next set's first exercise.
    func skipRest() throws {
        guard case .rest = state else { return }
        try advanceFromRest()
    }

    /// Stop a timed exercise early, logging the actual elapsed seconds.
    func stopTimedExerciseEarly() throws {
        guard case .exercise(let sessionExercise) = state,
              let exercise = sessionExercise.workoutExercise, exercise.isTimed else { return }

        let target = self.target(for: sessionExercise)?.targetDurationSeconds ?? 0
        let elapsed = max(0, target - timedRemaining)
        sessionExercise.actualDurationSeconds = elapsed
        try advanceFromExercise()
    }

    private func enterExerciseState(_ sessionExercise: SessionExercise) {
        cancelCountdown()
        state = .exercise(sessionExercise)

        guard let exercise = sessionExercise.workoutExercise, exercise.isTimed else {
            timedRemaining = 0
            return
        }
        let duration = target(for: sessionExercise)?.targetDurationSeconds ?? 0
        timedRemaining = duration
        startTimedCountdown(from: duration, sessionExercise: sessionExercise)
    }

    private func commitExerciseLog(_ sessionExercise: SessionExercise) throws {
        guard let exercise = sessionExercise.workoutExercise else { return }
        if !exercise.isTimed {
            guard sessionExercise.actualReps != nil else {
                throw WorkoutManagerError.repsNotLogged
            }
        }
        try modelContext.save()
    }

    private func advanceFromExercise() throws {
        guard let session = activeSession else { return }
        let orderedSets = session.orderedSets
        let currentSetExercises = orderedSets[currentSetIndex].orderedExercises

        if currentExerciseIndex + 1 < currentSetExercises.count {
            currentExerciseIndex += 1
            enterExerciseState(currentSetExercises[currentExerciseIndex])
            try modelContext.save()
        } else if currentSetIndex + 1 < orderedSets.count {
            startRestCountdown(seconds: restSeconds(forSessionSetIndex: currentSetIndex))
            try modelContext.save()
        } else {
            try finish()
        }
    }

    /// `SessionSet` stores only structure; rest duration is owned by the
    /// template's `WorkoutSet`. Join by matching `order`.
    private func restSeconds(forSessionSetIndex index: Int) -> Int {
        guard let session = activeSession,
              let sessionSet = session.orderedSets[safe: index],
              let templateSet = session.template?.orderedSets.first(where: { $0.order == sessionSet.order })
        else { return 60 }
        return templateSet.restSeconds
    }

    private func advanceFromRest() throws {
        cancelCountdown()
        guard let session = activeSession else { return }
        currentSetIndex += 1
        currentExerciseIndex = 0

        let orderedSets = session.orderedSets
        if currentSetIndex < orderedSets.count {
            let firstExercise = orderedSets[currentSetIndex].orderedExercises[0]
            enterExerciseState(firstExercise)
            try modelContext.save()
        } else {
            try finish()
        }
    }

    private func finish() throws {
        guard let session = activeSession else { return }
        cancelCountdown()
        session.completedAt = .now
        session.isCompleted = true
        if let template = session.template, !template.hasBeenCompleted {
            template.hasBeenCompleted = true
        }
        try modelContext.save()
        state = .complete
    }

    // MARK: - Countdown tasks

    private func startRestCountdown(seconds: Int) {
        cancelCountdown()
        state = .rest(secondsRemaining: seconds)

        countdownTask = Task { @MainActor [weak self] in
            var remaining = seconds
            while remaining > 0 {
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
                remaining -= 1
                guard let self else { return }
                self.state = .rest(secondsRemaining: remaining)
            }
            try? self?.advanceFromRest()
        }
    }

    private func startTimedCountdown(from seconds: Int, sessionExercise: SessionExercise) {
        cancelCountdown()

        countdownTask = Task { @MainActor [weak self] in
            var remaining = seconds
            while remaining > 0 {
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
                remaining -= 1
                guard let self else { return }
                self.timedRemaining = remaining
            }
            guard let self else { return }
            sessionExercise.actualDurationSeconds = seconds
            try? self.advanceFromExercise()
        }
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
    }

    // MARK: - First-run edits (PRD §5.3.1)

    /// True while the user is still authoring the canonical plan — the very
    /// first session against this template. Edits in this state write through
    /// to `WorkoutExercise` / `ExerciseTarget`. Once the first session
    /// completes, this returns false and edits must be session-local only.
    var isFirstRunInProgress: Bool {
        guard let template = activeSession?.template else { return false }
        return !template.hasBeenCompleted
    }

    /// Rename the underlying `WorkoutExercise`. First-run only.
    func renameExercise(_ sessionExercise: SessionExercise, to newName: String) throws {
        guard isFirstRunInProgress else { return }
        guard let exercise = sessionExercise.workoutExercise else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        exercise.name = trimmed
        try modelContext.save()
    }

    /// Adjust the target for a rep-based exercise. First-run only — writes
    /// through to the active `ExerciseTarget`.
    func updateTargetReps(_ reps: Int, for sessionExercise: SessionExercise) throws {
        guard isFirstRunInProgress,
              let exercise = sessionExercise.workoutExercise, !exercise.isTimed,
              let target = target(for: sessionExercise) else { return }
        target.targetReps = max(1, reps)
        try modelContext.save()
    }

    /// Adjust the target for a timed exercise. First-run only — writes through
    /// to the active `ExerciseTarget`. If the current state is `.exercise` for
    /// this same session-exercise, restart the countdown from the new value.
    func updateTargetDuration(_ seconds: Int, for sessionExercise: SessionExercise) throws {
        guard isFirstRunInProgress,
              let exercise = sessionExercise.workoutExercise, exercise.isTimed,
              let target = target(for: sessionExercise) else { return }
        let clamped = max(1, seconds)
        target.targetDurationSeconds = clamped
        try modelContext.save()

        if case .exercise(let current) = state, current.id == sessionExercise.id {
            timedRemaining = clamped
            startTimedCountdown(from: clamped, sessionExercise: sessionExercise)
        }
    }
}

// MARK: - Safe subscript helper

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Errors

enum WorkoutManagerError: Error, LocalizedError {
    case noActiveSnapshot(templateTitle: String)
    case detachedSnapshot
    case cannotDiscardActiveSnapshot
    case invariantViolated(String)
    case repsNotLogged

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
        case .repsNotLogged:
            return "Log your reps before advancing."
        }
    }
}

// MARK: - Environment injection

private struct WorkoutManagerKey: EnvironmentKey {
    static var defaultValue: WorkoutManager? { nil }
}

extension EnvironmentValues {
    var workoutManager: WorkoutManager? {
        get { self[WorkoutManagerKey.self] }
        set { self[WorkoutManagerKey.self] = newValue }
    }
}
