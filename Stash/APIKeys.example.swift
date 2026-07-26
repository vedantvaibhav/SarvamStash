//
//  APIKeys.example.swift
//
//  TEMPLATE — copy this to `Stash/APIKeys.swift` to build the project:
//
//      cp Stash/APIKeys.example.swift Stash/APIKeys.swift
//
//  `Stash/APIKeys.swift` is gitignored and is NOT in the repository, but the
//  Xcode target does reference it — so a fresh clone will not compile until
//  you make that copy. This file exists so that step is reproducible, the
//  same way `Secrets.example.plist` documents the secrets file.
//
//  IMPORTANT — do NOT add this file to the Xcode target. It declares
//  `enum APIKeys`, so compiling it alongside the real `APIKeys.swift` fails
//  with an "invalid redeclaration" error. Like `Secrets.example.plist`, it is
//  tracked in git for reference only and is deliberately absent from
//  `project.pbxproj`.
//
//  There are no key VALUES here or in the real file — both contain only the
//  resolution chain. Actual secrets live in `Secrets.plist` (see
//  `Secrets.example.plist` for the key names), never in source.
//

import Foundation

/// Single place for secret configuration. **Do not commit real values.**
///
/// Resolution order for each value:
/// 1. Process environment (Xcode Scheme → Run → Arguments → Environment Variables)
/// 2. `Secrets.plist` inside the app bundle (if you add one locally and include it in “Copy Bundle Resources” — file is gitignored)
/// 3. `~/Library/Application Support/Stash/Secrets.plist` (copy from `Secrets.example.plist`)
///
/// See repo `Stash/Secrets.example.plist` for key names.
enum APIKeys {

    static var stashInferenceAPIKey: String {
        resolved("STASH_INFERENCE_API_KEY")
    }

    static var stashSpeechTranscriptionAPIKey: String {
        resolved("STASH_SPEECH_TRANSCRIPTION_API_KEY")
    }

    /// Groq transcription: dedicated env, then generic `GROQ_API_KEY`.
    static var groqTranscriptionAPIKey: String {
        let a = resolved("STASH_GROQ_TRANSCRIPTION_KEY")
        if !a.isEmpty { return a }
        return resolved("GROQ_API_KEY")
    }

    /// Sarvam Saaras v3 speech-to-text. Same resolution chain as every other
    /// key here (env → bundled Secrets.plist → Application Support).
    static var sarvamAPIKey: String {
        resolved("SARVAM_API_KEY")
    }

    static var supabaseProjectURL: String {
        resolved("SUPABASE_URL")
    }

    static var supabaseAnonKey: String {
        resolved("SUPABASE_ANON_KEY")
    }

    static var slackErrorWebhookURL: String {
        resolved("SLACK_ERROR_WEBHOOK_URL")
    }

    // MARK: - Startup validation

    /// Logs a warning for each required key that is not configured.
    /// Never crashes — missing keys fail gracefully at request time.
    static func validateKeys() {
        let required = [
            "STASH_INFERENCE_API_KEY",
            "STASH_SPEECH_TRANSCRIPTION_API_KEY"
        ]
        for key in required {
            if resolved(key).isEmpty {
                #if DEBUG
                print("[APIKeys] WARNING: \(key) is not configured. " +
                      "Add it to Secrets.plist or environment.")
                #endif
            }
        }
    }

    // MARK: - Resolution

    /// Bundle `Secrets.plist` (optional local file) first; Application Support file overrides.
    ///
    /// NOTE: `static let` — the plist is read ONCE per process. Editing
    /// `Secrets.plist` therefore requires relaunching the app, not just
    /// rebuilding it.
    private static let plistCache: [String: String] = {
        var merged: [String: String] = [:]
        if let d = loadPlistFromBundle(named: "Secrets") {
            merged.merge(d) { _, new in new }
        }
        if let d = loadPlist(at: applicationSupportSecretsURL()) {
            merged.merge(d) { _, new in new }
        }
        return merged
    }()

    private static func resolved(_ name: String) -> String {
        let env = (ProcessInfo.processInfo.environment[name] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !env.isEmpty { return env }
        if let v = plistCache[name]?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
            return v
        }
        return ""
    }

    private static func applicationSupportSecretsURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("Stash", isDirectory: true)
            .appendingPathComponent("Secrets.plist", isDirectory: false)
    }

    private static func loadPlist(at url: URL) -> [String: String]? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let obj = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = obj as? [String: Any] else { return nil }
        return dict.compactMapValues { $0 as? String }
    }

    private static func loadPlistFromBundle(named name: String) -> [String: String]? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "plist") else { return nil }
        return loadPlist(at: url)
    }
}
