import Foundation
import SwiftUI

/// Generates a workout template (plus its initial active snapshot) from a
/// natural-language prompt. Both `MockLLMService` (Phase 2) and `LLMService`
/// (Phase 6) conform to this. Views always reference the protocol, never a
/// concrete type — inject via `\.llmService` in the environment.
protocol LLMServiceProtocol {
    func generateTemplate(prompt: String) async throws -> ParsedTemplate
}

// MARK: - Environment injection

private struct LLMServiceKey: EnvironmentKey {
    static let defaultValue: LLMServiceProtocol = MockLLMService()
}

extension EnvironmentValues {
    var llmService: LLMServiceProtocol {
        get { self[LLMServiceKey.self] }
        set { self[LLMServiceKey.self] = newValue }
    }
}
