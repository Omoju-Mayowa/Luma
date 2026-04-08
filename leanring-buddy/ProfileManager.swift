import Foundation
@preconcurrency import Combine

// MARK: - LumaAPIProvider

/// The AI provider type for an API profile.
enum LumaAPIProvider: String, Codable, CaseIterable {
    case openRouter = "OpenRouter"
    case anthropic = "Anthropic"
    case google = "Google"
    case custom = "Custom"

    /// Human-readable display name
    var displayName: String { rawValue }

    /// The default base URL for this provider's chat completions endpoint.
    var defaultBaseURL: String {
        switch self {
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .anthropic:  return "https://api.anthropic.com/v1"
        case .google:     return "https://generativelanguage.googleapis.com/v1beta/openai"
        case .custom:     return ""
        }
    }

    /// The auth header name used by this provider.
    /// Anthropic uses x-api-key; everyone else uses Authorization: Bearer.
    var authHeaderName: String {
        switch self {
        case .anthropic: return "x-api-key"
        default: return "Authorization"
        }
    }

    /// Whether the auth value needs "Bearer " prefix
    var requiresBearerPrefix: Bool {
        switch self {
        case .anthropic: return false
        default: return true
        }
    }
}

// MARK: - LumaAPIProfile

/// A stored API configuration profile.
/// The profile metadata (everything except the API key) is stored together in Keychain as JSON.
/// Each profile's API key is stored separately in Keychain under its own key.
struct LumaAPIProfile: Codable, Identifiable {
    /// Stable UUID for this profile
    let id: UUID
    /// Human-readable profile name (e.g. "Work - OpenRouter", "Personal - Anthropic")
    var name: String
    /// The AI provider
    var provider: LumaAPIProvider
    /// Override for the base URL (used for Custom provider or custom endpoints)
    var baseURL: String
    /// Whether this is the active/default profile
    var isDefault: Bool
    /// The model selected for this profile (e.g. "google/gemini-2.5-flash:free")
    var selectedModel: String

    /// The Keychain key where this profile's API key is stored.
    /// Format: "com.nox.luma.apikey.<profile-id>"
    var keychainAPIKeyIdentifier: String {
        "com.nox.luma.apikey.\(id.uuidString)"
    }

    /// The effective base URL: uses the provider's default if baseURL is empty.
    var effectiveBaseURL: String {
        baseURL.isEmpty ? provider.defaultBaseURL : baseURL
    }

    init(id: UUID = UUID(), name: String, provider: LumaAPIProvider, baseURL: String = "", isDefault: Bool = false, selectedModel: String = "") {
        self.id = id
        self.name = name
        self.provider = provider
        self.baseURL = baseURL
        self.isDefault = isDefault
        self.selectedModel = selectedModel
    }
}

// MARK: - ProfileManager

/// Manages the collection of LumaAPIProfile objects.
/// Profile metadata is stored as a JSON array in Keychain.
/// Each profile's API key is stored in Keychain separately.
@MainActor
final class ProfileManager: ObservableObject {

    static let shared = ProfileManager()

    private let profilesKeychainKey = "com.nox.luma.profiles"

    /// All stored profiles, ordered (default profile first).
    @Published private(set) var profiles: [LumaAPIProfile] = []

    /// The currently active (default) profile, if any.
    var activeProfile: LumaAPIProfile? {
        profiles.first(where: { $0.isDefault }) ?? profiles.first
    }

    private init() {
        loadProfiles()
    }

    // MARK: - Profile CRUD

    /// Adds a new profile. If it's the first profile, marks it as default.
    func addProfile(_ profile: LumaAPIProfile) {
        var newProfile = profile
        if profiles.isEmpty { newProfile.isDefault = true }
        profiles.append(newProfile)
        saveProfiles()
    }

    /// Updates an existing profile (matched by id).
    func updateProfile(_ updatedProfile: LumaAPIProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == updatedProfile.id }) else { return }
        profiles[index] = updatedProfile
        saveProfiles()
    }

    /// Deletes a profile and its API key from Keychain.
    func deleteProfile(withID profileID: UUID) throws {
        guard let profile = profiles.first(where: { $0.id == profileID }) else { return }
        try KeychainManager.delete(key: profile.keychainAPIKeyIdentifier)
        profiles.removeAll(where: { $0.id == profileID })
        // If we removed the default, promote the first remaining profile
        if !profiles.isEmpty && !profiles.contains(where: { $0.isDefault }) {
            profiles[0].isDefault = true
        }
        saveProfiles()
    }

    /// Sets the given profile as the default, unsets all others.
    func setDefaultProfile(withID profileID: UUID) {
        for index in profiles.indices {
            profiles[index].isDefault = (profiles[index].id == profileID)
        }
        saveProfiles()
    }

    // MARK: - API Key Storage

    /// Saves the API key for a profile to Keychain.
    func saveAPIKey(_ apiKey: String, forProfileID profileID: UUID) throws {
        guard let profile = profiles.first(where: { $0.id == profileID }) else { return }
        try KeychainManager.save(key: profile.keychainAPIKeyIdentifier, string: apiKey)
    }

    /// Loads the API key for a profile from Keychain. Returns nil if not set.
    func loadAPIKey(forProfileID profileID: UUID) -> String? {
        guard let profile = profiles.first(where: { $0.id == profileID }) else { return nil }
        return try? KeychainManager.loadString(key: profile.keychainAPIKeyIdentifier)
    }

    /// Loads the API key for the active profile.
    func loadActiveAPIKey() -> String? {
        guard let activeProfile = activeProfile else { return nil }
        return loadAPIKey(forProfileID: activeProfile.id)
    }

    /// Deletes all profiles and their API keys (used by Reset Luma).
    func deleteAllProfiles() throws {
        for profile in profiles {
            try? KeychainManager.delete(key: profile.keychainAPIKeyIdentifier)
        }
        profiles = []
        try? KeychainManager.delete(key: profilesKeychainKey)
    }

    // MARK: - Persistence

    private func saveProfiles() {
        guard let encoded = try? JSONEncoder().encode(profiles) else { return }
        try? KeychainManager.save(key: profilesKeychainKey, data: encoded)
    }

    private func loadProfiles() {
        guard
            let data = try? KeychainManager.load(key: profilesKeychainKey),
            let decoded = try? JSONDecoder().decode([LumaAPIProfile].self, from: data)
        else { return }
        profiles = decoded
    }
}
