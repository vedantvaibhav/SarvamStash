# Stash × Sarvam — Buildathon Launch Plan

_Drafted: 24 Jul 2026_

## 1. Context

- **Event:** GrowthX × Sarvam "Epoch Buildathon." 200 builders, 8-hour build, ₹10L prize pool. Top 10 teams present live at Sarvam Epoch (India's Frontier AI Conference, 30–31 July) in front of investors and AI leaders (Lightspeed, Bessemer backing; Razorpay supporting).
- **Application deadline:** ~48 hours from when this was flagged (24 Jul) — so effectively by **26 Jul**. This is the near-term forcing function; the 8-hour build itself happens later, at the event.
- **Credits:** every builder gets 5,000 Sarvam credits.
- **Stakes:** this isn't a normal hackathon demo — the room includes people from NVIDIA, AWS, Razorpay, Zepto, Swiggy, and India's leading AI companies. Judging likely rewards depth of Sarvam usage *and* "this is a real product," not just an API wrapper thrown together in 8 hours.

## 2. Product thesis

**"A language layer for your Mac."** One Sarvam-powered pipeline, reachable from three different capture surfaces:

1. **Voice** (mic) → dictate in Hindi/Hinglish/codemix → clean text lands wherever you're typing.
2. **Selected text** (any webpage) → a pill offers to translate it to your default language.
3. *(Nice-to-have, not must-have)* **Audio/video playing in a browser tab** → live translated captions overlaid on the page.

All three feed the same underlying idea: capture something in one language, deliver it in another, with minimal friction. This is the story for judges — not three unrelated features, one pipeline with three doors into it.

Base app (clipboard history, notes, file shelf) carries over from Stash unchanged in spirit — it's there to prove "this is a real, already-working macOS app," not something to demo on stage. The stage time goes entirely to the Sarvam-powered surfaces.

## 3. Repo setup

- **New standalone repo/Xcode project**, forked from the current Stash codebase (confirmed: not a branch — a real fork with its own bundle ID).
- Open decisions to make when forking: own Sparkle update feed vs. none for the hackathon build, own Supabase project vs. reusing the existing one (reusing is faster but couples the demo build to production auth — leaning toward reusing for speed unless there's a reason not to).
- Carried over as-is (no changes needed): `AutoPasteService.swift` (AX-write + ⌘V fallback paste), `TranscriptionFloatingWidget.swift` (pill UI shell), `PanelController.swift`, `NotesStorage.swift`, file shelf.

## 4. Feature list (everything decided so far)

### 4.1 Clipboard history cap
- Current: `ClipboardManager.swift`, `maxEntries = 50`.
- Change: raise to 500 (adjustable — this is a one-line constant, easy to tune later).

### 4.2 Remove forced auto-copy on transcription; new completion pill
- Current behavior (`TranscriptionService.deliverTranscriptShort`): every transcript is written to the pasteboard unconditionally, regardless of whether AutoPaste actually landed anywhere.
- New behavior:
  - AutoPaste succeeds (verified) → done. No forced clipboard write. Existing short "Pasted ✓" pill stays as-is.
  - AutoPaste fails/uncertain → new fallback pill: 2-line truncated preview of the transcript + a Copy button, holds for 5 seconds, then dismisses. Transcript is saved to Notes either way (this part already happens today and doesn't change).
- Touches: `TranscriptionService.swift` (`deliverTranscriptShort`, `pillCopyFor`), likely a new SwiftUI subview in/near `TranscriptionFloatingWidget.swift` for the fallback pill body.

### 4.3 Sarvam as primary transcription provider, OpenAI as fallback
- Sarvam Saaras v3 tried first (codemix-aware, purpose-built for Hindi/English/regional mixing — the actual differentiator over the current OpenAI-only pipeline).
- On Sarvam error/timeout, fall back automatically to the existing OpenAI Whisper path (already built, no changes needed to that half).
- Sarvam is **not** OpenAI-endpoint-compatible — different request/response shape entirely — so this is a new parallel service, not a URL swap. Do not fold it into `APIConstants.resolvedProvider`'s prefix-sniffing logic; keep it as a fully separate constants surface with its own base URL and key.
- Batch/REST endpoint recommended for the core dictation flow (matches the existing request/response pipeline shape); WebSocket streaming reserved for the stretch caption feature (4.5), where real-time actually matters.

### 4.4 Bug fix: sessions stuck "waiting" for too long
- Root cause found: `TranscriptionRetryQueue.swift` backoff schedule is 2s → 8s → 30s → 2m → 10m across 5 attempts — worst case ~12.6 cumulative minutes stuck waiting.
- Fix: cap the max backoff step at 2 minutes (instead of 10), and add a manual "retry now" affordance to the waiting pill so the user isn't purely at the mercy of silent backoff.

### 4.5 Browser text-selection translate pill *(must-have new feature)*
- Chrome extension, content script detects a text selection on any page → floating pill appears: "Translate to [your default language]?" → on confirm, calls Sarvam's translation API (Mayura or Sarvam-Translate) → shows the result inline.
- Scoped to **text only** for v1 — no text-to-speech. Least-effort version, per earlier decision.

### 4.6 Live video/audio caption translation *(nice-to-have, not must-have)*
- Same Chrome extension. Uses `chrome.tabCapture` to grab the active tab's audio (works today, no native macOS audio hooks needed) → streams to Sarvam's Saaras v3 WebSocket endpoint (`codemix` or `translate` mode) → if the target language differs from what Saaras outputs directly, one more hop through Mayura/Sarvam-Translate → renders as a caption overlay on the page.
- Important correction from earlier discussion: **true AI "dubbing" (swapping in a translated voice track, synced, in the original speaker's voice) is not publicly available via API** — it's a waitlisted Sarvam Studio product. What's actually being built here is live translated *captions*, not audio dubbing. This is still a strong differentiator — it's one of Sarvam's own flagship streaming use cases, and very few other teams will attempt live tab-audio capture in 8 hours.
- Explicitly time-boxed and cuttable: if it isn't solid, it gets dropped from the live demo (see Action Plan, Phase 4).

### 4.7 New app window (menu-bar app gets a companion window)
- Today the app is menu-bar-only (`LSUIElement = true`, `NSApp.setActivationPolicy(.accessory)`, no `WindowGroup` scene in `StashApp.swift`). Adding a real window is a genuine architecture change, not a small tweak.
- Content is still open — ideas pulled from looking at Wispr Flow's dashboard: a searchable history of past transcriptions/notes, a personal vocabulary/dictionary manager (useful for Sarvam's domain-prompting feature), per-context tone/language presets. None of this is locked — lowest priority item on this list, build only if time remains.

### 4.8 Settings — "more integrated"
- Flagged as vague/open. Not blocking for the hackathon build; revisit after the core demo features are solid.

## 5. API keys — what actually changes

**Nothing gets replaced. This is additive.**

- Existing keys (untouched): `STASH_INFERENCE_API_KEY` (OpenAI/Groq/xAI, auto-detected by prefix), `STASH_SPEECH_TRANSCRIPTION_API_KEY` (optional separate speech key), `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SLACK_ERROR_WEBHOOK_URL`. All resolved through `APIKeys.swift`'s existing chain: environment variable → bundled `Secrets.plist` → `~/Library/Application Support/Stash/Secrets.plist`.
- **New key needed:** `SARVAM_API_KEY` — one subscription key covers Saaras (STT), Mayura/Sarvam-Translate, Bulbul (TTS), and the chat models, so this is a single addition, not several.
- Add it to `APIKeys.swift` as a new static var following the exact existing pattern:
  ```swift
  static var sarvamAPIKey: String {
      resolved("SARVAM_API_KEY")
  }
  ```
  Do **not** modify the `resolved()` resolution chain itself — that logic is explicitly off-limits per project rules; only add alongside it.
- Where to get it: sign up at `dashboard.sarvam.ai`, using the account that has the buildathon's 5,000 credits attached.
- Store it the same way as every other key: `Secrets.plist` (gitignored) locally, or the Application Support plist. Never hardcode, never commit — same rule as everything else in this codebase.
- New constants surface needed: since Sarvam isn't OpenAI-shaped, a small `SarvamConstants.swift` (or a clearly separated section in `APIConstants.swift`) holding the Sarvam base URL and model identifiers, kept independent from the existing `resolvedProvider` prefix-sniffing.

## 6. Open questions (not blocking, but worth settling soon)

- Solo or team? Changes how much of this is realistically buildable in 8 hours.
- Reuse the existing Supabase project for the fork, or stand up a separate one?
- Exact content of the new app window (section 4.7) — lowest priority, can stay undecided until closer to the event.
- Settings "more integrated" — needs a follow-up conversation once the core features are locked.

## 7. Action plan

Ordered by priority: must-haves first, nice-to-haves explicitly cuttable.

**Before the event (during/after the 48-hour application window):**
- Fork the repo, set up the new Xcode project and bundle ID.
- Sign up on Sarvam's dashboard, confirm the 5,000 credits are active, get the API key.
- Add `SARVAM_API_KEY` to `APIKeys.swift` + local `Secrets.plist`; smoke-test one Saaras REST call outside the app (curl or a small script) before wiring it into Swift.
- Decide team size/composition — affects everything below.

**Hour 0–2: Core Sarvam swap**
- Build the Sarvam STT service (REST, batch — not streaming, to match the existing request/response pipeline shape).
- Wire it in as the primary path inside the existing `deliverTranscriptShort`/`deliverTranscriptLong` flow, OpenAI Whisper as the automatic fallback on error.
- Test against a real Hindi/Hinglish codemix sample — this is the core "wow, it actually understands code-mixing" moment.

**Hour 2–3: Bug fixes + pill/clipboard rework**
- Cap retry backoff at 2 minutes, add manual "retry now."
- Bump clipboard cap to 500.
- Remove the unconditional pasteboard write; build the 2-line-preview + Copy fallback pill (5s hold).

**Hour 3–5: Browser text-selection pill (must-have)**
- New Chrome extension target: selection listener → floating pill → Sarvam translate call → inline result.
- This is the second core demo beat, and the smaller lift of the two new browser features.

**Hour 5–6.5: Live caption translation (nice-to-have, time-boxed)**
- Same extension: `tabCapture` → Saaras WebSocket → optional translate hop → caption overlay.
- Hard cutoff at 6.5 hours. If it isn't reliable by then, cut it from the live demo — fall back to a pre-recorded clip if it's close to working, or drop it entirely if not.

**Hour 6.5–7.5: Polish + app window (only if time remains)**
- App window content from section 4.7, lowest priority.
- Otherwise: demo script rehearsal, and pre-record backup clips for anything network-dependent (especially section 4.6 — live-API demos are the classic way things go wrong on stage).

**Last 30 minutes:** buffer. Cut scope rather than ship something half-working.

## 8. Demo script (for stage, if selected in top 10)

1. Open with the "real product" framing — this already exists, has real users, real infrastructure (10 seconds, don't over-explain).
2. Beat 1: speak a Hindi-English codemix sentence into the mic → clean text appears instantly wherever the cursor is.
3. Beat 2: select untranslated text on a real webpage → pill → translated inline.
4. Beat 3 (only if 4.6 shipped and is reliable): play a short video with non-English audio → live captions appear in the viewer's language.
5. Close on the thesis: one Sarvam pipeline, three ways in.
