import SwiftUI
import SwiftData

struct TemplateDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.workoutManager) private var workoutManager

    @Bindable var template: WorkoutTemplate

    @State private var progressionSnapshot: WorkoutSnapshot?
    @State private var startedSession: WorkoutSession?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                actionButtons
                exerciseList
            }
            .padding()
        }
        .navigationTitle(template.title)
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $progressionSnapshot) { snapshot in
            ProgressionEditorView(
                template: template,
                draftSnapshot: snapshot
            )
        }
        .navigationDestination(item: $startedSession) { session in
            WorkoutExecutionView(session: session)
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

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(headerSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var headerSubtitle: String {
        let setCount = template.orderedSets.count
        let exerciseCount = template.orderedSets.reduce(0) { $0 + $1.exercises.count }
        return "\(setCount) sets · \(exerciseCount) exercises"
    }

    // MARK: - Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                startWorkout()
            } label: {
                Label("Start Workout", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                openProgression()
            } label: {
                Label("Increase Progression", systemImage: "arrow.up.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private func startWorkout() {
        guard let manager = workoutManager else {
            errorMessage = "Workout manager not available."
            return
        }
        do {
            startedSession = try manager.startSession(for: template)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openProgression() {
        guard let manager = workoutManager else {
            errorMessage = "Workout manager not available."
            return
        }
        do {
            progressionSnapshot = try manager.createProgression(for: template)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Exercise list

    @ViewBuilder
    private var exerciseList: some View {
        if let snapshot = template.activeSnapshot {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(template.orderedSets) { set in
                    SetCard(set: set, snapshot: snapshot)
                }
            }
        } else {
            ContentUnavailableView(
                "No active snapshot",
                systemImage: "exclamationmark.triangle",
                description: Text("Targets can't be displayed — the template is missing an active snapshot.")
            )
        }
    }
}

// MARK: - Set card

private struct SetCard: View {
    let set: WorkoutSet
    let snapshot: WorkoutSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Set \(set.order + 1)")
                    .font(.headline)
                Spacer()
                Text("\(set.restSeconds)s rest")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(set.orderedExercises) { exercise in
                ExerciseDetailRow(exercise: exercise, target: snapshot.target(for: exercise))
                if exercise.id != set.orderedExercises.last?.id {
                    Divider()
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
    }
}

private struct ExerciseDetailRow: View {
    let exercise: WorkoutExercise
    let target: ExerciseTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(exercise.name)
                    .font(.body.weight(.semibold))
                Spacer()
                Text(targetLabel)
                    .font(.callout.monospaced())
                    .foregroundStyle(.primary)
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
        if exercise.isTimed, let s = target.targetDurationSeconds { return "\(s)s" }
        if let r = target.targetReps { return "\(r) reps" }
        return "—"
    }
}

#Preview {
    NavigationStack {
        TemplateDetailView(template: WorkoutTemplate(title: "Preview Template"))
    }
    .modelContainer(for: [
        WorkoutTemplate.self, WorkoutSet.self, WorkoutExercise.self,
        WorkoutSnapshot.self, ExerciseTarget.self,
        WorkoutSession.self, SessionSet.self, SessionExercise.self
    ], inMemory: true)
}
