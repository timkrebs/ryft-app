import Foundation

/// Where a read-model misuse goes (`Repository.onMisuse`'s default). In the unit tests' host, RyftTests'
/// `MisuseRecorder` records it against the test that made it: that test fails, the host and the other tests go on.
/// Found at run time by its Objective-C name: the app, its previews and the UI tests' app process have no such class,
/// and stop at the misuse in Debug.
@objc protocol MisuseRecording {
    static func record(_ message: String)
}

enum Misuse {
    /// The Objective-C name of RyftTests' recorder.
    static let recorderClassName = "RyftTestsMisuseRecorder"

    /// The unit tests' recorder when it's loaded (the tests' host), else Debug stops here.
    static func report(_ message: String) {
        if let recorder = NSClassFromString(recorderClassName) as? MisuseRecording.Type {
            recorder.record(message)
        } else {
            assertionFailure(message)
        }
    }
}
