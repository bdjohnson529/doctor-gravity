import SwiftUI

/// LLM configuration screen. Provider (MVP: OpenAI only), model, and API key.
/// The API key is stored in Keychain when entered here; if left blank, the
/// app falls back to the build-time `OPENAI_API_KEY` defined in
/// `Config.xcconfig.local` (gitignored).
struct SettingsView: View {
    @Environment(\.llmSettingsStore) private var store

    @State private var draftAPIKey: String = ""
    @State private var savedFeedbackVisible = false

    var body: some View {
        NavigationStack {
            Group {
                if let store {
                    form(store: store)
                } else {
                    ContentUnavailableView(
                        "Settings unavailable",
                        systemImage: "exclamationmark.triangle"
                    )
                }
            }
            .navigationTitle("Settings")
        }
        .onAppear {
            draftAPIKey = store?.apiKey ?? ""
        }
    }

    @ViewBuilder
    private func form(store: LLMSettingsStore) -> some View {
        Form {
            Section {
                Picker("Provider", selection: providerBinding(store: store)) {
                    ForEach(LLMProvider.availableInMVP) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                .disabled(LLMProvider.availableInMVP.count <= 1)

                TextField("Model", text: modelBinding(store: store))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Model")
            } footer: {
                Text("Default for \(store.provider.displayName): \(store.provider.defaultModel)")
            }

            Section {
                SecureField("Paste API key", text: $draftAPIKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                HStack {
                    Button("Save key") {
                        store.apiKey = draftAPIKey
                        withAnimation { savedFeedbackVisible = true }
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation { savedFeedbackVisible = false }
                        }
                    }
                    .disabled(draftAPIKey.trimmingCharacters(in: .whitespaces).isEmpty)

                    Spacer()

                    if !store.apiKey.isEmpty {
                        Button("Clear", role: .destructive) {
                            store.apiKey = ""
                            draftAPIKey = ""
                        }
                    }
                }

                if savedFeedbackVisible {
                    Label("Saved to Keychain", systemImage: "checkmark.seal.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            } header: {
                Text("API Key")
            } footer: {
                sourceFooter(store: store)
            }

            Section {
                Text("MVP ships with OpenAI only. The wire format is OpenAI-compatible /chat/completions, so additional providers can be enabled in a future build without code changes here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func sourceFooter(store: LLMSettingsStore) -> some View {
        switch store.apiKeySource {
        case .keychain:
            Text("Using key from Keychain.")
        case .xcconfig:
            Text("No Keychain key set — using build-time fallback from Config.xcconfig.local.")
        case .none:
            Text("No key configured. Generation will fail until you add one.")
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Bindings

    private func providerBinding(store: LLMSettingsStore) -> Binding<LLMProvider> {
        Binding(get: { store.provider }, set: { store.provider = $0 })
    }

    private func modelBinding(store: LLMSettingsStore) -> Binding<String> {
        Binding(get: { store.model }, set: { store.model = $0 })
    }
}
