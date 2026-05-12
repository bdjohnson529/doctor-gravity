import XCTest
import SwiftData
@testable import DoctorGravity

final class JSONParserTests: XCTestCase {

    // MARK: - isTimed invariant (PRD §3.5)

    func testRepBasedExerciseRequiresTargetReps() throws {
        let exercise = WorkoutExercise(name: "Push-ups", order: 0, isTimed: false)

        XCTAssertNoThrow(try JSONParser.validateTarget(
            targetReps: 10, targetDurationSeconds: nil, for: exercise
        ))
    }

    func testTimedExerciseRequiresTargetDuration() throws {
        let exercise = WorkoutExercise(name: "Plank", order: 0, isTimed: true)

        XCTAssertNoThrow(try JSONParser.validateTarget(
            targetReps: nil, targetDurationSeconds: 30, for: exercise
        ))
    }

    func testRepBasedExerciseRejectsDurationTarget() {
        let exercise = WorkoutExercise(name: "Push-ups", order: 0, isTimed: false)

        XCTAssertThrowsError(try JSONParser.validateTarget(
            targetReps: nil, targetDurationSeconds: 30, for: exercise
        )) { error in
            guard case LLMParseError.invalidTarget = error else {
                XCTFail("expected invalidTarget, got \(error)"); return
            }
        }
    }

    func testTimedExerciseRejectsRepsTarget() {
        let exercise = WorkoutExercise(name: "Plank", order: 0, isTimed: true)

        XCTAssertThrowsError(try JSONParser.validateTarget(
            targetReps: 10, targetDurationSeconds: nil, for: exercise
        )) { error in
            guard case LLMParseError.invalidTarget = error else {
                XCTFail("expected invalidTarget, got \(error)"); return
            }
        }
    }

    func testRejectsBothFieldsSet() {
        let exercise = WorkoutExercise(name: "Push-ups", order: 0, isTimed: false)

        XCTAssertThrowsError(try JSONParser.validateTarget(
            targetReps: 10, targetDurationSeconds: 30, for: exercise
        )) { error in
            guard case LLMParseError.invalidTarget = error else {
                XCTFail("expected invalidTarget, got \(error)"); return
            }
        }
    }

    func testRejectsNeitherFieldSet() {
        let exercise = WorkoutExercise(name: "Push-ups", order: 0, isTimed: false)

        XCTAssertThrowsError(try JSONParser.validateTarget(
            targetReps: nil, targetDurationSeconds: nil, for: exercise
        )) { error in
            guard case LLMParseError.invalidTarget = error else {
                XCTFail("expected invalidTarget, got \(error)"); return
            }
        }
    }

    // MARK: - End-to-end parse

    func testParseValidTemplate() throws {
        let json = """
        {
          "title": "Full Body Strength",
          "sets": [
            {
              "order": 0,
              "restSeconds": 60,
              "exercises": [
                { "name": "Push-ups", "order": 0, "isTimed": false,
                  "notes": "Keep core tight",
                  "target": { "targetReps": 10 } },
                { "name": "Plank", "order": 1, "isTimed": true, "notes": null,
                  "target": { "targetDurationSeconds": 30 } }
              ]
            }
          ]
        }
        """

        let parsed = try JSONParser.parseTemplate(from: json)

        XCTAssertEqual(parsed.template.title, "Full Body Strength")
        XCTAssertEqual(parsed.template.sets.count, 1)
        XCTAssertEqual(parsed.template.sets.first?.exercises.count, 2)
        XCTAssertTrue(parsed.initialSnapshot.isActive)
        XCTAssertEqual(parsed.initialSnapshot.targets.count, 2)

        let pushups = parsed.initialSnapshot.targets.first { $0.workoutExercise?.name == "Push-ups" }
        XCTAssertEqual(pushups?.targetReps, 10)
        XCTAssertNil(pushups?.targetDurationSeconds)

        let plank = parsed.initialSnapshot.targets.first { $0.workoutExercise?.name == "Plank" }
        XCTAssertEqual(plank?.targetDurationSeconds, 30)
        XCTAssertNil(plank?.targetReps)
    }

    func testParseRejectsViolatedInvariant() {
        let json = """
        {
          "title": "Bad",
          "sets": [
            {
              "order": 0,
              "restSeconds": 60,
              "exercises": [
                { "name": "Push-ups", "order": 0, "isTimed": false, "notes": null,
                  "target": { "targetDurationSeconds": 30 } }
              ]
            }
          ]
        }
        """

        XCTAssertThrowsError(try JSONParser.parseTemplate(from: json)) { error in
            guard case LLMParseError.invalidTarget = error else {
                XCTFail("expected invalidTarget, got \(error)"); return
            }
        }
    }

    func testParseStripsMarkdownFences() throws {
        let json = """
        ```json
        {
          "title": "Fenced",
          "sets": [
            { "order": 0, "restSeconds": 45, "exercises": [
              { "name": "Sit-ups", "order": 0, "isTimed": false, "notes": null,
                "target": { "targetReps": 20 } }
            ] }
          ]
        }
        ```
        """

        let parsed = try JSONParser.parseTemplate(from: json)
        XCTAssertEqual(parsed.template.title, "Fenced")
    }

    func testParseRejectsEmptyResponse() {
        XCTAssertThrowsError(try JSONParser.parseTemplate(from: "  \n  ")) { error in
            guard case LLMParseError.emptyResponse = error else {
                XCTFail("expected emptyResponse, got \(error)"); return
            }
        }
    }

    // MARK: - SwiftData container initialises (Phase 1 done-when)

    @MainActor
    func testModelContainerInitialises() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for:
                WorkoutTemplate.self,
                WorkoutSet.self,
                WorkoutExercise.self,
                WorkoutSnapshot.self,
                ExerciseTarget.self,
                WorkoutSession.self,
                SessionSet.self,
                SessionExercise.self,
            configurations: config
        )
        XCTAssertNotNil(container.mainContext)
    }

    @MainActor
    func testCascadeDeleteTemplateRemovesGraph() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for:
                WorkoutTemplate.self,
                WorkoutSet.self,
                WorkoutExercise.self,
                WorkoutSnapshot.self,
                ExerciseTarget.self,
                WorkoutSession.self,
                SessionSet.self,
                SessionExercise.self,
            configurations: config
        )
        let ctx = container.mainContext

        let json = """
        {
          "title": "Cascade test",
          "sets": [
            { "order": 0, "restSeconds": 60, "exercises": [
              { "name": "Push-ups", "order": 0, "isTimed": false, "notes": null,
                "target": { "targetReps": 10 } }
            ] }
          ]
        }
        """
        let parsed = try JSONParser.parseTemplate(from: json)
        ctx.insert(parsed.template)
        ctx.insert(parsed.initialSnapshot)
        try ctx.save()

        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<WorkoutTemplate>()), 1)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<WorkoutSet>()), 1)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<WorkoutExercise>()), 1)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<WorkoutSnapshot>()), 1)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<ExerciseTarget>()), 1)

        ctx.delete(parsed.template)
        try ctx.save()

        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<WorkoutTemplate>()), 0)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<WorkoutSet>()), 0)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<WorkoutExercise>()), 0)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<WorkoutSnapshot>()), 0)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<ExerciseTarget>()), 0)
    }
}
