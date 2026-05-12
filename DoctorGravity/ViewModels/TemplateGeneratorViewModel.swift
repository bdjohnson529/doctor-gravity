import Foundation
import SwiftData
import Observation

/// Drives `TemplateGeneratorView`. Owns the prompt buffer and the four-state
/// machine (`.idle → .loading → .preview → .saved` or `.error`). Saving inserts
/// the parsed template + initial snapshot in a single transaction (PRD §4.2,
/// §7 "Atomic saves").
@Observable
@MainActor
final class TemplateGeneratorViewModel {

    enum State: Equatable {
        case idle
        case loading
        case preview(ParsedTemplate)
        case saved(WorkoutTemplate)
        case error(String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.loading, .loading): return true
            case (.preview(let a), .preview(let b)): return a.template.id == b.template.id
            case (.saved(let a), .saved(let b)): return a.id == b.id
            case (.error(let a), .error(let b)): return a == b
            default: return false
            }
        }
    }

    static let maxPromptLength = 300

    var prompt: String = "" {
        didSet {
            if prompt.count > Self.maxPromptLength {
                prompt = String(prompt.prefix(Self.maxPromptLength))
            }
        }
    }
    private(set) var state: State = .idle

    private let service: LLMServiceProtocol
    private let modelContext: ModelContext

    init(service: LLMServiceProtocol, modelContext: ModelContext) {
        self.service = service
        self.modelContext = modelContext
    }

    var canGenerate: Bool {
        guard case .loading = state else {
            return !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }

    func generate() async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        state = .loading
        do {
            let parsed = try await service.generateTemplate(prompt: trimmed)
            state = .preview(parsed)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Insert the previewed template + its initial snapshot in a single
    /// SwiftData transaction. Inserting the template cascades through its
    /// relationship graph (sets → exercises, snapshot → targets) so we only
    /// need to insert the two roots.
    func save() {
        guard case .preview(let parsed) = state else { return }

        modelContext.insert(parsed.template)
        modelContext.insert(parsed.initialSnapshot)

        do {
            try modelContext.save()
            state = .saved(parsed.template)
        } catch {
            modelContext.rollback()
            state = .error("Couldn't save template: \(error.localizedDescription)")
        }
    }

    /// Discard the current preview and return to idle so the user can edit
    /// the prompt and regenerate.
    func discardPreview() {
        state = .idle
    }

    /// Reset everything after a successful save so the user can generate another.
    func reset() {
        prompt = ""
        state = .idle
    }

    /// Re-run generation from the error state.
    func retry() async {
        guard case .error = state else { return }
        await generate()
    }
}
