import Foundation
import SwiftUI
import Observation

/// User-editable LLM configuration. Provider + model live in UserDefaults;
/// the API key lives in Keychain. When the user hasn't entered a key, the
/// store falls back to a build-time value injected via xcconfig →
/// `Info.plist["OpenAIAPIKey"]` so developers can run against a real API
/// without hand-pasting the key every install.
@Observable
@MainActor
final class LLMSettingsStore {
    private let userDefaults: UserDefaults
    private let keychainService = "com.doctorgravity.app.llm"

    private enum Keys {
        static let provider = "llm.provider"
        static let model    = "llm.model"
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let initialProvider = LLMSettingsStore.readProvider(from: userDefaults)
        self.provider = initialProvider
        self.model    = LLMSettingsStore.readModel(from: userDefaults, provider: initialProvider)
        self.apiKey   = KeychainHelper.get(service: "com.doctorgravity.app.llm", account: initialProvider.rawValue) ?? ""
    }

    // MARK: - Stored values

    var provider: LLMProvider {
        didSet {
            guard provider != oldValue else { return }
            userDefaults.set(provider.rawValue, forKey: Keys.provider)
            // Model is per-provider — reset to the new provider's default and
            // reload its key from Keychain.
            model = LLMSettingsStore.readModel(from: userDefaults, provider: provider)
            apiKey = KeychainHelper.get(service: keychainService, account: provider.rawValue) ?? ""
        }
    }

    var model: String {
        didSet {
            guard model != oldValue else { return }
            userDefaults.set(model, forKey: Keys.model + "." + provider.rawValue)
        }
    }

    /// The key the user typed into Settings. Empty string means "not set" —
    /// the effective key may still come from xcconfig.
    var apiKey: String {
        didSet {
            guard apiKey != oldValue else { return }
            KeychainHelper.set(apiKey, service: keychainService, account: provider.rawValue)
        }
    }

    // MARK: - Effective values used by LLMService

    /// API key actually sent on requests. Keychain wins; xcconfig is the dev
    /// fallback.
    var effectiveAPIKey: String? {
        let trimmedKeychain = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKeychain.isEmpty { return trimmedKeychain }
        return Self.xcconfigFallbackKey(for: provider)
    }

    /// Where the effective key came from. Used by SettingsView to show a hint.
    var apiKeySource: APIKeySource {
        let trimmedKeychain = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKeychain.isEmpty { return .keychain }
        if Self.xcconfigFallbackKey(for: provider) != nil { return .xcconfig }
        return .none
    }

    enum APIKeySource {
        case keychain
        case xcconfig
        case none
    }

    /// Snapshot used by `LLMService` on each request so live setting edits
    /// take effect without restart.
    var snapshot: LLMSettings {
        LLMSettings(
            provider: provider,
            model: model.isEmpty ? provider.defaultModel : model,
            apiKey: effectiveAPIKey
        )
    }

    // MARK: - Defaults / reads

    private static func readProvider(from defaults: UserDefaults) -> LLMProvider {
        if let raw = defaults.string(forKey: Keys.provider),
           let p = LLMProvider(rawValue: raw) {
            return p
        }
        return .openai
    }

    private static func readModel(from defaults: UserDefaults, provider: LLMProvider) -> String {
        defaults.string(forKey: Keys.model + "." + provider.rawValue) ?? provider.defaultModel
    }

    private static func xcconfigFallbackKey(for provider: LLMProvider) -> String? {
        let infoKey: String
        switch provider {
        case .openai:    infoKey = "OpenAIAPIKey"
        case .anthropic: infoKey = "AnthropicAPIKey"
        case .google:    infoKey = "GoogleAPIKey"
        }
        guard let value = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String,
              !value.isEmpty,
              value != "$(\(infoKey))" else { return nil }
        return value
    }
}

// MARK: - Plain settings struct used by LLMService

struct LLMSettings {
    let provider: LLMProvider
    let model: String
    let apiKey: String?
}

// MARK: - Environment

private struct LLMSettingsStoreKey: EnvironmentKey {
    static var defaultValue: LLMSettingsStore? { nil }
}

extension EnvironmentValues {
    var llmSettingsStore: LLMSettingsStore? {
        get { self[LLMSettingsStoreKey.self] }
        set { self[LLMSettingsStoreKey.self] = newValue }
    }
}
