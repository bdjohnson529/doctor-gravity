import SwiftUI
import SwiftData

@main
struct DoctorGravityApp: App {
    private let llmService: LLMServiceProtocol = MockLLMService()

    var body: some Scene {
        WindowGroup {
            ContentView()
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
