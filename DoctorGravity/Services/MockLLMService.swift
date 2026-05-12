import Foundation

/// Hardcoded LLM stand-in for Phases 2–5. Returns a fixed Full Body Strength
/// template with a mix of rep-based and timed exercises so the UI exercises
/// both code paths. Routes through `JSONParser` so the real parse pipeline
/// (including the §3.5 invariant check) is on the hot path during dev.
final class MockLLMService: LLMServiceProtocol {

    /// Simulated network latency so the `.loading` state is observable in the UI.
    var simulatedLatency: Duration = .milliseconds(800)

    func generateTemplate(prompt: String) async throws -> ParsedTemplate {
        try await Task.sleep(for: simulatedLatency)
        return try JSONParser.parseTemplate(from: Self.fixtureJSON)
    }

    private static let fixtureJSON = """
    {
      "title": "Full Body Strength",
      "sets": [
        {
          "order": 0,
          "restSeconds": 60,
          "exercises": [
            { "name": "Push-ups", "order": 0, "isTimed": false,
              "notes": "Keep core tight; chest to floor.",
              "target": { "targetReps": 12 } }
          ]
        },
        {
          "order": 1,
          "restSeconds": 60,
          "exercises": [
            { "name": "Bodyweight Squats", "order": 0, "isTimed": false,
              "notes": "Drive through your heels.",
              "target": { "targetReps": 15 } }
          ]
        },
        {
          "order": 2,
          "restSeconds": 90,
          "exercises": [
            { "name": "Plank", "order": 0, "isTimed": true,
              "notes": "Straight line from shoulders to heels.",
              "target": { "targetDurationSeconds": 45 } },
            { "name": "Mountain Climbers", "order": 1, "isTimed": true,
              "notes": "Drive knees toward chest.",
              "target": { "targetDurationSeconds": 30 } }
          ]
        },
        {
          "order": 3,
          "restSeconds": 60,
          "exercises": [
            { "name": "Sit-ups", "order": 0, "isTimed": false,
              "notes": "Slow and controlled.",
              "target": { "targetReps": 20 } }
          ]
        }
      ]
    }
    """
}
