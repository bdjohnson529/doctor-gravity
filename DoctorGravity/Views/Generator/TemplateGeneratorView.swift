import SwiftUI
import SwiftData

struct TemplateGeneratorView: View {
    @State private var viewModel: TemplateGeneratorViewModel

    init(viewModel: TemplateGeneratorViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    promptSection
                    actionSection
                    bodySection
                }
                .padding()
            }
            .navigationTitle("Generate Workout")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Prompt input

    @ViewBuilder
    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Describe your workout")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField(
                "e.g. 20-minute full-body workout, no equipment",
                text: $viewModel.prompt,
                axis: .vertical
            )
            .lineLimit(3...6)
            .textFieldStyle(.roundedBorder)
            .disabled(viewModel.state == .loading)

            HStack {
                Spacer()
                Text("\(viewModel.prompt.count) / \(TemplateGeneratorViewModel.maxPromptLength)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Generate / loading / error CTA

    @ViewBuilder
    private var actionSection: some View {
        switch viewModel.state {
        case .idle, .preview:
            Button {
                Task { await viewModel.generate() }
            } label: {
                Label("Generate", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canGenerate)

        case .loading:
            HStack(spacing: 12) {
                ProgressView()
                Text("Generating template…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))

        case .error(let message):
            VStack(alignment: .leading, spacing: 12) {
                Label("Couldn't generate template", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Retry") {
                        Task { await viewModel.retry() }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Dismiss", role: .cancel) {
                        viewModel.discardPreview()
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))

        case .saved:
            VStack(alignment: .leading, spacing: 12) {
                Label("Template saved", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Text("Template list and workout execution come in the next phase.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Generate another") {
                    viewModel.reset()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
        }
    }

    // MARK: - Preview body

    @ViewBuilder
    private var bodySection: some View {
        if case .preview(let parsed) = viewModel.state {
            TemplatePreviewView(parsed: parsed) {
                viewModel.save()
            } onDiscard: {
                viewModel.discardPreview()
            }
        }
    }
}

// MARK: - Preview card

private struct TemplatePreviewView: View {
    let parsed: ParsedTemplate
    let onSave: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(parsed.template.title)
                    .font(.title2.bold())
                Text("\(parsed.template.orderedSets.count) sets · \(totalExerciseCount) exercises")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(parsed.template.orderedSets) { set in
                SetPreviewRow(set: set, snapshot: parsed.initialSnapshot)
            }

            HStack {
                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Button("Discard", role: .destructive, action: onDiscard)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
    }

    private var totalExerciseCount: Int {
        parsed.template.orderedSets.reduce(0) { $0 + $1.exercises.count }
    }
}

private struct SetPreviewRow: View {
    let set: WorkoutSet
    let snapshot: WorkoutSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Set \(set.order + 1)")
                    .font(.headline)
                Spacer()
                Text("\(set.restSeconds)s rest")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(set.orderedExercises) { exercise in
                ExercisePreviewRow(exercise: exercise, target: snapshot.target(for: exercise))
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemBackground), in: .rect(cornerRadius: 8))
    }
}

private struct ExercisePreviewRow: View {
    let exercise: WorkoutExercise
    let target: ExerciseTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(exercise.name)
                    .font(.body.weight(.medium))
                Spacer()
                Text(targetLabel)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            }
            if let notes = exercise.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var targetLabel: String {
        guard let target else { return "—" }
        if exercise.isTimed, let seconds = target.targetDurationSeconds {
            return "\(seconds)s"
        }
        if let reps = target.targetReps {
            return "\(reps) reps"
        }
        return "—"
    }
}

#Preview {
    do {
        let container = try ModelContainer(
            for:
                WorkoutTemplate.self, WorkoutSet.self, WorkoutExercise.self,
                WorkoutSnapshot.self, ExerciseTarget.self,
                WorkoutSession.self, SessionSet.self, SessionExercise.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let vm = TemplateGeneratorViewModel(
            service: MockLLMService(),
            modelContext: container.mainContext
        )
        return TemplateGeneratorView(viewModel: vm)
            .modelContainer(container)
    } catch {
        return Text("Preview failed: \(error.localizedDescription)")
    }
}
