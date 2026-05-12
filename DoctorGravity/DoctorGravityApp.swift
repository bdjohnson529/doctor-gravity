import SwiftUI
import SwiftData

@main
struct DoctorGravityApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
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
