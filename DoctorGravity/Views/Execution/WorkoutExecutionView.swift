import SwiftUI
import SwiftData

/// Top-level execution screen. Dispatches on `WorkoutManager.state` to render the
/// current step (.exercise / .rest / .complete). Owns scenePhase observation to
/// flush in-progress state to SwiftData when the app backgrounds (PRD §7).
struct WorkoutExecutionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.workoutManager) private var workoutManager

    /// The session to execute. The view calls `manager.beginExecution(session)`
    /// in `.task` so the manager can resume at the first un-logged exercise.
    let session: WorkoutSession

    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let manager = workoutManager {
                content(manager: manager)
            } else {
                ContentUnavailableView(
                    "Workout manager unavailable",
                    systemImage: "exclamationmark.triangle"
                )
            }
        }
        .navigationTitle(session.template?.title ?? "Workout")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Pause") {
                    workoutManager?.pauseExecution()
                    dismiss()
                }
            }
        }
        .task {
            workoutManager?.beginExecution(session)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                workoutManager?.flush()
            }
        }
        .onDisappear {
            workoutManager?.pauseExecution()
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

    @ViewBuilder
    private func content(manager: WorkoutManager) -> some View {
        switch manager.state {
        case .idle:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .exercise(let sessionExercise):
            ExerciseStepView(
                manager: manager,
                sessionExercise: sessionExercise,
                onAdvance: advance,
                onStopTimed: stopTimedEarly
            )

        case .rest(let seconds):
            RestStepView(
                secondsRemaining: seconds,
                onSkip: skipRest
            )

        case .complete:
            CompletionStepView(session: session) {
                dismiss()
            }
        }
    }

    // MARK: - Actions

    private func advance() {
        do {
            try workoutManager?.advance()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stopTimedEarly() {
        do {
            try workoutManager?.stopTimedExerciseEarly()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func skipRest() {
        do {
            try workoutManager?.skipRest()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
