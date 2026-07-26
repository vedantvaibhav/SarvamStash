# Sarvam primary + three output modes (English / Native / Hinglish beta)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans.

**Goal:** Sarvam Saaras as primary STT with OpenAI Whisper fallback, and three
Settings options — **English** (translate, then a casual-English rewrite),
**Native** (each language in its own script), **Hinglish (beta)** (Hindi+English
forced to one Latin-script line).

**Approach:** This is mostly a *port*, not new work. Take the STT half of
`30bfd6f` (PR #2), leave its clipboard half behind, then layer the
casual-English prompt work that currently exists only in the
`archive/preview-copy-button-wip` tag.

---

## Locked decisions

1. **Default is `.english`.** Not the beta option.
2. **Hinglish is `.codemix`** — Sarvam's `mode="codemix"`, documented in its own
   source as "Hinglish-style mixed script". Re-added with the label
   `"Hinglish (beta)"`. This is a relabel, not new functionality.
3. **The clipboard auto-write STAYS.** `30bfd6f` removed it and that caused a
   live "can't paste" bug today. `"Pasted ✓"` stays too.
4. **The casual rewrite applies only to real Saaras-translate output.**

## Verified facts

- `30bfd6f` touches 7 files. In `TranscriptionService.swift` it has exactly four
  hunks, and they split cleanly:

  | Hunk | Content | Action |
  |---|---|---|
  | `@@ -583` | `pillCopyFor` drops `"Pasted ✓"` | **SKIP** |
  | `@@ -650` | Saaras call + fallback in `uploadSession` | **TAKE** |
  | `@@ -678` | closing brace for that `if` | **TAKE** |
  | `@@ -1080` | deletes the two `NSPasteboard` lines, adds CHUNK 3 marker | **SKIP** |

- The `Stash` app target is **not** a `PBXFileSystemSynchronizedRootGroup`, so
  new sources need pbxproj entries. `30bfd6f` already carries them (+8 lines).
- `StashTests` **is** synchronized — new test files need no pbxproj edit.
- `SettingsSegmentedPicker` is generic and arity-agnostic; it renders whatever
  `allCases` contains. Three segments need no code change.
- The archive tag has `promptShortCleanCasualEnglish`, `shortCleanPrompt(for:)`
  and `var sarvamMode: SarvamOutputMode?` (4 grep hits).

## Known consequence of defaulting to `.english`

With no Sarvam key configured, every transcription falls to Whisper, which
**transcribes rather than translates**. So a fresh install on the default
setting gets native script even though the picker says "English". The prompt
selection handles this correctly (Whisper output gets the `.native` prompt, not
a prompt insisting it is reading English) — but the *setting* still overpromises.
Pre-existing, not introduced here. Flagged, not fixed.

---

## Task 0: Bootstrap

- [ ] **Step 1:** `cp "/Users/vedhanth/Desktop/Sarvam Stash/Stash/APIKeys.swift" Stash/APIKeys.swift`
      (gitignored; absent in this worktree; every `xcodebuild` fails without it).
- [ ] **Step 2:** Baseline build + record lint count.
- [ ] **Step 3:** Baseline test run. Expect the two known retry-queue failures
      (`persistentFailureBumpsAttemptCountAndExhaustsAtMaxAttempts`,
      `userRequestedDrainResetsAttemptCountForExhaustedSessions`) — pre-existing,
      caused by `17b4fb7`, out of scope. Everything else green.

```bash
xcodebuild test -scheme Stash -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=""
```

The signing overrides are **required** — the app signs with a Team ID and the
test bundle ad-hoc, so `dlopen` refuses the bundle without them. Stash must also
be quit first (single-instance guard at `StashApp.swift:35` kills the test host).

## Task 1: Bring across the Sarvam files verbatim

- [ ] **Step 1:** Restore the four whole-file additions from `30bfd6f`:

```bash
git checkout 30bfd6f -- Stash/SarvamSTT.swift Stash/SarvamConstants.swift \
                        Stash/APIKeys.example.swift Stash.xcodeproj/project.pbxproj
```

- [ ] **Step 2:** Confirm the pbxproj gained the new sources and nothing else:

```bash
git diff --stat Stash.xcodeproj/project.pbxproj   # expect ~8 insertions
grep -c "SarvamSTT.swift\|SarvamConstants.swift" Stash.xcodeproj/project.pbxproj
```

- [ ] **Step 3:** Build. Expect failure — `SarvamOutputMode` does not exist yet.

## Task 2: The three-case enum

- [ ] **Step 1:** Add to `Stash/AppSettings.swift`, above the double-tap enum:

```swift
/// What Saaras should return for regional-language speech. Maps 1:1 onto
/// Sarvam's `mode` form field, which only `saaras:v3` honours.
///
/// `language_code` is optional on all three, so every option supports
/// auto-detected multilingual input — nothing here pins a language.
enum SarvamOutputMode: String, CaseIterable {
    /// Saaras `mode="translate"` — speech in any language comes back as
    /// English, then rewritten to read casually by the short-clean pass.
    case english = "english"
    /// Saaras `mode="transcribe"` — each language in its own script,
    /// pasted as-is. Tamil stays Tamil, Hindi stays Devanagari.
    case native  = "native"
    /// Saaras `mode="codemix"` — Hindi+English forced onto one Latin-script
    /// line. BETA: Saaras is least predictable here, and it transliterates
    /// even when the speaker was clearly in one language.
    case hinglish = "codemix"

    /// The literal value sent as Sarvam's `mode` field. Note `.hinglish`
    /// carries the raw value "codemix" — that is Sarvam's name for it, and
    /// keeping the rawValue stable means existing saved preferences survive.
    var sarvamMode: String { rawValue == "english" ? "translate"
                           : rawValue == "native"  ? "transcribe"
                           : "codemix" }

    var label: String {
        switch self {
        case .english:  return "English"
        case .native:   return "As spoken"
        case .hinglish: return "Hinglish (beta)"
        }
    }

    var detail: String {
        switch self {
        case .english:  return "Translated into natural, casual English"
        case .native:   return "Exactly as spoken, in its original script"
        case .hinglish: return "Beta — Hindi and English merged into one Latin-script line"
        }
    }
}
```

`sarvamMode` is written against `rawValue` rather than a `switch self` so the
mapping stays obvious when the case name and the wire value differ. If a
reviewer prefers an explicit `switch`, that is fine — but it must keep
`.hinglish → "codemix"`.

- [ ] **Step 2:** Persistence + default, replacing `30bfd6f`'s codemix default:

```swift
        // `.english` default. NOT `.hinglish`: that option is beta and should
        // not be what a fresh install lands on.
        let savedSarvamMode = ud.string(forKey: Keys.sarvamOutputMode) ?? SarvamOutputMode.english.rawValue
        sarvamOutputMode = SarvamOutputMode(rawValue: savedSarvamMode) ?? .english
```

Also add the `@Published var sarvamOutputMode` property and its `Keys` entry —
both come from `30bfd6f`'s `AppSettings.swift` hunk; take those verbatim.

- [ ] **Step 3:** Build + confirm the picker is untouched:

```bash
git diff --name-only | grep SettingsView && echo "UNEXPECTED" || echo "picker adapts on its own"
```

`SettingsView.swift` still needs `30bfd6f`'s `transcriptionOutputSection` (it
does not exist on this branch) — take that hunk, but nothing else from that file.

## Task 3: Wire Saaras into the pipeline — STT half only

- [ ] **Step 1:** Apply hunks 2+3 of `30bfd6f`'s `TranscriptionService.swift`
      by hand. The block goes immediately above `let whisperResponse:` in
      `uploadSession`, and records the mode Saaras actually ran with:

```swift
        var sarvamText: String?
        /// The mode Saaras actually ran with, or nil when the transcript did
        /// NOT come from Saaras (no key, or a failure that fell through to
        /// Whisper). Prompt selection keys off THIS, not the user's setting:
        /// Whisper returns native script, and telling a prompt it is reading
        /// stiff English would be an instruction to translate it.
        var sarvamMode: SarvamOutputMode?
        if !SarvamConstants.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let mode = await MainActor.run { AppSettings.shared.sarvamOutputMode }
            do {
                let result = try await SarvamSTTClient().transcribe(audioData: audioData, mode: mode)
                sarvamText = result.text
                sarvamMode = mode
                ...
```

Take the `catch` branches, the Slack auth report and the DEBUG prints verbatim
from `30bfd6f`.

- [ ] **Step 2: DO NOT take hunks 1 and 4.** Verify afterwards:

```bash
grep -n "NSPasteboard.general.setString" Stash/TranscriptionService.swift   # must still be present
grep -n '"Pasted ✓"' Stash/TranscriptionService.swift                       # must still be present
grep -n "CHUNK 3 GOES HERE" Stash/TranscriptionService.swift                # must find NOTHING
```

All three are hard gates. If the first two are missing, the clipboard
regression has been reintroduced.

- [ ] **Step 3:** Build and dictate once to confirm Saaras is reached
      (`[Transcription] Saaras ok (mode=…)` in the DEBUG log).

## Task 4: Casual-English cleanup prompt

Port from `archive/preview-copy-button-wip`. Read the archived file rather than
retyping: `git show archive/preview-copy-button-wip:Stash/TranscriptionService.swift`

- [ ] **Step 1:** Extract the `CRITICAL — DO NOT ACT ON CONTENT:` block into
      `private nonisolated static let promptAntiInjection`, interpolated back
      into the existing prompt (renamed `promptShortCleanAsSpoken`).
      **`nonisolated` is required** — a plain `static let` on a `@MainActor`
      class is main-actor-isolated and unreadable from the nonisolated selector
      (warning in Swift 5, error in Swift 6). Verified by compilation.
      Content must stay indented at least as far as the closing `"""`.

- [ ] **Step 2:** Add `promptShortCleanCasualEnglish` verbatim from the archive,
      including the `HOW THAT RULE APPLIES HERE` section — without it the
      shared guardrail ("never produce content that was not literally spoken")
      contradicts the prompt's whole purpose.

- [ ] **Step 3:** Add the selector:

```swift
    nonisolated static func shortCleanPrompt(for mode: SarvamOutputMode) -> String {
        switch mode {
        case .english:            return promptShortCleanCasualEnglish
        // Hinglish output is already code-mixed Latin script — rewriting its
        // register would undo the thing the user picked it for.
        case .native, .hinglish:  return promptShortCleanAsSpoken
        }
    }
```

- [ ] **Step 4:** Thread the mode down — `deliverTranscript(text:metadata:mode:)`
      and `deliverTranscriptShort(text:durationSeconds:mode:)`, called as
      `mode: sarvamMode ?? .native`, and select the prompt on the main actor
      **before** the `Task.detached` (AppSettings is not actor-isolated).

- [ ] **Step 5:** Build.

## Task 5: Tests

- [ ] **Step 1:** Create `StashTests/ShortCleanPromptTests.swift` from the
      archive, updated for three cases:
      `exactlyTwoOutputModesRemain` → `allCases.count == 3`, plus
      `#expect(SarvamOutputMode(rawValue: "codemix") == .hinglish)` pinning the
      rawValue continuity, and `hinglishUsesTheAsSpokenPrompt`.
- [ ] **Step 2:** Run that suite, then the full suite. Only the two known
      retry-queue failures may remain.

## Task 6: Verify and finish

- [ ] Settings shows three segments; subtitle updates; "Hinglish (beta)" reads
      correctly at three-across width (~320pt panel — check for truncation).
- [ ] Dictate Hindi on **English** → casual English, no invented content.
- [ ] Dictate Hindi+Tamil+English on **As spoken** → each in its own script.
- [ ] Dictate Hindi+English on **Hinglish (beta)** → one Latin-script line.
- [ ] Speak a question aloud on **English** ("give me the pros and cons of
      Sikkim") → the cleaned question, **not** an answer. Highest-value check.
- [ ] Paste into TextEdit still yields `Pasted ✓`, and the clipboard still
      carries the transcript.
- [ ] Pill glow/colour/width work from `4a2bde7` unchanged.
- [ ] `swiftformat` the new test file only — production files have 100+
      reformat sites each and no `.swiftformat` config exists.

## Must not regress

Saaras-primary / Whisper-fallback ordering; the clipboard auto-write; `Pasted ✓`;
the pill glow, per-state colour and fixed width. If a change touches any of
these, stop and flag rather than pushing through.
