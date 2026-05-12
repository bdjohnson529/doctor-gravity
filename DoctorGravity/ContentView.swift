import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.llmService) private var llmService

    var body: some View {
        TemplateGeneratorView(
            viewModel: TemplateGeneratorViewModel(
                service: llmService,
                modelContext: modelContext
            )
        )
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            WorkoutTemplate.self,
            WorkoutSet.self,
            WorkoutExercise.self,
            WorkoutSnapshot.self,
            ExerciseTarget.self,
            WorkoutSession.self,
            SessionSet.self,
            SessionExercise.self
        ], inMemory: true)
}
