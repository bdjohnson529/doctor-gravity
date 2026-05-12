import SwiftUI
import SwiftData

/// Summary screen shown after the final exercise. Reports completed sets and
/// total actual reps logged. PRD §5.3 — also the moment first-run completion
/// flips `template.hasBeenCompleted = true`, handled by `WorkoutManager.finish`.
struct CompletionStepView: View {
    let session: WorkoutSession
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 96))
                .foregroundStyle(.green)

            Text("Workout Complete")
                .font(.largeTitle.bold())

            VStack(spacing: 8) {
                summaryRow(label: "Sets", value: "\(session.orderedSets.count)")
                summaryRow(label: "Total reps", value: "\(session.totalActualReps)")
                if let completedAt = session.completedAt {
                    summaryRow(
                        label: "Finished",
                        value: completedAt.formatted(date: .omitted, time: .shortened)
                    )
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))

            Spacer()

            Button {
                onDone()
            } label: {
                Label("Done", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.body.weight(.semibold).monospacedDigit())
        }
    }
}
