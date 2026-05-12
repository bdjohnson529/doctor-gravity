import Foundation

/// Providers exposed in the Settings picker. All use the OpenAI-compatible
/// `/chat/completions` schema, so the rest of the app code doesn't care which
/// is selected. MVP ships OpenAI only; Anthropic and Google are pre-wired but
/// hidden in `SettingsView` until verified end-to-end.
enum LLMProvider: String, Codable, CaseIterable, Identifiable {
    case openai
    case anthropic
    case google

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openai: "OpenAI"
        case .anthropic: "Anthropic"
        case .google: "Google"
        }
    }

    var baseURL: URL {
        switch self {
        case .openai:    URL(string: "https://api.openai.com/v1/chat/completions")!
        case .anthropic: URL(string: "https://api.anthropic.com/v1/chat/completions")!
        case .google:    URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")!
        }
    }

    var defaultModel: String {
        switch self {
        case .openai:    "gpt-4o-mini"
        case .anthropic: "claude-sonnet-4-6"
        case .google:    "gemini-2.5-flash"
        }
    }

    /// Providers verified in this MVP. Settings UI shows only these by default.
    static var availableInMVP: [LLMProvider] { [.openai] }
}
