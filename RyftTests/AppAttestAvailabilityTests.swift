import DeviceCheck
import Foundation
import Testing
@testable import Ryft

/// AC5: the platform doesn't serve App Attest (yet): no key, no header, and few probes.
@Suite("App Attest: not served yet (AC5)")
@MainActor
struct AppAttestNotServedTests {
    struct Answer: Sendable, CustomTestStringConvertible {
        let status: Int
        let servedBefore: Bool
        var testDescription: String { "\(status), seen served before: \(servedBefore)" }
    }

    @Test(arguments: [Answer(status: 404, servedBefore: false), Answer(status: 501, servedBefore: false),
                      Answer(status: 404, servedBefore: true)])
    func noKeyNoHeaderAndNoSecondProbeUntilSixHours(_ answer: Answer) async throws {
        let rig = AttestRig(served: answer.servedBefore, scripted: false)
        rig.server.reply(AttestServer.challenge, .json(answer.status, #"{"error":"not found"}"#))

        _ = try await rig.getMe()
        #expect(await rig.renewalEnded())
        _ = try await rig.getMe()
        #expect(rig.server.count(AttestServer.challenge) == 1)
        #expect(rig.service.calls.isEmpty && rig.keys.stored == nil && rig.keys.saved.isEmpty)
        #expect(rig.server.count(AttestServer.keys) == 0 && rig.server.count(AttestServer.token) == 0)
        #expect(rig.backoff?.servedSeen == false)

        // The next launch, a few hours on, on the same defaults: no probe either.
        rig.launch()
        _ = try await rig.getMe()
        rig.clock.advance(by: .seconds(6 * 3_600 - 60))
        rig.launch()
        _ = try await rig.getMe()
        #expect(await rig.renewalEnded())
        #expect(rig.server.count(AttestServer.challenge) == 1)
        #expect(rig.server.appTokens(AttestServer.me) == [nil, nil, nil, nil])

        // Six hours after the answer: one probe again (and still nothing else).
        rig.clock.advance(by: .seconds(61))
        rig.launch()
        _ = try await rig.getMe()
        #expect(await rig.renewalEnded())
        #expect(rig.server.count(AttestServer.challenge) == 2)
        #expect(rig.service.calls.isEmpty)
        #expect(rig.server.appTokens(AttestServer.me).allSatisfy { $0 == nil })
    }

    @Test func twoAttestorsOnOneDefaultsSuiteProbeOnce() async throws {
        let rig = AttestRig(served: false, scripted: false)
        rig.server.reply(AttestServer.challenge, .json(404, #"{"error":"not found"}"#))
        let first: AppAttestor = rig.attestor
        let second = rig.launch()
        #expect(first !== second)
        _ = try await rig.getMe(rig.client(for: first))
        #expect(await rig.renewalEnded(first))
        _ = try await rig.getMe(rig.client(for: second))
        #expect(await rig.renewalEnded(second))
        #expect(rig.server.count(AttestServer.challenge) == 1)
    }

    @Test(arguments: [500, 503])
    func aServerErrorIsNotAnAnswerToNotServed(_ status: Int) async throws {
        let rig = AttestRig()
        rig.server.reply(AttestServer.challenge, .refusal(status, requestID: "rid-5xx"))
        _ = try await rig.getMe()
        #expect(rig.backoff?.notServedUntil == nil)
        #expect(rig.server.count(AttestServer.challenge) == 1)
        #expect(rig.service.calls.isEmpty)
        // Only the in-process backoff holds: the next launch asks again.
        rig.launch()
        _ = try await rig.getMe()
        #expect(rig.server.count(AttestServer.challenge) == 2)
    }

    @Test func aServedAnswerEndsTheBackoff() async throws {
        let rig = AttestRig(served: false)
        rig.defaults.set(try JSONEncoder().encode(AppAttestor.Backoff(
            notServedUntil: rig.clock.now().addingTimeInterval(3_600))), forKey: AppAttestor.defaultsKey)
        rig.launch()
        _ = try await rig.getMe()
        #expect(rig.server.count(AttestServer.challenge) == 0)       // inside the six hours
        rig.clock.advance(by: .seconds(3_601))
        rig.launch()
        _ = try await rig.getMe()
        #expect(await rig.renewalEnded())
        #expect(rig.backoff?.servedSeen == true && rig.backoff?.notServedUntil == nil)
        _ = try await rig.getMe()
        #expect(rig.server.appTokens(AttestServer.me).last == "tok-1")
    }

    @Test func aDeviceClockSetBackDoesNotExtendTheBackoff() async throws {
        let rig = AttestRig(served: false)
        // A stored end further out than six hours can only come from a clock that was set back: over.
        rig.defaults.set(try JSONEncoder().encode(AppAttestor.Backoff(
            notServedUntil: rig.clock.now().addingTimeInterval(30 * 86_400))), forKey: AppAttestor.defaultsKey)
        rig.launch()
        _ = try await rig.getMe()
        #expect(await rig.renewalEnded())
        #expect(rig.server.count(AttestServer.challenge) > 0)       // a whole run: asked again
    }
}

/// AC6: this iPhone can't attest: nothing is sent.
@Suite("App Attest: unsupported (AC6)")
@MainActor
struct AppAttestUnsupportedTests {
    @Test func noAttestRequestAndNoHeaderOnAnyRoute() async throws {
        let rig = AttestRig(supported: false)
        _ = try await rig.getMe()
        _ = try await rig.postSync()
        _ = try await rig.getMe()
        #expect(rig.server.appAttestRequests == 0)
        #expect(rig.service.calls.isEmpty)
        #expect(rig.server.requests.allSatisfy { $0.appToken == nil })
        #expect(rig.server.requests.count == 3)
        // Nothing kept: no Keychain item, no backoff.
        #expect(rig.keys.saved.isEmpty && rig.keys.stored == nil)
        #expect(rig.backoff == AppAttestor.Backoff(servedSeen: true))   // as it was set up
    }

    @Test func aLaterLaunchOnTheSameDeviceDoesNotAskEither() async throws {
        let rig = AttestRig(supported: false)
        for _ in 0..<3 {
            rig.launch()
            _ = try await rig.getMe()
        }
        #expect(rig.server.appAttestRequests == 0 && rig.service.calls.isEmpty)
    }

    @Test func featureUnsupportedFromAppleEndsAppAttestForTheProcess() async throws {
        let rig = AttestRig()
        rig.service.failNext("generateKey", with: DCError(.featureUnsupported))
        _ = try await rig.getMe()
        #expect(rig.server.count(AttestServer.challenge) == 1)
        #expect(rig.service.count("generateKey") == 1 && rig.server.count(AttestServer.keys) == 0)
        #expect(rig.server.appTokens(AttestServer.me) == [nil])
        // For the rest of the process, whatever the clock says.
        rig.clock.advance(by: .seconds(3_600))
        _ = try await rig.getMe()
        #expect(rig.server.appAttestRequests == 1 && rig.service.count("generateKey") == 1)
        #expect(rig.server.appTokens(AttestServer.me) == [nil, nil])
    }
}
