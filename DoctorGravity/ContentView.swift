import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TemplateListView()
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
