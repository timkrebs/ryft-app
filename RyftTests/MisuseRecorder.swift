import Foundation
import Testing
import XCTest
@testable import Ryft

/// A read-model misuse in the unit tests (`Repository.onMisuse`: `seed` while writes are pending) fails the test that
/// made it instead of stopping the host with every test running in it. The app finds this class at run time by its
/// Objective-C name (`Misuse.report`). Outside a Swift Testing test, XCTest's failure.
@objc(RyftTestsMisuseRecorder)
final class MisuseRecorder: NSObject, MisuseRecording {
    static func record(_ message: String) {
        // Where it came from: the issue's own location is this file. Past `record`, `Misuse.report` and the default.
        let caller = Thread.callStackSymbols.dropFirst(4).prefix(6).joined(separator: "\n")
        let text = "\(message)\nCalled from:\n\(caller)"
        if Test.current != nil {
            Issue.record(Comment(rawValue: text))
        } else {
            XCTFail(text)
        }
    }
}
