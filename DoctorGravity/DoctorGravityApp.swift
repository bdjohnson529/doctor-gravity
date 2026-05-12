import SwiftUI
import SwiftData

@main
struct DoctorGravityApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
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

/// Owns the singletons that need the scene's `modelContext` or want a stable
/// lifetime across the app: the settings store, the LLM client built from it,
/// and the WorkoutManager. Created once when the view first appears.
private struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var settingsStore: LLMSettingsStore?
    @State private var llmService: LLMServiceProtocol?
    @State private var workoutManager: WorkoutManager?

    var body: some View {
        Group {
            if let settingsStore, let llmService, let workoutManager {
                ContentView()
                    .environment(\.llmService, llmService)
                    .environment(\.llmSettingsStore, settingsStore)
                    .environment(\.workoutManager, workoutManager)
            } else {
                Color.clear
            }
        }
        .task {
            if settingsStore == nil {
                let store = LLMSettingsStore()
                settingsStore = store
                llmService = LLMService(settings: { @MainActor in store.snapshot })
                workoutManager = WorkoutManager(modelContext: modelContext)
            }
        }
    }
}
