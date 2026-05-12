import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \WorkoutSession.startedAt, order: .reverse)
    private var sessions: [WorkoutSession]

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: WorkoutSession.self) { session in
                if session.isCompleted {
                    HistoryDetailView(session: session)
                } else {
                    WorkoutExecutionView(session: session)
                }
            }
        }
    }

    // MARK: - Sections

    private var completed: [WorkoutSession] {
        sessions.filter(\.isCompleted)
    }

    private var inProgress: [WorkoutSession] {
        sessions.filter { !$0.isCompleted }
    }

    private var totalReps: Int {
        completed.reduce(0) { $0 + $1.totalActualReps }
    }

    // MARK: - List

    private var list: some View {
        List {
            statsSection
            if !inProgress.isEmpty {
                inProgressSection
            }
            if !completed.isEmpty {
                completedSection
            }
        }
    }

    private var statsSection: some View {
        Section {
            HStack {
                Label("Total reps", systemImage: "sum")
                Spacer()
                Text("\(totalReps)")
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .contentTransition(.numericText())
            }
            HStack {
                Label("Workouts completed", systemImage: "checkmark.seal")
                Spacer()
                Text("\(completed.count)")
                    .font(.title3.monospacedDigit().weight(.semibold))
            }
        } header: {
            Text("Stats")
        }
    }

    private var inProgressSection: some View {
        Section {
            ForEach(inProgress) { session in
                NavigationLink(value: session) {
                    InProgressRow(session: session)
                }
            }
            .onDelete { offsets in
                deleteSessions(inProgress, at: offsets)
            }
        } header: {
            Text("In Progress")
        } footer: {
            Text("Tap to resume.")
        }
    }

    private var completedSection: some View {
        Section {
            ForEach(completed) { session in
                NavigationLink(value: session) {
                    CompletedRow(session: session)
                }
            }
            .onDelete { offsets in
                deleteSessions(completed, at: offsets)
            }
        } header: {
            Text("Completed")
        }
    }

    private func deleteSessions(_ list: [WorkoutSession], at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(list[index])
        }
        try? modelContext.save()
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView(
            "No workouts yet",
            systemImage: "clock.arrow.circlepath",
            description: Text("Complete a workout to start building your history.")
        )
    }
}

// MARK: - Rows

private struct CompletedRow: View {
    let session: WorkoutSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.template?.title ?? "Workout")
                .font(.headline)
            HStack(spacing: 8) {
                if let completedAt = session.completedAt {
                    Text(completedAt.formatted(date: .abbreviated, time: .shortened))
                }
                Text("·")
                Text("\(session.totalActualReps) reps")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct InProgressRow: View {
    let session: WorkoutSession

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.template?.title ?? "Workout")
                    .font(.headline)
                Text("Started \(session.startedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "play.circle.fill")
                .foregroundStyle(.tint)
                .font(.title2)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    HistoryView()
        .modelContainer(for: [
            WorkoutTemplate.self, WorkoutSet.self, WorkoutExercise.self,
            WorkoutSnapshot.self, ExerciseTarget.self,
            WorkoutSession.self, SessionSet.self, SessionExercise.self
        ], inMemory: true)
}
