//
//  TaskPlanner.swift
//  leanring-buddy
//
//  Uses the AI (via APIClient) to break a user's learning goal into an ordered
//  list of WalkthroughSteps. Sends a structured JSON prompt and parses the response
//  into a WalkthroughPlan. Retries once if the first parse attempt fails.
//

import Foundation

// MARK: - TaskPlanner

@MainActor
final class TaskPlanner {

    // We only retry once — a second failure usually means the model genuinely can't
    // produce valid JSON for this goal, and retrying indefinitely would frustrate the user.
    private let maximumRetryAttempts: Int = 1

    // MARK: - Public API

    /// Takes a user goal and the name of the frontmost app, asks the AI to break
    /// the goal into ordered steps, and returns the parsed WalkthroughPlan.
    /// Throws if the AI returns invalid JSON after the retry.
    func planSteps(goal: String, frontmostAppName: String) async throws -> WalkthroughPlan {
        var lastParseError: Error?

        for attemptNumber in 0...maximumRetryAttempts {
            if attemptNumber > 0 {
                print("[Luma] TaskPlanner: retrying step generation (attempt \(attemptNumber + 1))")
            }

            do {
                let rawAIResponseText = try await requestStepsFromAI(
                    goal: goal,
                    frontmostAppName: frontmostAppName
                )
                let parsedPlan = try parsePlanFromJSON(rawAIResponseText)
                return parsedPlan
            } catch {
                lastParseError = error
                print("[Luma] TaskPlanner: parse failed on attempt \(attemptNumber + 1): \(error.localizedDescription)")
            }
        }

        throw lastParseError ?? NSError(
            domain: "TaskPlanner",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Failed to generate walkthrough plan after \(maximumRetryAttempts + 1) attempts."]
        )
    }

    // MARK: - AI Request

    /// Sends the goal and current app name to the AI with a structured prompt
    /// that requests a JSON WalkthroughPlan. Returns the raw response string.
    private func requestStepsFromAI(goal: String, frontmostAppName: String) async throws -> String {
        // The system prompt is carefully worded to get strict JSON output only.
        // elementName must be the EXACT text visible on screen so the AX search
        // can match it via substring comparison.
        let stepGenerationSystemPrompt = """
        You are a macOS task planner. Break the user's goal into clear, ordered steps.

        Return ONLY valid JSON in this exact format — no markdown, no explanation:
        {
          "totalSteps": <number>,
          "steps": [
            {
              "index": <0-based number>,
              "instruction": "<exact words to say to the user>",
              "elementName": "<shortest label that uniquely identifies this UI element in the AX tree>",
              "elementRole": "<AXButton | AXMenuItem | AXMenuBarItem | AXTextField | null>",
              "appBundleID": "<com.apple.finder etc., or null if not app-specific>",
              "isMenuBar": <true if the element is in the macOS menu bar, otherwise false>,
              "timeoutSeconds": 15
            }
          ]
        }

        Rules:
        - elementName must match the AX accessibility label exactly — use the shortest label that is unique (e.g. "Compress" not "Compress 'Downloads'"). macOS AX titles strip contextual suffixes.
        - For context menu interactions, split into two steps: (1) right-click the item (elementName = the file/folder name, instruction = "Right-click <name>"), then (2) select from the menu (elementName = the menu item label, isMenuBar = false).
        - For Finder: use appBundleID "com.apple.finder"
        - For menu bar system items (battery, wifi, clock, Control Center): set isMenuBar to true and appBundleID to "com.apple.controlcenter"
        - For app menu items (File, Edit, View menus): set isMenuBar to true, appBundleID to that app's bundle ID
        - For Control Center: appBundleID "com.apple.controlcenter"
        - If a step has no specific element (e.g. "press a key"), use elementName ""
        """

        let userMessage = "Goal: \(goal)\nCurrent frontmost app: \(frontmostAppName)\n\nReturn the JSON plan."

        // Use non-streaming analyzeImage with an empty images array — step planning is text-only.
        // We need the full response before we can parse the JSON.
        let (responseText, _) = try await APIClient.shared.analyzeImage(
            images: [],
            systemPrompt: stepGenerationSystemPrompt,
            conversationHistory: [],
            userPrompt: userMessage
        )

        return responseText
    }

    // MARK: - JSON Parsing

    /// Extracts and decodes the WalkthroughPlan from the AI's response.
    /// Locates the outermost { } object to handle any surrounding prose the AI might add.
    private func parsePlanFromJSON(_ rawJSONString: String) throws -> WalkthroughPlan {
        // Find the bounds of the JSON object. The AI occasionally adds surrounding
        // sentences despite the prompt, so we extract just the object portion.
        guard let objectStartIndex = rawJSONString.firstIndex(of: "{"),
              let objectEndIndex = rawJSONString.lastIndex(of: "}")
        else {
            throw NSError(
                domain: "TaskPlanner",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "AI response did not contain a JSON object. Raw: \(rawJSONString)"]
            )
        }

        let jsonSubstring = String(rawJSONString[objectStartIndex...objectEndIndex])

        guard let jsonData = jsonSubstring.data(using: .utf8) else {
            throw NSError(
                domain: "TaskPlanner",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Could not encode extracted JSON as UTF-8 data."]
            )
        }

        do {
            let decoder = JSONDecoder()
            let decodedPlan = try decoder.decode(WalkthroughPlan.self, from: jsonData)
            print("[Luma] TaskPlanner: parsed \(decodedPlan.steps.count) step(s) from AI response")
            return decodedPlan
        } catch {
            throw NSError(
                domain: "TaskPlanner",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "JSON decode failed: \(error.localizedDescription). Raw JSON: \(jsonSubstring)"]
            )
        }
    }
}
