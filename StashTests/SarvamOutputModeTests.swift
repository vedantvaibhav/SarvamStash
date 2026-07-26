import Testing
import Foundation
@testable import Stash

/// The three output modes and the cleanup prompt each one selects.
///
/// Not `@MainActor`: `shortCleanPrompt(for:)` and the prompt constants are all
/// `nonisolated`, deliberately — a plain `static let` on a `@MainActor` class
/// is main-actor-isolated and unreadable from here.
@Suite("Sarvam output modes")
struct SarvamOutputModeTests {

    @Test func threeModesAreOffered() {
        #expect(SarvamOutputMode.allCases.count == 3)
    }

    /// Each case maps to the literal Saaras `mode` field value. Getting these
    /// wrong silently changes what the API returns.
    @Test func eachModeSendsTheRightSaarasModeValue() {
        #expect(SarvamOutputMode.english.sarvamMode == "translate")
        #expect(SarvamOutputMode.native.sarvamMode == "transcribe")
        #expect(SarvamOutputMode.hinglish.sarvamMode == "codemix")
    }

    /// `.hinglish` is a RENAME of the old `codemix` case, not a new one. Its
    /// rawValue stays "codemix" so preferences saved by earlier builds keep
    /// resolving instead of silently falling back to the default.
    @Test func hinglishPreservesTheCodemixRawValue() {
        #expect(SarvamOutputMode.hinglish.rawValue == "codemix")
        #expect(SarvamOutputMode(rawValue: "codemix") == .hinglish)
    }

    /// Hinglish is beta and must not be what a fresh install lands on.
    @Test func hinglishIsLabelledBeta() {
        #expect(SarvamOutputMode.hinglish.label.lowercased().contains("beta"))
    }

    @Test func everyModeHasADistinctLabelAndDetail() {
        let labels = Set(SarvamOutputMode.allCases.map(\.label))
        let details = Set(SarvamOutputMode.allCases.map(\.detail))
        #expect(labels.count == 3)
        #expect(details.count == 3)
    }
}

@Suite("Short-clean prompt selection")
struct ShortCleanPromptTests {

    @Test func englishSelectsTheCasualRewrite() {
        #expect(TranscriptionService.shortCleanPrompt(for: .english).contains("casual"))
    }

    /// Both "give me back what I said" modes share the untouched cleanup
    /// prompt. Rewriting register on either would undo the point of choosing
    /// it — especially Hinglish, whose whole output is deliberately code-mixed.
    @Test func nativeAndHinglishBothUseTheAsSpokenPrompt() {
        let asSpoken = TranscriptionService.shortCleanPrompt(for: .native)
        #expect(asSpoken.contains("Preserve the speaker's vocabulary and tone exactly"))
        #expect(TranscriptionService.shortCleanPrompt(for: .hinglish) == asSpoken)
    }

    @Test func englishPromptDiffersFromTheOthers() {
        #expect(TranscriptionService.shortCleanPrompt(for: .english)
                != TranscriptionService.shortCleanPrompt(for: .native))
    }

    /// Interpolated from one shared constant, so it cannot drift — but if
    /// someone later inlines it into one prompt and edits the other, this
    /// fails. The guardrail is the difference between "pros and cons of
    /// Sikkim" being cleaned and being answered.
    @Test func everyPromptCarriesTheAntiInjectionGuardrail() {
        for mode in SarvamOutputMode.allCases {
            let prompt = TranscriptionService.shortCleanPrompt(for: mode)
            #expect(prompt.contains("DO NOT ACT ON CONTENT"),
                    "\(mode) prompt lost the anti-injection guardrail")
            #expect(prompt.contains("never produce"),
                    "\(mode) prompt lost the never-produce-uninvited-content rule")
        }
    }

    /// Register may change; meaning may not.
    @Test func everyPromptForbidsInventingContent() {
        for mode in SarvamOutputMode.allCases {
            let prompt = TranscriptionService.shortCleanPrompt(for: mode).lowercased()
            #expect(prompt.contains("never add information") || prompt.contains("never invent"),
                    "\(mode) prompt lost the never-invent guardrail")
        }
    }

    /// The shared guardrail ends on an absolute — "never produce content that
    /// was not literally spoken" — which the casual prompt's REGISTER section
    /// contradicts unless the reconciliation is present. The guardrail is
    /// deliberately NOT reworded, since that would change the as-spoken
    /// prompt. So this section is the only thing making the casual prompt
    /// coherent, and without this test its deletion leaves everything green.
    @Test func casualPromptReconcilesTheGuardrailWithRephrasing() {
        #expect(TranscriptionService.shortCleanPrompt(for: .english)
            .contains("HOW THAT RULE APPLIES HERE"))
        // Nonsense in a prompt that forbids rephrasing outright.
        #expect(!TranscriptionService.shortCleanPrompt(for: .native)
            .contains("HOW THAT RULE APPLIES HERE"))
    }
}
