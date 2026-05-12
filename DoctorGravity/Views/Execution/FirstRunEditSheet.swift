import SwiftUI
import SwiftData

/// First-run-only edit sheet (PRD §5.3.1). Lets the user rename the exercise
/// and adjust its target. Changes write through to `WorkoutExercise.name` and
/// the active `ExerciseTarget` via `WorkoutManager`. After the first session
/// completes, this sheet is never shown.
struct FirstRunEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let manager: WorkoutManager
    let sessionExercise: SessionExercise
    let exercise: WorkoutExercise

    @State private var name: String = ""
    @State private var reps: Int = 0
    @State private var seconds: Int = 0
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                }

                Section("Target") {
                    if exercise.isTimed {
                        Stepper(value: $seconds, in: 5...600, step: 5) {
                            HStack {
                                Text("Duration")
                                Spacer()
                                Text("\(seconds)s")
                                    .monospacedDigit()
                            }
                        }
                    } else {
                        Stepper(value: $reps, in: 1...100) {
                            HStack {
                                Text("Reps")
                                Spacer()
                                Text("\(reps)")
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                Section {
                    Text("First-run edits update the template and active snapshot. Once you complete this session, future edits stay session-local.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert(
                "Couldn't save",
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
        .onAppear(perform: hydrate)
    }

    private func hydrate() {
        name = exercise.name
        reps = manager.target(for: sessionExercise)?.targetReps ?? 0
        seconds = manager.target(for: sessionExercise)?.targetDurationSeconds ?? 0
    }

    private func save() {
        do {
            try manager.renameExercise(sessionExercise, to: name)
            if exercise.isTimed {
                try manager.updateTargetDuration(seconds, for: sessionExercise)
            } else {
                try manager.updateTargetReps(reps, for: sessionExercise)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
