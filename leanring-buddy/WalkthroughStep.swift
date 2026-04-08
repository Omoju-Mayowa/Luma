//
//  WalkthroughStep.swift
//  leanring-buddy
//
//  Data models for the WalkthroughEngine system. Defines a single step in
//  a guided walkthrough and the state machine that drives the overall flow.
//

import Foundation

/// A single step in a guided walkthrough.
/// Each step tells the user what to do (instruction), optionally specifies
/// what accessibility element to watch for, what action to expect, and
/// which app the action should happen in.
struct WalkthroughStep: Codable, Identifiable {
    let id: UUID
    let stepIndex: Int
    let instruction: String          // What to tell the user (spoken + displayed)
    let expectedElement: String?     // Accessibility element title/role to watch (optional)
    let expectedAction: String?      // "click" | "focus" | "valueChange" | "open"
    let appBundleID: String?         // Which app this step happens in (optional)
    let timeoutSeconds: Int          // How long before a nudge fires (default 30)

    init(
        stepIndex: Int,
        instruction: String,
        expectedElement: String? = nil,
        expectedAction: String? = nil,
        appBundleID: String? = nil,
        timeoutSeconds: Int = 30
    ) {
        self.id = UUID()
        self.stepIndex = stepIndex
        self.instruction = instruction
        self.expectedElement = expectedElement
        self.expectedAction = expectedAction
        self.appBundleID = appBundleID
        self.timeoutSeconds = timeoutSeconds
    }

    // MARK: - Codable Support

    // Custom coding keys map the JSON field names from the AI response to Swift property names.
    // The AI returns camelCase keys that match directly, but we need to handle the UUID
    // specially since the AI doesn't generate UUIDs — we assign them during init.
    enum CodingKeys: String, CodingKey {
        case id
        case stepIndex
        case instruction
        case expectedElement
        case expectedAction
        case appBundleID
        case timeoutSeconds
    }

    // Custom decoder that generates a new UUID when decoding from AI JSON,
    // since the AI response won't include a UUID field.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.stepIndex = try container.decode(Int.self, forKey: .stepIndex)
        self.instruction = try container.decode(String.self, forKey: .instruction)
        self.expectedElement = try container.decodeIfPresent(String.self, forKey: .expectedElement)
        self.expectedAction = try container.decodeIfPresent(String.self, forKey: .expectedAction)
        self.appBundleID = try container.decodeIfPresent(String.self, forKey: .appBundleID)
        self.timeoutSeconds = (try? container.decode(Int.self, forKey: .timeoutSeconds)) ?? 30
    }
}

/// The state machine that drives the WalkthroughEngine.
/// Each case represents a distinct phase of the walkthrough lifecycle.
enum WalkthroughState {
    /// Not in walkthrough mode — the engine is waiting for activation.
    case idle

    /// The AI is generating steps for the user's goal.
    case planning(goal: String)

    /// The AI has returned steps; waiting for the user to confirm before starting.
    case confirming(goal: String, steps: [WalkthroughStep])

    /// The walkthrough is in progress. currentIndex is the zero-based step currently active.
    case active(goal: String, steps: [WalkthroughStep], currentIndex: Int)

    /// All steps have been completed successfully.
    case complete(goal: String)
}
