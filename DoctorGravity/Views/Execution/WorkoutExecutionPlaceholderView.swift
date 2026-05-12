import SwiftUI
import SwiftData

/// Phase 3 placeholder. Phase 4 will replace with `WorkoutExecutionView` driving
/// the `.exercise → .rest → .complete` state machine. The session is real — it's
/// been inserted into SwiftData — so Discard is offered to keep history clean.
struct WorkoutExecutionPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.workoutManager) private var workoutManager

    let session: WorkoutSession

    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summary
                Divider()
                exerciseList
            }
            .padding()
        }
        .navigationTitle("Session Started")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Discard", role: .destructive) {
                    discard()
                }
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

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Execution view comes in Phase 4", systemImage: "info.circle")
                .font(.headline)
            Text("Session created at \(session.startedAt.formatted(date: .omitted, time: .shortened)).")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
    }

    private var exerciseList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Will execute:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(session.orderedSets) { sessionSet in
                VStack(alignment: .leading, spacing: 6) {
                    Text("Set \(sessionSet.order + 1)")
                        .font(.headline)
                    ForEach(sessionSet.orderedExercises) { sessionExercise in
                        if let exercise = sessionExercise.workoutExercise {
                            Text("• \(exercise.name)")
                                .font(.body)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func discard() {
        guard let manager = workoutManager else {
            dismiss(); return
        }
        do {
            try manager.discardSession(session)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
