//
//  CustomCursorManager.swift
//  leanring-buddy
//
//  Manages a custom NSCursor loaded from the "Luma-cursor" asset in Assets.xcassets.
//  When enabled, this replaces the system arrow cursor with the Luma branded cursor
//  while the user interacts with the app. Persists the user's preference to UserDefaults.
//

import AppKit
import Combine

@MainActor
final class CustomCursorManager {

    // Shared singleton — one manager for the whole app lifetime.
    static let shared = CustomCursorManager()

    // MARK: - Constants

    /// UserDefaults key used to persist whether the custom cursor is enabled.
    private static let userDefaultsKeyForCustomCursorEnabled = "isCustomCursorEnabled"

    /// The hotspot for the Luma cursor is at the very top-left corner of the image,
    /// which visually aligns with where the cursor tip sits in the artwork.
    private static let cursorHotspot = CGPoint(x: 0, y: 0)

    // MARK: - Published State

    /// Whether the custom Luma cursor is currently enabled.
    /// Changes here are persisted to UserDefaults and immediately reflected in the active cursor.
    @Published var isCustomCursorEnabled: Bool

    // MARK: - Private State

    /// The loaded NSCursor built from the "Luma-cursor" image asset.
    /// Will be nil if the asset doesn't exist in the bundle — in that case we silently
    /// fall back to the system arrow cursor rather than crashing.
    private var lumaCursor: NSCursor?

    // MARK: - Initialization

    private init() {
        // Determine the initial value for isCustomCursorEnabled.
        // If the key has never been written (first launch), default to true so the
        // custom cursor is on by default. Only respect an explicit false if set.
        let hasStoredPreference = UserDefaults.standard.object(forKey: Self.userDefaultsKeyForCustomCursorEnabled) != nil
        if hasStoredPreference {
            self.isCustomCursorEnabled = UserDefaults.standard.bool(forKey: Self.userDefaultsKeyForCustomCursorEnabled)
        } else {
            // First launch — enable by default and store that decision.
            self.isCustomCursorEnabled = true
            UserDefaults.standard.set(true, forKey: Self.userDefaultsKeyForCustomCursorEnabled)
        }

        // Attempt to load the Luma cursor image from the app's asset catalog.
        // If the named image doesn't exist we print a warning and leave lumaCursor nil.
        // All downstream callers check for nil before applying the cursor, so the app
        // continues to work normally with the default system arrow.
        if let cursorImage = NSImage(named: "Luma-cursor") {
            self.lumaCursor = NSCursor(image: cursorImage, hotSpot: Self.cursorHotspot)
        } else {
            print("[CustomCursorManager] WARNING: 'Luma-cursor' image asset not found in bundle. The system arrow cursor will be used as fallback.")
            self.lumaCursor = nil
        }
    }

    // MARK: - Public API

    /// Activates the Luma branded cursor as the current NSCursor.
    ///
    /// This is a no-op when:
    /// - The user has disabled the custom cursor (isCustomCursorEnabled == false)
    /// - The cursor image asset failed to load at startup (lumaCursor == nil)
    func activateCustomCursor() {
        guard isCustomCursorEnabled else {
            // User turned off the custom cursor — respect that preference silently.
            return
        }
        guard let lumaCursor = lumaCursor else {
            // Asset was missing at launch — already warned at init time, skip silently.
            return
        }
        lumaCursor.set()
    }

    /// Restores the operating system's default arrow cursor.
    ///
    /// Call this whenever Luma is done overriding the cursor (e.g., when the user
    /// moves out of a tracked area or disables the custom cursor in settings).
    func restoreSystemCursor() {
        NSCursor.arrow.set()
    }

    /// Updates the user's custom-cursor preference, persists it to UserDefaults,
    /// and immediately applies the change to the on-screen cursor.
    ///
    /// - Parameter enabled: Pass `true` to enable the Luma cursor, `false` to revert
    ///   to the macOS system arrow cursor.
    func setCustomCursorEnabled(_ enabled: Bool) {
        isCustomCursorEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.userDefaultsKeyForCustomCursorEnabled)

        if enabled {
            activateCustomCursor()
        } else {
            restoreSystemCursor()
        }
    }
}
