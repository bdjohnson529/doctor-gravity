import SwiftUI
import SwiftData

@main
struct DoctorGravityApp: App {
    private let llmService: LLMServiceProtocol = MockLLMService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.llmService, llmService)
        }
        .modelContainer(for: [
            WorkoutTemplate.self,
            WorkoutSet.self,
            WorkoutExercise.self,
            WorkoutSnapshot.self,
            ExerciseTarget.self,
            WorkoutSession.self,
            SessionSet.self,
            SessionExercise.self
        ])
    }
}

/// Bridges the SwiftData `modelContext` env value into the `WorkoutManager`
/// env value. Built once when the root view first appears so the manager
/// lifetime matches the scene's container.
private struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var workoutManager: WorkoutManager?

    var body: some View {
        Group {
            if let workoutManager {
                ContentView()
                    .environment(\.workoutManager, workoutManager)
            } else {
                Color.clear
            }
        }
        .task {
            if workoutManager == nil {
                workoutManager = WorkoutManager(modelContext: modelContext)
            }
        }
    }
}
