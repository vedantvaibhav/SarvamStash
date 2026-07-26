import Foundation

/// Failure taxonomy for a Saaras call. The orchestration in
/// `TranscriptionService.uploadSession` needs to tell auth rejection apart
/// from everything else: an auth failure must fail over to OpenAI
/// immediately and must never be handed to the retry queue, because no
/// amount of backoff fixes a bad subscription key.
enum SarvamSTTError: Error {
    /// HTTP 403 — bad/expired/unsubscribed key.
    case auth(message: String)
    /// No key configured. Skip Sarvam entirely rather than round-tripping.
    case notConfigured
    /// Transport failure (offline, timeout, DNS).
    case transport(URLError)
    /// Any non-200 that isn't 403, or an unparseable body.
    case api(status: Int, message: String)

    var isAuth: Bool {
        if case .auth = self { return true }
        return false
    }
}

/// Parsed Saaras response. Only the transcript is consumed downstream;
/// `languageCode` is carried for logging/diagnostics since Saaras reports
/// what it auto-detected, which is useful when debugging codemix output.
struct SarvamTranscription {
    let text: String
    let languageCode: String?
}

/// Thin client for Sarvam's non-streaming speech-to-text endpoint.
///
/// Standalone rather than a method on `TranscriptionService` so it stays
/// independently testable and doesn't grow that file further; it needs none
/// of that type's state.
struct SarvamSTTClient {

    var apiKey: String = SarvamConstants.apiKey
    var session: URLSession = .shared

    /// Transcribe `audioData` (m4a, as written by `AudioPersistence`).
    ///
    /// `mode` is passed through from the user's Settings choice — it is not
    /// hardcoded. `language_code` is sent as `unknown` so Saaras
    /// auto-detects; it is optional on every mode, codemix included.
    func transcribe(audioData: Data, mode: SarvamOutputMode) async throws -> SarvamTranscription {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw SarvamSTTError.notConfigured }
        guard let url = URL(string: SarvamConstants.transcribeURL) else {
            throw SarvamSTTError.api(status: -1, message: "Invalid Sarvam URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = SarvamConstants.requestTimeout
        // Sarvam-specific auth header — NOT `Authorization: Bearer`.
        request.setValue(key, forHTTPHeaderField: SarvamConstants.authHeaderField)

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(
            boundary: boundary,
            audioData: audioData,
            mode: mode
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw SarvamSTTError.transport(urlError)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else {
            let message = Self.errorMessage(from: data) ?? "HTTP \(status)"
            if status == SarvamConstants.authFailureStatus {
                throw SarvamSTTError.auth(message: message)
            }
            throw SarvamSTTError.api(status: status, message: message)
        }

        guard let parsed = Self.parse(data: data) else {
            throw SarvamSTTError.api(status: status, message: "Unparseable Sarvam response")
        }
        return parsed
    }

    // MARK: - Request body

    private static func multipartBody(boundary: String,
                                      audioData: Data,
                                      mode: SarvamOutputMode) -> Data {
        var body = Data()

        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }

        field("model", SarvamConstants.model)
        field("mode", mode.sarvamMode)
        // Optional on every mode — sent explicitly so auto-detect is visible
        // at the call site rather than implied by omission.
        field("language_code", SarvamConstants.autoDetectLanguageCode)

        // `input_audio_codec` is required only for raw PCM. We send m4a, so
        // it is deliberately omitted.
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".utf8))
        body.append(Data("Content-Type: \(SarvamConstants.audioMimeType)\r\n\r\n".utf8))
        body.append(audioData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }

    // MARK: - Response parsing

    /// Success body is `{ "transcript": "...", "language_code": "hi-IN", ... }`.
    /// Note the field is `transcript` — not OpenAI's `text`.
    private static func parse(data: Data) -> SarvamTranscription? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let transcript = json["transcript"] as? String else { return nil }
        return SarvamTranscription(
            text: transcript.trimmingCharacters(in: .whitespacesAndNewlines),
            languageCode: json["language_code"] as? String
        )
    }

    /// Error body is `{ "error": { "message": "...", "code": "..." } }`.
    private static func errorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }
        if let error = json["error"] as? [String: Any] {
            let message = error["message"] as? String
            let code = error["code"] as? String
            return [code, message].compactMap { $0 }.joined(separator: ": ")
        }
        return String(data: data, encoding: .utf8)
    }
}
