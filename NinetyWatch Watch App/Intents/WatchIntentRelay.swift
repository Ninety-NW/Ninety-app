// WatchIntentRelay.swift
// NinetyWatch Watch App
//
// Async bridge between watchOS AppIntents and iPhone via WatchConnectivity.
// The Watch cannot run AlarmKit, so every Siri command captured on the wrist
// is packed into a WCSession.sendMessage payload and relayed to the iPhone
// for execution. The iPhone replies with a dialog string that the Watch
// intent returns to Siri verbatim.

import WatchConnectivity

/// Thread-safe relay that wraps `WCSession.sendMessage` in `async/await`.
actor WatchIntentRelay {

    static let shared = WatchIntentRelay()

    // MARK: - Errors

    enum RelayError: Error, LocalizedError {
        case sessionNotAvailable
        case phoneNotReachable
        case invalidResponse
        case phoneError(String)

        var errorDescription: String? {
            switch self {
            case .sessionNotAvailable:
                return "WatchConnectivity non è disponibile."
            case .phoneNotReachable:
                return "L'iPhone non è raggiungibile. Assicurati che sia nelle vicinanze."
            case .invalidResponse:
                return "Risposta non valida dall'iPhone."
            case .phoneError(let msg):
                return msg
            }
        }
    }

    // MARK: - Relay

    /// Sends an intent relay message to the paired iPhone and awaits a dialog response.
    ///
    /// - Parameters:
    ///   - action: The relay action identifier (e.g. `"setAlarm"`, `"getAlarm"`, `"updateAlarm"`).
    ///   - params: Additional key-value pairs to include in the message payload.
    /// - Returns: The dialog string composed by the iPhone-side handler.
    func relay(action: String, params: [String: Any] = [:]) async throws -> String {
        guard WCSession.isSupported() else {
            throw RelayError.sessionNotAvailable
        }

        let session = WCSession.default

        guard session.activationState == .activated else {
            throw RelayError.sessionNotAvailable
        }

        guard session.isReachable else {
            throw RelayError.phoneNotReachable
        }

        // Build outgoing message
        var message: [String: Any] = ["intentRelay": action]
        for (key, value) in params {
            message[key] = value
        }

        // Bridge the callback-based API into async/await
        return try await withCheckedThrowingContinuation { continuation in
            session.sendMessage(message, replyHandler: { reply in
                if let error = reply["error"] as? String {
                    continuation.resume(throwing: RelayError.phoneError(error))
                } else if let dialog = reply["dialog"] as? String {
                    continuation.resume(returning: dialog)
                } else {
                    continuation.resume(throwing: RelayError.invalidResponse)
                }
            }, errorHandler: { error in
                continuation.resume(throwing: error)
            })
        }
    }
}
