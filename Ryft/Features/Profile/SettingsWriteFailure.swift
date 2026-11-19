import Foundation

/// How a settings change failed, judged by what left the phone, not by the network when the failure arrived (the body-setting
/// editors and Notifications share it; C3 review, item 2):
/// - `offline`: nothing was sent. The iPhone had no network path (`notConnectedToInternet`, `dataNotAllowed`,
///   `internationalRoamingOff`), or the caller's check before sending found none. Nothing changed.
/// - `noAnswer`: it was sent, and no readable answer came back (a timeout, a dropped connection, any other transport failure,
///   a `408`). It may have saved, so the caller asks the platform again (`rereads`).
/// - `serverError`: RYFT answered with a `5xx` (not `501`). It's back as it was; the caller asks again all the same.
/// - `refused`: RYFT answered no (`4xx`, `429`, `501`, signed out). Nothing changed.
/// A `422` names its own field in the caller's words before it gets here.
enum SettingsWriteFailure: Equatable {
    case offline, noAnswer, serverError, refused

    init(_ error: Error) {
        if let api = error as? APIError {
            switch api {
            case .transport(let inner):
                self = Self.sentNothing(inner) ? .offline : .noAnswer
            case .http(let status, _, _, _, _):
                switch status {
                case 408: self = .noAnswer
                case 501: self = .refused
                case 500...599: self = .serverError
                default: self = .refused
                }
            case .signedOut, .notConfigured:
                self = .refused
            }
        } else if error is URLError {
            self = Self.sentNothing(error) ? .offline : .noAnswer
        } else {
            // Not an answer RYFT gave (an unreadable body, an SDK's own failure): the change may have gone through.
            self = .noAnswer
        }
    }

    /// The platform may hold something else than the page shows: ask it again (`GET /v1/me`).
    var rereads: Bool { self == .noAnswer || self == .serverError }

    /// The URL loading system never sent the request: no path, or one this iPhone may not use.
    private static func sentNothing(_ error: Error) -> Bool {
        guard let code = (error as? URLError)?.code else { return false }
        return code == .notConnectedToInternet || code == .dataNotAllowed || code == .internationalRoamingOff
    }

    /// The sentence for a change that didn't save, the same in every settings page.
    var saveMessage: String {
        switch self {
        case .offline:
            return String(localized: "You're offline, so this wasn't saved. Try again when you're back online.",
                          comment: "Settings (Notifications, the body-setting editors): nothing was sent, the iPhone is offline; the value went back.")
        case .noAnswer:
            return String(localized: "RYFT didn't answer, so this may not have saved. Try again in a moment.",
                          comment: "Settings (Notifications, the body-setting editors): sent, no answer (a timeout, a lost connection); RYFT is asked again.")
        case .serverError:
            return String(localized: "RYFT had a problem saving this, so it's back as it was. Try again in a moment.",
                          comment: "Settings (Notifications, the body-setting editors): RYFT answered with a server error (5xx); the value went back.")
        case .refused:
            return String(localized: "RYFT couldn't save this change, so it's back as it was.",
                          comment: "Settings (Notifications, the body-setting editors): RYFT refused the change (409, 403, 429 …); it went back.")
        }
    }
}
