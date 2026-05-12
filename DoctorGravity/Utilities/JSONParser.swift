import Foundation

/// Errors thrown when decoding an LLM response into the SwiftData object graph.
/// Always surfaced to the user via the generator view — never silently swallowed.
enum LLMParseError: Error, LocalizedError {
    case emptyResponse
    case decodingFailed(underlying: Error, raw: String)
    case missingField(String)
    case invalidTarget(exerciseName: String, reason: String)
    case emptyTemplate

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "The model returned an empty response."
        case .decodingFailed(_, _):
            return "The model returned a response that couldn't be read as a workout template."
        case .missingField(let field):
            return "The model response is missing a required field: \(field)."
        case .invalidTarget(let exerciseName, let reason):
            return "Target for '\(exerciseName)' is invalid: \(reason)"
        case .emptyTemplate:
            return "The model returned a template with no exercises."
        }
    }
}

/// Result of a successful parse: the template, its sets/exercises (wired into
/// `template.sets`), and the initial active snapshot with one target per exercise.
/// The caller is responsible for inserting these into a `ModelContext` as a
/// single transaction (PRD §4.2).
struct ParsedTemplate {
    let template: WorkoutTemplate
    let initialSnapshot: WorkoutSnapshot
}

/// Decodes LLM JSON into a `WorkoutTemplate` + initial `WorkoutSnapshot`.
///
/// Expected JSON contract (mirrors PRD §3 field names):
/// ```
/// {
///   "title": "Full Body Strength",
///   "sets": [
///     {
///       "order": 0,
///       "restSeconds": 60,
///       "exercises": [
///         { "name": "Push-ups", "order": 0, "isTimed": false,
///           "notes": "Keep core tight",
///           "target": { "targetReps": 10 } },
///         { "name": "Plank", "order": 1, "isTimed": true, "notes": null,
///           "target": { "targetDurationSeconds": 30 } }
///       ]
///     }
///   ]
/// }
/// ```
///
/// Enforces the §3.5 invariant: each `target` has exactly one of `targetReps`
/// or `targetDurationSeconds`, matching the parent exercise's `isTimed`.
enum JSONParser {

    // MARK: - DTOs (decode shape only — do not leak outside this file)

    private struct TemplateDTO: Decodable {
        let title: String
        let sets: [SetDTO]
    }

    private struct SetDTO: Decodable {
        let order: Int
        let restSeconds: Int?
        let exercises: [ExerciseDTO]
    }

    private struct ExerciseDTO: Decodable {
        let name: String
        let order: Int
        let isTimed: Bool
        let notes: String?
        let target: TargetDTO
    }

    private struct TargetDTO: Decodable {
        let targetReps: Int?
        let targetDurationSeconds: Int?
    }

    // MARK: - Public API

    /// Parse a JSON string from the LLM. Strips markdown fences defensively in
    /// case the model ignores the no-fence instruction.
    static func parseTemplate(from jsonString: String) throws -> ParsedTemplate {
        let trimmed = stripCodeFences(from: jsonString)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            throw LLMParseError.emptyResponse
        }

        guard let data = trimmed.data(using: .utf8) else {
            throw LLMParseError.decodingFailed(
                underlying: NSError(domain: "JSONParser", code: -1),
                raw: jsonString
            )
        }

        let dto: TemplateDTO
        do {
            dto = try JSONDecoder().decode(TemplateDTO.self, from: data)
        } catch {
            #if DEBUG
            print("[JSONParser] decode failed. Raw response:\n\(jsonString)")
            #endif
            throw LLMParseError.decodingFailed(underlying: error, raw: jsonString)
        }

        return try build(from: dto)
    }

    // MARK: - DTO → SwiftData graph

    private static func build(from dto: TemplateDTO) throws -> ParsedTemplate {
        guard !dto.title.isEmpty else {
            throw LLMParseError.missingField("title")
        }
        guard !dto.sets.isEmpty else {
            throw LLMParseError.emptyTemplate
        }
        let totalExercises = dto.sets.reduce(0) { $0 + $1.exercises.count }
        guard totalExercises > 0 else {
            throw LLMParseError.emptyTemplate
        }

        let template = WorkoutTemplate(title: dto.title)
        let snapshot = WorkoutSnapshot(isActive: true)
        snapshot.template = template

        for setDTO in dto.sets.sorted(by: { $0.order < $1.order }) {
            let set = WorkoutSet(
                order: setDTO.order,
                restSeconds: setDTO.restSeconds ?? 60
            )
            set.template = template
            template.sets.append(set)

            for exerciseDTO in setDTO.exercises.sorted(by: { $0.order < $1.order }) {
                let exercise = WorkoutExercise(
                    name: exerciseDTO.name,
                    order: exerciseDTO.order,
                    isTimed: exerciseDTO.isTimed,
                    notes: exerciseDTO.notes
                )
                exercise.set = set
                set.exercises.append(exercise)

                let target = try makeTarget(from: exerciseDTO.target, for: exercise)
                target.snapshot = snapshot
                target.workoutExercise = exercise
                snapshot.targets.append(target)
            }
        }

        return ParsedTemplate(template: template, initialSnapshot: snapshot)
    }

    // MARK: - Invariant: exactly-one-of, matching isTimed (PRD §3.5)

    private static func makeTarget(
        from dto: TargetDTO,
        for exercise: WorkoutExercise
    ) throws -> ExerciseTarget {
        try validateTarget(dto, for: exercise)
        return ExerciseTarget(
            targetReps: dto.targetReps,
            targetDurationSeconds: dto.targetDurationSeconds
        )
    }

    /// Rejects any target that violates §3.5.
    private static func validateTarget(_ dto: TargetDTO, for exercise: WorkoutExercise) throws {
        let hasReps = dto.targetReps != nil
        let hasDuration = dto.targetDurationSeconds != nil

        switch (hasReps, hasDuration) {
        case (true, true):
            throw LLMParseError.invalidTarget(
                exerciseName: exercise.name,
                reason: "both targetReps and targetDurationSeconds are set; exactly one is required"
            )
        case (false, false):
            throw LLMParseError.invalidTarget(
                exerciseName: exercise.name,
                reason: "neither targetReps nor targetDurationSeconds is set; exactly one is required"
            )
        case (true, false) where exercise.isTimed:
            throw LLMParseError.invalidTarget(
                exerciseName: exercise.name,
                reason: "exercise is timed but target uses targetReps; expected targetDurationSeconds"
            )
        case (false, true) where !exercise.isTimed:
            throw LLMParseError.invalidTarget(
                exerciseName: exercise.name,
                reason: "exercise is rep-based but target uses targetDurationSeconds; expected targetReps"
            )
        default:
            return
        }
    }

    // MARK: - Helpers

    private static func stripCodeFences(from raw: String) -> String {
        var s = raw
        if let r = s.range(of: "```json", options: .caseInsensitive) {
            s.removeSubrange(s.startIndex..<r.upperBound)
        } else if let r = s.range(of: "```") {
            s.removeSubrange(s.startIndex..<r.upperBound)
        }
        if let r = s.range(of: "```", options: .backwards) {
            s.removeSubrange(r.lowerBound..<s.endIndex)
        }
        return s
    }
}

extension JSONParser {
    /// Convenience overload for tests and runtime defensive checks where the
    /// caller has ints rather than a decoded DTO.
    static func validateTarget(
        targetReps: Int?,
        targetDurationSeconds: Int?,
        for exercise: WorkoutExercise
    ) throws {
        try validateTarget(
            TargetDTO(targetReps: targetReps, targetDurationSeconds: targetDurationSeconds),
            for: exercise
        )
    }
}
