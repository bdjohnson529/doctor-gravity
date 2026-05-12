import SwiftUI
import SwiftData

/// Displays the current exercise. For rep-based: shows target reps and a stepper
/// bound to `SessionExercise.actualReps`. For timed: shows a countdown that
/// auto-advances on completion (via WorkoutManager.startTimedCountdown), with a
/// Stop Early button that logs partial time. First-run sessions also expose an
/// Edit button to rename or adjust the target (writes through to template).
struct ExerciseStepView: View {
    let manager: WorkoutManager
    @Bindable var sessionExercise: SessionExercise
    let onAdvance: () -> Void
    let onStopTimed: () -> Void

    @State private var isEditing = false

    private var exercise: WorkoutExercise? { sessionExercise.workoutExercise }
    private var target: ExerciseTarget? { manager.target(for: sessionExercise) }

    var body: some View {
        VStack(spacing: 24) {
            progressHeader
            Spacer()
            exerciseCard
            Spacer()
            logSection
            advanceButton
        }
        .padding()
        .sheet(isPresented: $isEditing) {
            if let exercise {
                FirstRunEditSheet(
                    manager: manager,
                    sessionExercise: sessionExercise,
                    exercise: exercise
                )
            }
        }
    }

    // MARK: - Header

    private var progressHeader: some View {
        VStack(spacing: 4) {
            Text("Set \(manager.currentSetNumber) of \(manager.totalSetCount)")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Exercise \(manager.currentExerciseNumberInSet) of \(manager.currentSetExerciseCount)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Card

    private var exerciseCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text(exercise?.name ?? "Exercise")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                if manager.isFirstRunInProgress {
                    Button {
                        isEditing = true
                    } label: {
                        Image(systemName: "pencil.circle")
                            .font(.title2)
                    }
                    .accessibilityLabel("Edit exercise")
                }
            }

            if let notes = exercise?.notes, !notes.isEmpty {
                Text(notes)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
    }

    // MARK: - Logging

    @ViewBuilder
    private var logSection: some View {
        if let exercise {
            if exercise.isTimed {
                timedDisplay
            } else {
                repsStepper
            }
        }
    }

    private var timedDisplay: some View {
        VStack(spacing: 8) {
            Text("\(manager.timedRemaining)s")
                .font(.system(size: 72, weight: .heavy, design: .rounded).monospacedDigit())
                .contentTransition(.numericText(countsDown: true))
            Text("Target: \(target?.targetDurationSeconds ?? 0)s")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var repsStepper: some View {
        VStack(spacing: 8) {
            Text("Target: \(target?.targetReps ?? 0) reps")
                .font(.callout)
                .foregroundStyle(.secondary)

            Stepper(
                value: Binding(
                    get: { sessionExercise.actualReps ?? 0 },
                    set: { sessionExercise.actualReps = $0 }
                ),
                in: 0...200
            ) {
                HStack {
                    Text("Logged:")
                    Spacer()
                    Text("\(sessionExercise.actualReps ?? 0)")
                        .font(.title.monospacedDigit())
                        .contentTransition(.numericText())
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
        }
    }

    // MARK: - Advance

    @ViewBuilder
    private var advanceButton: some View {
        if exercise?.isTimed == true {
            Button(role: .destructive) {
                onStopTimed()
            } label: {
                Label("Stop Early", systemImage: "stop.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        } else {
            Button {
                onAdvance()
            } label: {
                Label("Next", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!manager.canAdvance)
        }
    }
}
