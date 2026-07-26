import Foundation

/// Sarvam speech-to-text configuration.
///
/// Deliberately NOT folded into `APIConstants`. That type resolves an
/// OpenAI-*shaped* provider by sniffing the key prefix (`sk-`, `gsk_`,
/// `xai-`) and hands back an OpenAI-compatible base URL. Sarvam is not
/// OpenAI-shaped: different auth header, different endpoint path, different
/// request fields, and a different response key. Mixing it into the prefix
/// sniffing would make `resolvedProvider` lie about what the key can do.
///
/// Contract verified against Sarvam's OpenAPI spec and the published
/// speech-to-text reference (2026-07-25).
enum SarvamConstants {

    static var apiKey: String { APIKeys.sarvamAPIKey }

    static let baseURL = "https://api.sarvam.ai"

    /// Non-streaming Saaras v3 transcription.
    ///
    /// NOT `/speech-to-text-translate` — that endpoint is the legacy
    /// `saaras:v2.5` model and takes no `mode`. English output is reached
    /// here instead, via `mode = "translate"`.
    static let transcribePath = "/speech-to-text"

    static var transcribeURL: String { baseURL + transcribePath }

    /// Saaras v3. `mode` is only honoured by this model — `saarika:v2.5`
    /// ignores it.
    static let model = "saaras:v3"

    /// Auth goes in this header. Sarvam does NOT accept
    /// `Authorization: Bearer <key>`, which is what the OpenAI / Groq / xAI
    /// paths in `TranscriptionService` send — do not copy that code here.
    static let authHeaderField = "api-subscription-key"

    /// Auto-detect. `language_code` is optional on every mode (including
    /// `codemix`), so multilingual dictation works without pinning a
    /// language; sending `unknown` makes that explicit rather than relying
    /// on the field's absence.
    static let autoDetectLanguageCode = "unknown"

    /// HTTP 403 is Sarvam's auth/subscription rejection. Called out because
    /// the orchestration treats it as "fail over now, never queue".
    static let authFailureStatus = 403

    /// MIME type for the m4a/AAC files `AudioPersistence` writes.
    ///
    /// MUST NOT be `audio/m4a`. OpenAI accepts that string (it's what
    /// `callWhisper` sends), but Sarvam rejects it with HTTP 400
    /// "Invalid file type" — verified against the live API 2026-07-25. Its
    /// allow-list contains `audio/mp4` and `audio/x-m4a`, not `audio/m4a`.
    /// Copying the Whisper call's MIME here would 400 every request and make
    /// Sarvam silently fall back to OpenAI forever.
    static let audioMimeType = "audio/mp4"

    static let requestTimeout: TimeInterval = 40
}
