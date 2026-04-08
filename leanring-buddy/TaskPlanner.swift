//
//  TaskPlanner.swift
//  leanring-buddy
//
//  Uses the AI (via APIClient) to break a user's learning goal into an ordered
//  list of WalkthroughSteps. Sends a structured JSON prompt and parses the
//  response. Retries once if the first parse attempt fails due to malformed JSON.
//

import Foundation

// MARK: - TaskPlanner

@MainActor
final class TaskPlanner {

    // Named constant for the retry limit — we only retry once because a second
    // failure usually means the model genuinely can't handle the goal, and
    // retrying indefinitely would frustrate the user with a long wait.
    private let maximumRetryAttempts: Int = 1

    // MARK: - Public API

    /// Takes a user goal description and the name of the currently active app,
    /// asks the AI to break the goal into ordered steps, and returns the parsed steps.
    /// Throws if the AI returns invalid JSON after the retry.
    func planSteps(goal: String, frontmostAppName: String) async throws -> [WalkthroughStep] {
        var lastParseError: Error?

        for attemptNumber in 0...maximumRetryAttempts {
            if attemptNumber > 0 {
                print("TaskPlanner: retrying step generation (attempt \(attemptNumber + 1)) after parse failure")
            }

            do {
                let rawAIResponseText = try await requestStepsFromAI(
                    goal: goal,
                    frontmostAppName: frontmostAppName
                )
                let parsedSteps = try parseStepsFromJSON(rawAIResponseText)
                return parsedSteps
            } catch {
                lastParseError = error
                print("TaskPlanner: step parse failed on attempt \(attemptNumber + 1): \(error.localizedDescription)")
            }
        }

        // All attempts exhausted — surface the last error
        throw lastParseError ?? NSError(
            domain: "TaskPlanner",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Failed to generate walkthrough steps after \(maximumRetryAttempts + 1) attempts."]
        )
    }

    // MARK: - AI Request

    /// Sends the goal and current app name to the AI with a structured prompt
    /// that requests a JSON array of steps. Returns the raw response string.
    private func requestStepsFromAI(goal: String, frontmostAppName: String) async throws -> String {
        // The system prompt is carefully worded to get the AI to output ONLY valid JSON
        // with no markdown fences, no explanation — just the raw array. This is important
        // because parseStepsFromJSON uses substring extraction which breaks if there's extra text.
        let stepGenerationSystemPrompt = """
        You are a step-by-step computer task planner. The user wants to learn how to do something on their Mac. Break their goal into clear, ordered steps.

        Return ONLY a valid JSON array. No markdown, no explanation, just the JSON array. Each step:
        {
          "stepIndex": <number starting at 0>,
          "instruction": "<clear instruction for what the user should do>",
          "expectedElement": "<accessibility element title or role, optional — omit if not applicable>",
          "expectedAction": "<click|focus|valueChange|open, optional — omit if not applicable>",
          "appBundleID": "<bundle ID if step happens in specific app, optional — omit if not applicable>",
          "timeoutSeconds": <number, default 30>
        }
        """

        let userMessage = "Goal: \(goal)\nCurrent app: \(frontmostAppName)\n\nReturn the JSON array of steps."

        // We use the non-streaming analyzeImage method here because we need the full
        // response before we can parse the JSON — partial JSON is not parseable.
        // images array is empty because step planning is text-only (no screenshot needed).
        let (responseText, _) = try await APIClient.shared.analyzeImage(
            images: [],
            systemPrompt: stepGenerationSystemPrompt,
            conversationHistory: [],
            userPrompt: userMessage
        )

        return responseText
    }

    // MARK: - JSON Parsing

    /// Extracts and decodes the JSON array of steps from the AI's response string.
    /// Finds the first `[` and last `]` to handle cases where the AI includes
    /// minor surrounding text despite the prompt instructions.
    private func parseStepsFromJSON(_ rawJSONString: String) throws -> [WalkthroughStep] {
        // Find the bounds of the JSON array in the response.
        // The AI occasionally wraps the JSON in a sentence like "Here are your steps: [...]"
        // even when instructed not to, so we extract just the array portion.
        guard let arrayStartIndex = rawJSONString.firstIndex(of: "["),
              let arrayEndIndex = rawJSONString.lastIndex(of: "]")
        else {
            throw NSError(
                domain: "TaskPlanner",
                code: -2,
                userInfo: [
                    NSLocalizedDescriptionKey: "AI response did not contain a JSON array. Raw response: \(rawJSONString)"
                ]
            )
        }

        // Extract the JSON substring from the first "[" to the last "]" (inclusive)
        let jsonSubstring = String(rawJSONString[arrayStartIndex...arrayEndIndex])

        guard let jsonData = jsonSubstring.data(using: .utf8) else {
            throw NSError(
                domain: "TaskPlanner",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Could not encode extracted JSON substring as UTF-8 data."]
            )
        }

        do {
            let decoder = JSONDecoder()
            let decodedSteps = try decoder.decode([WalkthroughStep].self, from: jsonData)
            return decodedSteps
        } catch {
            throw NSError(
                domain: "TaskPlanner",
                code: -4,
                userInfo: [
                    NSLocalizedDescriptionKey: "JSON decode failed: \(error.localizedDescription). Raw JSON: \(jsonSubstring)"
                ]
            )
        }
    }
}
