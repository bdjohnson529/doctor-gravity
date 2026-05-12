import SwiftUI
import SwiftData

/// Displays a completed session with targets (from `session.snapshot`) and
/// actuals (from `SessionExercise`) shown side by side, per exercise (PRD §5.4).
struct HistoryDetailView: View {
    let session: WorkoutSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summary
                exercises
            }
            .padding()
        }
        .navigationTitle(session.template?.title ?? "Workout")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Summary

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let completedAt = session.completedAt {
                HStack {
                    Image(systemName: "calendar")
                    Text(completedAt.formatted(date: .complete, time: .shortened))
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 20) {
                metric(label: "Sets", value: "\(session.orderedSets.count)")
                metric(label: "Total reps", value: "\(session.totalActualReps)")
                if let duration = sessionDuration {
                    metric(label: "Duration", value: duration)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
        }
    }

    private var sessionDuration: String? {
        guard let completedAt = session.completedAt else { return nil }
        let interval = completedAt.timeIntervalSince(session.startedAt)
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        if minutes == 0 { return "\(seconds)s" }
        return "\(minutes)m \(seconds)s"
    }

    // MARK: - Exercise breakdown

    private var exercises: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(session.orderedSets) { sessionSet in
                SessionSetCard(sessionSet: sessionSet, session: session)
            }
        }
    }
}

// MARK: - Set card

private struct SessionSetCard: View {
    let sessionSet: SessionSet
    let session: WorkoutSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Set \(sessionSet.order + 1)")
                .font(.headline)

            ForEach(sessionSet.orderedExercises) { sessionExercise in
                if let exercise = sessionExercise.workoutExercise {
                    HistoryExerciseRow(
                        exercise: exercise,
                        sessionExercise: sessionExercise,
                        target: target(for: exercise)
                    )
                    if sessionExercise.id != sessionSet.orderedExercises.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
    }

    private func target(for exercise: WorkoutExercise) -> ExerciseTarget? {
        session.snapshot?.target(for: exercise)
    }
}

// MARK: - Row

private struct HistoryExerciseRow: View {
    let exercise: WorkoutExercise
    let sessionExercise: SessionExercise
    let target: ExerciseTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(exercise.name)
                .font(.body.weight(.semibold))

            HStack(spacing: 16) {
                column(title: "Target", value: targetLabel, foreground: .secondary)
                column(title: "Actual", value: actualLabel, foreground: actualForeground)
                Spacer()
                if exercise.isTimed == false {
                    deltaBadge
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func column(title: String, value: String, foreground: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospacedDigit())
                .foregroundStyle(foreground)
        }
    }

    private var targetLabel: String {
        guard let target else { return "—" }
        if exercise.isTimed, let s = target.targetDurationSeconds { return "\(s)s" }
        if let r = target.targetReps { return "\(r) reps" }
        return "—"
    }

    private var actualLabel: String {
        if exercise.isTimed, let s = sessionExercise.actualDurationSeconds { return "\(s)s" }
        if let r = sessionExercise.actualReps { return "\(r) reps" }
        return "—"
    }

    private var delta: Int? {
        guard !exercise.isTimed,
              let actual = sessionExercise.actualReps,
              let target = target?.targetReps else { return nil }
        return actual - target
    }

    private var actualForeground: Color {
        guard let delta else { return .primary }
        if delta >= 0 { return .green }
        return .orange
    }

    @ViewBuilder
    private var deltaBadge: some View {
        if let delta {
            Text(delta >= 0 ? "+\(delta)" : "\(delta)")
                .font(.caption.weight(.bold).monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    (delta >= 0 ? Color.green : Color.orange).opacity(0.15),
                    in: .capsule
                )
                .foregroundStyle(delta >= 0 ? .green : .orange)
        }
    }
}
