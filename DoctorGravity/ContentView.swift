import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Doctor Gravity")
                .font(.largeTitle.bold())
            Text("Phase 1 — Models & Persistence")
                .foregroundStyle(.secondary)
        }
        .padding()
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
