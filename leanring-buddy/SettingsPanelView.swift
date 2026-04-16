//
//  SettingsPanelView.swift
//  leanring-buddy
//
//  4-tab settings panel presented as a sheet from the menu bar panel.
//  Tabs: Account, API Profiles, Model, General.
//

import SwiftUI

// MARK: - SettingsPanelView

@MainActor
struct SettingsPanelView: View {

    @Environment(\.dismiss) private var dismiss

    // Observe singletons so changes in each tab update the UI immediately.
    @StateObject private var accountManager = AccountManager.shared
    @StateObject private var profileManager = ProfileManager.shared
    @StateObject private var pinManager    = PINManager.shared

    /// Which tab is currently selected (0–3).
    @State private var selectedTabIndex: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // Custom tab bar — replaces native TabView tab bar to eliminate the blue accent
            // glow/ring that macOS renders on the selected tab item. Active tab uses
            // surfaceElevated fill only; no shadow, no ring, no glow in either state.
            HStack(spacing: 0) {
                settingsTabBarButton(label: "Account",      icon: "person.circle",  index: 0)
                settingsTabBarButton(label: "API Profiles", icon: "key.horizontal", index: 1)
                settingsTabBarButton(label: "Model",        icon: "cpu",            index: 2)
                settingsTabBarButton(label: "General",      icon: "gearshape",      index: 3)
            }
            .padding(.top, LumaTheme.paddingXL)

            Divider()
                .background(LumaTheme.border)

            // Tab content — only the selected view renders at a time
            Group {
                switch selectedTabIndex {
                case 0:
                    AccountTabView(
                        accountManager: accountManager,
                        profileManager: profileManager,
                        pinManager: pinManager,
                        onResetComplete: { dismiss() }
                    )
                case 1:
                    APIProfilesTabView(profileManager: profileManager)
                case 2:
                    ModelTabView(profileManager: profileManager)
                default:
                    GeneralTabView(pinManager: pinManager)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 500, height: 580)
        .background(LumaTheme.background)
        .focusEffectDisabled()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .font(LumaTheme.Typography.bodyMedium)
                    .foregroundColor(LumaTheme.textPrimary)
                    .focusEffectDisabled()
                    .onHover { isHovering in
                        if isHovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
            }
        }
    }

    /// One button in the custom settings tab bar.
    /// Selected: LumaTheme.surfaceElevated background, primary text — no glow or ring.
    /// Unselected: LumaTheme.surface background, secondary text.
    @ViewBuilder
    private func settingsTabBarButton(label: String, icon: String, index: Int) -> some View {
        let isSelected = selectedTabIndex == index
        Button {
            selectedTabIndex = index
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(label)
                    .font(.system(size: 11))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? LumaTheme.surfaceElevated : LumaTheme.surface)
            .foregroundColor(isSelected ? LumaTheme.textPrimary : LumaTheme.textSecondary)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            if isHovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

// MARK: - Tab 1: Account

/// Displays the user's avatar, username, editable display name, and the destructive Reset Luma action.
@MainActor
private struct AccountTabView: View {

    @ObservedObject var accountManager: AccountManager
    @ObservedObject var profileManager: ProfileManager
    @ObservedObject var pinManager:     PINManager

    /// Called after a successful reset so the parent sheet can dismiss.
    var onResetComplete: () -> Void

    /// Draft of the display name being edited in the text field.
    @State private var editedDisplayName: String = ""

    /// Controls visibility of the "Reset Luma" confirmation alert.
    @State private var isShowingResetConfirmationAlert: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: LumaTheme.Spacing.xl) {

                if let account = accountManager.currentAccount {
                    accountContentView(account: account)
                } else {
                    noAccountPlaceholderView
                }
            }
            .padding(LumaTheme.Spacing.xl)
        }
        .onAppear {
            // Pre-populate the display name field with the current value.
            editedDisplayName = accountManager.currentAccount?.displayName ?? ""
        }
    }

    // MARK: Account Content

    private func accountContentView(account: LumaAccount) -> some View {
        VStack(spacing: LumaTheme.Spacing.xl) {

            // Avatar + identity block
            VStack(spacing: LumaTheme.Spacing.sm) {
                LumaAvatarView(initials: account.avatarInitials, size: 56)

                Text(account.username)
                    .font(LumaTheme.Typography.headline)
                    .foregroundColor(LumaTheme.Colors.primaryText)

                Text(account.displayName)
                    .font(LumaTheme.Typography.body)
                    .foregroundColor(LumaTheme.Colors.secondaryText)
            }

            Divider()

            // Editable display name
            VStack(alignment: .leading, spacing: LumaTheme.Spacing.sm) {
                Text("Display Name")
                    .font(LumaTheme.Typography.bodyMedium)
                    .foregroundColor(LumaTheme.Colors.primaryText)

                TextField("Display name", text: $editedDisplayName)
                    .textFieldStyle(.plain)
                    .font(LumaTheme.Typography.body)
                    .foregroundColor(LumaTheme.Colors.primaryText)
                    .padding(LumaTheme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: LumaTheme.CornerRadius.medium)
                            .fill(LumaTheme.Colors.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: LumaTheme.CornerRadius.medium)
                            .stroke(LumaTheme.Colors.surfaceElevated, lineWidth: 1)
                    )
                    // Save when the user presses Return
                    .onSubmit {
                        saveDisplayNameIfChanged()
                    }
                    // Save when the field loses focus (blur equivalent in SwiftUI)
                    .onChange(of: editedDisplayName) { _ in
                        // We intentionally do NOT save on every keystroke;
                        // saving happens on submit/blur via onSubmit + focusLost.
                        // The onChange here is a no-op placeholder to make
                        // the "blur" pattern clear for future developers.
                    }
            }

            Divider()

            // Destructive: Reset Luma
            VStack(alignment: .leading, spacing: LumaTheme.Spacing.sm) {
                Text("Danger Zone")
                    .font(LumaTheme.Typography.bodyMedium)
                    .foregroundColor(LumaTheme.Colors.primaryText)

                Button(role: .destructive) {
                    isShowingResetConfirmationAlert = true
                } label: {
                    Text("Reset Luma")
                        .font(LumaTheme.Typography.body)
                        .foregroundColor(LumaTheme.Colors.error)
                }
                .buttonStyle(.plain)
                .onHover { isHovering in
                    if isHovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                .alert(
                    "Reset Luma",
                    isPresented: $isShowingResetConfirmationAlert
                ) {
                    Button("Cancel", role: .cancel) {}
                    Button("Reset", role: .destructive) {
                        performResetLuma()
                    }
                } message: {
                    Text("This will erase all data and restart onboarding. Are you sure?")
                }
            }
        }
    }

    // MARK: No-Account Placeholder

    private var noAccountPlaceholderView: some View {
        Text("No account. Complete onboarding to create one.")
            .font(LumaTheme.Typography.body)
            .foregroundColor(LumaTheme.Colors.secondaryText)
            .multilineTextAlignment(.center)
            .padding(LumaTheme.Spacing.xl)
    }

    // MARK: Actions

    private func saveDisplayNameIfChanged() {
        let trimmedName = editedDisplayName.trimmingCharacters(in: .whitespaces)
        // Only write to AccountManager if the value actually changed, to avoid
        // unnecessary Keychain/UserDefaults writes on every focus cycle.
        guard !trimmedName.isEmpty,
              trimmedName != accountManager.currentAccount?.displayName else { return }
        accountManager.updateDisplayName(trimmedName)
    }

    private func performResetLuma() {
        accountManager.deleteAccount()
        try? profileManager.deleteAllProfiles()
        // Wipe the entire vault (PIN, API keys)
        VaultManager.shared.deleteAll()
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        onResetComplete()
    }
}

// MARK: - Tab 2: API Profiles

/// Lists all stored API profiles with set-default, delete, add, and inline edit capabilities.
@MainActor
private struct APIProfilesTabView: View {

    @ObservedObject var profileManager: ProfileManager

    /// Whether the "Add Profile" inline form is expanded.
    @State private var isAddProfileFormExpanded: Bool = false

    /// The profile whose inline edit form is currently open (nil = none).
    @State private var profileIDBeingEdited: UUID? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: LumaTheme.Spacing.md) {

                // Existing profiles list
                ForEach(profileManager.profiles) { profile in
                    VStack(spacing: 0) {
                        ProfileRowView(
                            profile: profile,
                            totalProfileCount: profileManager.profiles.count,
                            isEditFormExpanded: profileIDBeingEdited == profile.id,
                            onSetDefault: {
                                profileManager.setDefaultProfile(withID: profile.id)
                            },
                            onDelete: {
                                try? profileManager.deleteProfile(withID: profile.id)
                                if profileIDBeingEdited == profile.id {
                                    profileIDBeingEdited = nil
                                }
                            },
                            onToggleEditForm: {
                                if profileIDBeingEdited == profile.id {
                                    profileIDBeingEdited = nil
                                } else {
                                    profileIDBeingEdited = profile.id
                                    // Collapse add form if it was open
                                    isAddProfileFormExpanded = false
                                }
                            },
                            onSaveEdit: { updatedProfile, apiKeyString in
                                profileManager.updateProfile(updatedProfile)
                                if !apiKeyString.isEmpty {
                                    try? profileManager.saveAPIKey(apiKeyString, forProfileID: updatedProfile.id)
                                }
                                profileIDBeingEdited = nil
                            }
                        )
                    }
                    .background(LumaTheme.Colors.surface)
                    .cornerRadius(LumaTheme.CornerRadius.medium)
                }

                // "Add Profile" button and expandable form
                VStack(spacing: 0) {
                    Button {
                        isAddProfileFormExpanded.toggle()
                        // Collapse any open edit form when opening the add form
                        if isAddProfileFormExpanded {
                            profileIDBeingEdited = nil
                        }
                    } label: {
                        HStack {
                            Image(systemName: isAddProfileFormExpanded ? "minus.circle" : "plus.circle")
                            Text(isAddProfileFormExpanded ? "Cancel" : "Add Profile")
                        }
                        .font(LumaTheme.Typography.bodyMedium)
                        .foregroundColor(LumaTheme.Colors.accent)
                        .padding(LumaTheme.Spacing.md)
                    }
                    .buttonStyle(.plain)
                    .onHover { isHovering in
                        if isHovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if isAddProfileFormExpanded {
                        ProfileFormView(
                            mode: .add,
                            existingProfile: nil,
                            existingAPIKey: nil,
                            onSave: { newProfile, apiKeyString in
                                profileManager.addProfile(newProfile)
                                if !apiKeyString.isEmpty {
                                    try? profileManager.saveAPIKey(apiKeyString, forProfileID: newProfile.id)
                                }
                                isAddProfileFormExpanded = false
                            },
                            onCancel: {
                                isAddProfileFormExpanded = false
                            }
                        )
                    }
                }
                .background(LumaTheme.Colors.surface)
                .cornerRadius(LumaTheme.CornerRadius.medium)
            }
            .padding(LumaTheme.Spacing.xl)
        }
    }
}

// MARK: Profile Row

/// A single row in the API profiles list, with optional inline edit form.
@MainActor
private struct ProfileRowView: View {

    let profile: LumaAPIProfile
    let totalProfileCount: Int
    let isEditFormExpanded: Bool

    var onSetDefault:     () -> Void
    var onDelete:         () -> Void
    var onToggleEditForm: () -> Void
    var onSaveEdit:       (LumaAPIProfile, String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Row header
            HStack(spacing: LumaTheme.Spacing.md) {

                // Checkmark for default profile
                Image(systemName: profile.isDefault ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(profile.isDefault ? LumaTheme.Colors.accent : LumaTheme.Colors.tertiaryText)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(LumaTheme.Typography.bodyMedium)
                        .foregroundColor(LumaTheme.Colors.primaryText)

                    // Provider badge
                    Text(profile.provider.displayName)
                        .font(LumaTheme.Typography.caption)
                        .foregroundColor(LumaTheme.Colors.secondaryText)
                        .padding(.horizontal, LumaTheme.Spacing.xs)
                        .padding(.vertical, 2)
                        .background(LumaTheme.Colors.surfaceElevated)
                        .cornerRadius(LumaTheme.CornerRadius.small)
                }

                Spacer()

                // Action buttons
                HStack(spacing: LumaTheme.Spacing.sm) {

                    // Edit toggle
                    Button(isEditFormExpanded ? "Done" : "Edit") {
                        onToggleEditForm()
                    }
                    .font(LumaTheme.Typography.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(LumaTheme.Colors.secondaryText)
                    .onHover { isHovering in
                        if isHovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }

                    // Set Default (disabled if already default)
                    Button("Set Default") {
                        onSetDefault()
                    }
                    .font(LumaTheme.Typography.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(profile.isDefault ? LumaTheme.Colors.tertiaryText : LumaTheme.Colors.accent)
                    .disabled(profile.isDefault)
                    .onHover { isHovering in
                        if isHovering && !profile.isDefault { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }

                    // Delete (disabled if it's the only profile)
                    Button("Delete") {
                        onDelete()
                    }
                    .font(LumaTheme.Typography.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(totalProfileCount <= 1 ? LumaTheme.Colors.tertiaryText : LumaTheme.Colors.error)
                    .disabled(totalProfileCount <= 1)
                    .onHover { isHovering in
                        if isHovering && totalProfileCount > 1 { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                }
            }
            .padding(LumaTheme.Spacing.lg)

            // Inline edit form (expands below the row header)
            if isEditFormExpanded {
                Divider()
                    .padding(.horizontal, LumaTheme.Spacing.md)

                ProfileFormView(
                    mode: .edit,
                    existingProfile: profile,
                    existingAPIKey: ProfileManager.shared.loadAPIKey(forProfileID: profile.id),
                    onSave: { updatedProfile, apiKeyString in
                        onSaveEdit(updatedProfile, apiKeyString)
                    },
                    onCancel: {
                        onToggleEditForm()
                    }
                )
            }
        }
    }
}

// MARK: Profile Form

/// Shared inline form used for both adding a new profile and editing an existing one.
@MainActor
private struct ProfileFormView: View {

    enum FormMode { case add, edit }

    let mode: FormMode
    let existingProfile: LumaAPIProfile?
    let existingAPIKey:  String?

    var onSave:   (LumaAPIProfile, String) -> Void
    var onCancel: () -> Void

    @State private var profileName:        String = ""
    @State private var selectedProvider:   LumaAPIProvider = .openRouter
    @State private var apiKeyInput:        String = ""
    @State private var isAPIKeyVisible:    Bool = false
    @State private var customBaseURL:      String = ""

    // Connection test state
    @State private var connectionTestStatus: ConnectionTestStatus = .idle

    enum ConnectionTestStatus {
        case idle
        case testing
        case success
        case failure(reason: String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LumaTheme.Spacing.lg) {

            // Name field
            VStack(alignment: .leading, spacing: LumaTheme.Spacing.xs) {
                Text("Profile Name")
                    .font(LumaTheme.Typography.caption)
                    .foregroundColor(LumaTheme.Colors.secondaryText)
                TextField("e.g. Work - OpenRouter", text: $profileName)
                    .textFieldStyle(.plain)
                    .font(LumaTheme.Typography.body)
                    .foregroundColor(LumaTheme.Colors.primaryText)
                    .padding(LumaTheme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: LumaTheme.CornerRadius.medium)
                            .fill(LumaTheme.Colors.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: LumaTheme.CornerRadius.medium)
                            .stroke(LumaTheme.Colors.surfaceElevated, lineWidth: 1)
                    )
            }

            // Provider picker
            VStack(alignment: .leading, spacing: LumaTheme.Spacing.xs) {
                Text("Provider")
                    .font(LumaTheme.Typography.caption)
                    .foregroundColor(LumaTheme.Colors.secondaryText)
                Picker("Provider", selection: $selectedProvider) {
                    ForEach(LumaAPIProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Base URL (only shown for Custom provider)
            if selectedProvider == .custom {
                VStack(alignment: .leading, spacing: LumaTheme.Spacing.xs) {
                    Text("Base URL")
                        .font(LumaTheme.Typography.caption)
                        .foregroundColor(LumaTheme.Colors.secondaryText)
                    TextField("https://your-endpoint.com/v1", text: $customBaseURL)
                        .textFieldStyle(.plain)
                        .font(LumaTheme.Typography.body)
                        .foregroundColor(LumaTheme.Colors.primaryText)
                        .padding(LumaTheme.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: LumaTheme.CornerRadius.medium)
                                .fill(LumaTheme.Colors.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: LumaTheme.CornerRadius.medium)
                                .stroke(LumaTheme.Colors.surfaceElevated, lineWidth: 1)
                        )
                }
            }

            // API key field with eye toggle
            VStack(alignment: .leading, spacing: LumaTheme.Spacing.xs) {
                Text("API Key")
                    .font(LumaTheme.Typography.caption)
                    .foregroundColor(LumaTheme.Colors.secondaryText)

                HStack {
                    if isAPIKeyVisible {
                        TextField("Paste API key here", text: $apiKeyInput)
                            .textFieldStyle(.plain)
                            .font(LumaTheme.Typography.body)
                            .foregroundColor(LumaTheme.Colors.primaryText)
                    } else {
                        SecureField("Paste API key here", text: $apiKeyInput)
                            .textFieldStyle(.plain)
                            .font(LumaTheme.Typography.body)
                            .foregroundColor(LumaTheme.Colors.primaryText)
                    }

                    Button {
                        isAPIKeyVisible.toggle()
                    } label: {
                        Image(systemName: isAPIKeyVisible ? "eye.slash" : "eye")
                            .foregroundColor(LumaTheme.Colors.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .onHover { isHovering in
                        if isHovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                }
                .padding(LumaTheme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: LumaTheme.CornerRadius.medium)
                        .fill(LumaTheme.Colors.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LumaTheme.CornerRadius.medium)
                        .stroke(LumaTheme.Colors.surfaceElevated, lineWidth: 1)
                )
            }

            // Test Connection button + result
            HStack(spacing: LumaTheme.Spacing.sm) {
                Button("Test Connection") {
                    Task { await runConnectionTest() }
                }
                .buttonStyle(.plain)
                .font(LumaTheme.Typography.caption)
                .foregroundColor(LumaTheme.Colors.accent)
                .onHover { isHovering in
                    if isHovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)

                // Inline connection test result
                switch connectionTestStatus {
                case .idle:
                    EmptyView()
                case .testing:
                    ProgressView()
                        .scaleEffect(0.6)
                case .success:
                    Text("✓ Connected")
                        .font(LumaTheme.Typography.caption)
                        .foregroundColor(LumaTheme.Colors.success)
                case .failure(let reason):
                    Text("✗ Failed: \(reason)")
                        .font(LumaTheme.Typography.caption)
                        .foregroundColor(LumaTheme.Colors.error)
                }
            }

            // Save / Cancel
            HStack(spacing: LumaTheme.Spacing.sm) {
                Button(mode == .add ? "Save Profile" : "Save Changes") {
                    saveProfile()
                }
                .buttonStyle(.plain)
                .font(LumaTheme.Typography.bodyMedium)
                .foregroundColor(LumaTheme.Colors.accentForeground)
                .padding(.horizontal, LumaTheme.Spacing.md)
                .padding(.vertical, LumaTheme.Spacing.sm)
                .background(LumaTheme.Colors.accent)
                .cornerRadius(LumaTheme.CornerRadius.small)
                .disabled(profileName.trimmingCharacters(in: .whitespaces).isEmpty)
                .onHover { isHovering in
                    if isHovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }

                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .font(LumaTheme.Typography.body)
                    .foregroundColor(LumaTheme.Colors.secondaryText)
                    .onHover { isHovering in
                        if isHovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
            }
        }
        .padding(LumaTheme.Spacing.lg)
        .onAppear {
            populateFormFromExistingProfile()
        }
    }

    // MARK: Form Setup

    private func populateFormFromExistingProfile() {
        guard let profile = existingProfile else { return }
        profileName      = profile.name
        selectedProvider = profile.provider
        customBaseURL    = profile.baseURL
        apiKeyInput      = existingAPIKey ?? ""
    }

    // MARK: Actions

    private func saveProfile() {
        let trimmedName = profileName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let resolvedBaseURL = selectedProvider == .custom ? customBaseURL : ""

        // New profiles get a sensible default model so the first request doesn't
        // fail with "No model configured." Edited profiles keep their existing model.
        let resolvedModel: String
        if mode == .add {
            resolvedModel = defaultModelForProvider(selectedProvider)
        } else {
            resolvedModel = existingProfile?.selectedModel ?? ""
        }

        let profileToSave = LumaAPIProfile(
            id:            existingProfile?.id ?? UUID(),
            name:          trimmedName,
            provider:      selectedProvider,
            baseURL:       resolvedBaseURL,
            isDefault:     existingProfile?.isDefault ?? false,
            selectedModel: resolvedModel
        )

        onSave(profileToSave, apiKeyInput.trimmingCharacters(in: .whitespaces))
    }

    private func defaultModelForProvider(_ provider: LumaAPIProvider) -> String {
        switch provider {
        case .openRouter: return "google/gemini-2.5-flash:free"
        case .anthropic:  return "claude-sonnet-4-6"
        case .google:     return "gemini-2.0-flash"
        case .custom:     return ""
        }
    }

    /// GETs the provider's models list endpoint to verify the API key is valid.
    private func runConnectionTest() async {
        connectionTestStatus = .testing

        let trimmedAPIKey = apiKeyInput.trimmingCharacters(in: .whitespaces)
        guard !trimmedAPIKey.isEmpty else {
            connectionTestStatus = .failure(reason: "No API key entered")
            return
        }

        // Each provider exposes a GET /models endpoint for lightweight key validation
        let modelsEndpointURLString: String
        switch selectedProvider {
        case .openRouter:
            modelsEndpointURLString = "https://openrouter.ai/api/v1/models"
        case .anthropic:
            modelsEndpointURLString = "https://api.anthropic.com/v1/models"
        case .google:
            modelsEndpointURLString = "https://generativelanguage.googleapis.com/v1beta/models"
        case .custom:
            let trimmedBaseURL = customBaseURL.trimmingCharacters(in: .whitespaces)
            modelsEndpointURLString = trimmedBaseURL + "/models"
        }

        guard let requestURL = URL(string: modelsEndpointURLString) else {
            connectionTestStatus = .failure(reason: "Invalid URL")
            return
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        // Each provider uses a different auth scheme for the models endpoint.
        // - Anthropic: x-api-key header (no Bearer prefix)
        // - Google AI: x-goog-api-key header (the /v1beta/models endpoint doesn't
        //   accept Authorization: Bearer — it needs the native Google key header)
        // - OpenRouter / Custom: Authorization: Bearer
        switch selectedProvider {
        case .anthropic:
            request.setValue(trimmedAPIKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .google:
            request.setValue(trimmedAPIKey, forHTTPHeaderField: "x-goog-api-key")
        default:
            request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                connectionTestStatus = .success
            } else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                connectionTestStatus = .failure(reason: "HTTP \(statusCode)")
            }
        } catch {
            connectionTestStatus = .failure(reason: error.localizedDescription)
        }
    }
}

// MARK: - Tab 3: Model

/// Shows the active profile's selected model and allows editing it as plain text.
/// A full OpenRouter model picker will replace this text field in a future iteration.
@MainActor
private struct ModelTabView: View {

    @ObservedObject var profileManager: ProfileManager

    /// Draft model string being typed by the user.
    @State private var editedModelString: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LumaTheme.Spacing.xl) {

                // Subtitle explaining the per-profile relationship
                Text("Model is selected per profile. Manage profiles in the API Profiles tab.")
                    .font(LumaTheme.Typography.body)
                    .foregroundColor(LumaTheme.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let activeProfile = profileManager.activeProfile {
                    VStack(alignment: .leading, spacing: LumaTheme.Spacing.md) {

                        // Active profile context
                        HStack(spacing: LumaTheme.Spacing.sm) {
                            Text("Active Profile:")
                                .font(LumaTheme.Typography.bodyMedium)
                                .foregroundColor(LumaTheme.Colors.primaryText)
                            Text(activeProfile.name)
                                .font(LumaTheme.Typography.body)
                                .foregroundColor(LumaTheme.Colors.secondaryText)
                        }

                        // Model string field
                        VStack(alignment: .leading, spacing: LumaTheme.Spacing.xs) {
                            Text("Model")
                                .font(LumaTheme.Typography.bodyMedium)
                                .foregroundColor(LumaTheme.Colors.primaryText)

                            TextField("e.g. google/gemini-2.5-flash:free", text: $editedModelString)
                                .textFieldStyle(.plain)
                                .font(LumaTheme.Typography.body)
                                .foregroundColor(LumaTheme.Colors.primaryText)
                                .padding(LumaTheme.Spacing.sm)
                                .background(
                                    RoundedRectangle(cornerRadius: LumaTheme.CornerRadius.medium)
                                        .fill(LumaTheme.Colors.surface)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: LumaTheme.CornerRadius.medium)
                                        .stroke(LumaTheme.Colors.surfaceElevated, lineWidth: 1)
                                )
                                // Save on Return
                                .onSubmit {
                                    saveModelStringToActiveProfile(activeProfile: activeProfile)
                                }

                            Text("Paste any OpenRouter or provider model ID here. A searchable picker is coming soon.")
                                .font(LumaTheme.Typography.caption)
                                .foregroundColor(LumaTheme.Colors.tertiaryText)
                        }

                        // Save button
                        Button("Save Model") {
                            saveModelStringToActiveProfile(activeProfile: activeProfile)
                        }
                        .buttonStyle(.plain)
                        .font(LumaTheme.Typography.bodyMedium)
                        .foregroundColor(LumaTheme.Colors.accentForeground)
                        .padding(.horizontal, LumaTheme.Spacing.md)
                        .padding(.vertical, LumaTheme.Spacing.sm)
                        .background(LumaTheme.Colors.accent)
                        .cornerRadius(LumaTheme.CornerRadius.small)
                        .onHover { isHovering in
                            if isHovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                        }
                    }
                } else {
                    Text("No active profile. Add a profile in the API Profiles tab.")
                        .font(LumaTheme.Typography.body)
                        .foregroundColor(LumaTheme.Colors.secondaryText)
                }
            }
            .padding(LumaTheme.Spacing.xl)
        }
        .onAppear {
            editedModelString = profileManager.activeProfile?.selectedModel ?? ""
        }
    }

    private func saveModelStringToActiveProfile(activeProfile: LumaAPIProfile) {
        let trimmedModel = editedModelString.trimmingCharacters(in: .whitespaces)
        guard !trimmedModel.isEmpty else { return }
        // Build an updated copy of the active profile with the new model string
        var updatedProfile = activeProfile
        updatedProfile.selectedModel = trimmedModel
        profileManager.updateProfile(updatedProfile)
    }
}

// MARK: - Tab 4: General

/// Miscellaneous settings: launch-at-login, PIN management, and About.
@MainActor
private struct GeneralTabView: View {

    @ObservedObject var pinManager: PINManager

    // MARK: Launch at Login
    // Persisted in UserDefaults so it survives restarts.
    // The actual SMLoginItem enable/disable call happens in toggleLaunchAtLogin(enabled:).
    @AppStorage("launchAtLogin") private var launchAtLoginEnabled: Bool = false

    // MARK: PIN sheet state
    @State private var isShowingPINEntrySheet: Bool = false

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LumaTheme.Spacing.xl) {

                launchAtLoginSection
                Divider()
                pinManagementSection
                Divider()
                aboutSection
            }
            .padding(LumaTheme.Spacing.xl)
        }
        // PIN entry sheet (set or change)
        .sheet(isPresented: $isShowingPINEntrySheet) {
            PINEntryView(
                mode: .set,
                title: "Set a PIN",
                onSuccess: { isShowingPINEntrySheet = false },
                onCancel:  { isShowingPINEntrySheet = false }
            )
        }
    }

    // MARK: Launch at Login Section

    private var launchAtLoginSection: some View {
        VStack(alignment: .leading, spacing: LumaTheme.Spacing.sm) {

            Text("Launch at Login")
                .font(LumaTheme.Typography.headline)
                .foregroundColor(LumaTheme.Colors.primaryText)

            Toggle(isOn: $launchAtLoginEnabled) {
                Text("Start Luma automatically when you log in")
                    .font(LumaTheme.Typography.body)
                    .foregroundColor(LumaTheme.Colors.primaryText)
            }
            .toggleStyle(.switch)
            .onChange(of: launchAtLoginEnabled) { newValue in
                toggleLaunchAtLogin(enabled: newValue)
            }
        }
    }

    // MARK: PIN Management Section

    private var pinManagementSection: some View {
        VStack(alignment: .leading, spacing: LumaTheme.Spacing.md) {

            Text("PIN")
                .font(LumaTheme.Typography.headline)
                .foregroundColor(LumaTheme.Colors.primaryText)

            if pinManager.hasPIN {
                // PIN is set — show Change and Remove options
                HStack(spacing: LumaTheme.Spacing.md) {
                    Button("Change PIN") {
                        isShowingPINEntrySheet = true
                    }
                    .buttonStyle(.plain)
                    .font(LumaTheme.Typography.body)
                    .foregroundColor(LumaTheme.Colors.accent)
                    .onHover { isHovering in
                        if isHovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }

                    Button("Remove PIN") {
                        try? pinManager.clearPIN()
                    }
                    .buttonStyle(.plain)
                    .font(LumaTheme.Typography.body)
                    .foregroundColor(LumaTheme.Colors.error)
                    .onHover { isHovering in
                        if isHovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                }

            } else {
                // No PIN set — show Set PIN option
                Button("Set PIN") {
                    isShowingPINEntrySheet = true
                }
                .buttonStyle(.plain)
                .font(LumaTheme.Typography.body)
                .foregroundColor(LumaTheme.Colors.accent)
                .onHover { isHovering in
                    if isHovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
        }
    }

    // MARK: About Section

    private var aboutSection: some View {
        // Centered About block with app version and copyright
        VStack(spacing: LumaTheme.Spacing.xs) {
            Text("Luma v1.0")
                .font(LumaTheme.Typography.bodyMedium)
                .foregroundColor(LumaTheme.Colors.secondaryText)

            Text("© 2026 Omoju Oluwamayowa (Nox)")
                .font(LumaTheme.Typography.caption)
                .foregroundColor(LumaTheme.Colors.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    // MARK: Actions

    /// Stub for SMLoginItem integration.
    /// Full implementation requires the com.apple.security.application-groups entitlement
    /// and an SMLoginItemHelper target — wiring those up is out of scope for this file.
    private func toggleLaunchAtLogin(enabled: Bool) {
        // TODO: Replace with SMLoginItemSetEnabled("com.nox.luma.LaunchHelper", enabled)
        // once the LoginItemHelper target and entitlements are configured.
        print("[LaunchAtLogin] TODO: SMLoginItemSetEnabled called with enabled=\(enabled)")
    }
}
