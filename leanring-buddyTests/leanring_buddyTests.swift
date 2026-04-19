//
//  leanring_buddyTests.swift
//  leanring-buddyTests
//
//  Created by thorfinn on 3/2/26.
//

import Testing
@testable import leanring_buddy

struct leanring_buddyTests {

    @Test func firstPermissionRequestUsesSystemPromptOnly() async throws {
        let presentationDestination = WindowPositionManager.permissionRequestPresentationDestination(
            hasPermissionNow: false,
            hasAttemptedSystemPrompt: false
        )

        #expect(presentationDestination == .systemPrompt)
    }

    @Test func repeatedPermissionRequestOpensSystemSettings() async throws {
        let presentationDestination = WindowPositionManager.permissionRequestPresentationDestination(
            hasPermissionNow: false,
            hasAttemptedSystemPrompt: true
        )

        #expect(presentationDestination == .systemSettings)
    }

    @Test func knownGrantedScreenRecordingPermissionSkipsTheGate() async throws {
        let shouldTreatPermissionAsGranted = WindowPositionManager.shouldTreatScreenRecordingPermissionAsGrantedForSessionLaunch(
            hasScreenRecordingPermissionNow: false,
            hasPreviouslyConfirmedScreenRecordingPermission: true
        )

        #expect(shouldTreatPermissionAsGranted)
    }

    // MARK: - LumaMobileNetDetector Tests

    @Test func queryMatchWeightIsOnePointZeroForExactMatch() {
        let matchWeight = LumaMobileNetDetector.computeQueryMatchWeight(
            recognizedText: "Save",
            searchQuery: "Save"
        )
        #expect(matchWeight == 1.0)
    }

    @Test func queryMatchWeightIsSevenTenthsWhenLabelContainsQuery() {
        let matchWeight = LumaMobileNetDetector.computeQueryMatchWeight(
            recognizedText: "Save Document",
            searchQuery: "Save"
        )
        #expect(matchWeight == 0.7)
    }

    @Test func queryMatchWeightIsFourTenthsWhenQueryContainsLabelLongerThanThreeChars() {
        let matchWeight = LumaMobileNetDetector.computeQueryMatchWeight(
            recognizedText: "Save",
            searchQuery: "Save Document Now"
        )
        #expect(matchWeight == 0.4)
    }

    @Test func queryMatchWeightIsZeroForUnrelatedText() {
        let matchWeight = LumaMobileNetDetector.computeQueryMatchWeight(
            recognizedText: "Lorem ipsum",
            searchQuery: "Save"
        )
        #expect(matchWeight == 0.0)
    }

    @Test func queryMatchWeightIsZeroWhenQueryContainsLabelOfThreeCharsOrFewer() {
        // Labels of 3 chars or fewer are too ambiguous to match on (noise threshold)
        let matchWeight = LumaMobileNetDetector.computeQueryMatchWeight(
            recognizedText: "OK",
            searchQuery: "Click OK to confirm"
        )
        #expect(matchWeight == 0.0)
    }

    @Test func queryMatchIsCaseInsensitive() {
        let matchWeight = LumaMobileNetDetector.computeQueryMatchWeight(
            recognizedText: "SAVE",
            searchQuery: "save"
        )
        #expect(matchWeight == 1.0)
    }

    @Test func visionBoundingBoxIsFlippedToQuartzTopLeftOrigin() {
        // Vision box near the top of a 1000×1000 screen in Vision coords (bottom-left origin):
        //   minX=0.1, minY=0.8, width=0.2, height=0.1
        //   → maxY = minY + height = 0.9
        // In Quartz (top-left origin):
        //   quartzX      = 0.1 × 1000 = 100
        //   quartzY      = (1.0 - 0.9) × 1000 = 100
        //   quartzWidth  = 0.2 × 1000 = 200
        //   quartzHeight = 0.1 × 1000 = 100
        let visionBox = CGRect(x: 0.1, y: 0.8, width: 0.2, height: 0.1)
        let screenSize = CGSize(width: 1000, height: 1000)
        let quartzFrame = LumaMobileNetDetector.visionBoundingBoxToQuartzScreenFrame(
            visionNormalizedBox: visionBox,
            screenSize: screenSize
        )
        #expect(abs(quartzFrame.origin.x - 100) < 0.01)
        #expect(abs(quartzFrame.origin.y - 100) < 0.01)
        #expect(abs(quartzFrame.width  - 200) < 0.01)
        #expect(abs(quartzFrame.height - 100) < 0.01)
    }

    @Test func visionBoxAtBottomOfScreenMapsToLargeQuartzY() {
        // Vision box at the very bottom: minY=0.0, height=0.1 → maxY=0.1
        // In Quartz: quartzY = (1.0 - 0.1) × 1000 = 900
        let visionBox = CGRect(x: 0.0, y: 0.0, width: 1.0, height: 0.1)
        let screenSize = CGSize(width: 1000, height: 1000)
        let quartzFrame = LumaMobileNetDetector.visionBoundingBoxToQuartzScreenFrame(
            visionNormalizedBox: visionBox,
            screenSize: screenSize
        )
        #expect(abs(quartzFrame.origin.y - 900) < 0.01)
    }

    // MARK: - LumaImageProcessingEngine Layer 3 Helper Tests

    @Test func pointTagParserExtractsCoordinatesFromValidTag() {
        let apiResponseContainingPointTag = "[POINT:320,240:Save button]"
        let parsedCoordinate = LumaImageProcessingEngine.parsePointTagFromAPIResponse(
            apiResponseContainingPointTag
        )
        #expect(parsedCoordinate != nil)
        #expect(abs((parsedCoordinate?.x ?? 0) - 320) < 0.01)
        #expect(abs((parsedCoordinate?.y ?? 0) - 240) < 0.01)
    }

    @Test func pointTagParserHandlesTagWithNoLabel() {
        let apiResponseContainingPointTag = "[POINT:100,200]"
        let parsedCoordinate = LumaImageProcessingEngine.parsePointTagFromAPIResponse(
            apiResponseContainingPointTag
        )
        #expect(parsedCoordinate != nil)
        #expect(abs((parsedCoordinate?.x ?? 0) - 100) < 0.01)
        #expect(abs((parsedCoordinate?.y ?? 0) - 200) < 0.01)
    }

    @Test func pointTagParserReturnsNilForNoneTag() {
        let apiResponseWithNoElement = "[POINT:none]"
        let parsedCoordinate = LumaImageProcessingEngine.parsePointTagFromAPIResponse(
            apiResponseWithNoElement
        )
        #expect(parsedCoordinate == nil)
    }

    @Test func pointTagParserReturnsNilForUnrelatedText() {
        let unrelatedText = "I couldn't find that element on screen."
        let parsedCoordinate = LumaImageProcessingEngine.parsePointTagFromAPIResponse(
            unrelatedText
        )
        #expect(parsedCoordinate == nil)
    }

    @Test func adaptiveBoxIsSmallForSingleCharQuery() {
        let singleCharSize = LumaImageProcessingEngine.adaptiveBoundingBoxSize(forSearchQuery: "R")
        #expect(abs(singleCharSize.width  - 24) < 0.01)
        #expect(abs(singleCharSize.height - 24) < 0.01)
    }

    @Test func adaptiveBoxIsSmallForDoubleCharQuery() {
        let doubleCharSize = LumaImageProcessingEngine.adaptiveBoundingBoxSize(forSearchQuery: "RN")
        #expect(abs(doubleCharSize.width  - 24) < 0.01)
        #expect(abs(doubleCharSize.height - 24) < 0.01)
    }

    @Test func adaptiveBoxIsStandardSizeForWordQuery() {
        let wordSize = LumaImageProcessingEngine.adaptiveBoundingBoxSize(forSearchQuery: "Save")
        #expect(abs(wordSize.width  - 60) < 0.01)
        #expect(abs(wordSize.height - 30) < 0.01)
    }

    @Test func adaptiveBoxIsStandardSizeForPhraseQuery() {
        let phraseSize = LumaImageProcessingEngine.adaptiveBoundingBoxSize(
            forSearchQuery: "New Project"
        )
        #expect(abs(phraseSize.width  - 60) < 0.01)
        #expect(abs(phraseSize.height - 30) < 0.01)
    }

}
