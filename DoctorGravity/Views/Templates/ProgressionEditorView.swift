import SwiftUI
import SwiftData

/// Modal sheet for editing the targets on a freshly-created (inactive) snapshot.
/// On Confirm: activates the new snapshot via WorkoutManager. On Cancel: deletes
/// the draft. Per PRD §6, exactly one snapshot per template stays active at a time.
struct ProgressionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.workoutManager) private var workoutManager

    let template: WorkoutTemplate
    @Bindable var draftSnapshot: WorkoutSnapshot

    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Adjust targets for the next progression. Past sessions keep their original snapshot.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(template.orderedSets) { set in
                    Section("Set \(set.order + 1)") {
                        ForEach(set.orderedExercises) { exercise in
                            if let target = draftSnapshot.target(for: exercise) {
                                TargetEditorRow(exercise: exercise, target: target)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Increase Progression")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") { confirm() }
                        .fontWeight(.semibold)
                }
            }
            .alert(
                "Something went wrong",
                isPresented: .init(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                ),
                presenting: errorMessage
            ) { _ in
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { message in
                Text(message)
            }
        }
        .interactiveDismissDisabled(true)
    }

    // MARK: - Actions

    private func confirm() {
        guard let manager = workoutManager else {
            errorMessage = "Workout manager not available."
            return
        }
        do {
            try manager.activate(draftSnapshot)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancel() {
        guard let manager = workoutManager else {
            dismiss(); return
        }
        do {
            try manager.discardProgression(draftSnapshot)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Target editor row

private struct TargetEditorRow: View {
    let exercise: WorkoutExercise
    @Bindable var target: ExerciseTarget

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(exercise.name)
                .font(.body.weight(.semibold))

            if exercise.isTimed {
                Stepper(
                    value: durationBinding,
                    in: 5...600,
                    step: 5
                ) {
                    Text("\(target.targetDurationSeconds ?? 0) seconds")
                        .monospacedDigit()
                }
            } else {
                Stepper(
                    value: repsBinding,
                    in: 1...100
                ) {
                    Text("\(target.targetReps ?? 0) reps")
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var repsBinding: Binding<Int> {
        Binding(
            get: { target.targetReps ?? 0 },
            set: { target.targetReps = $0 }
        )
    }

    private var durationBinding: Binding<Int> {
        Binding(
            get: { target.targetDurationSeconds ?? 0 },
            set: { target.targetDurationSeconds = $0 }
        )
    }
}
