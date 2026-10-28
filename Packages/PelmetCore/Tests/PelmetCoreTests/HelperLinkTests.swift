import Foundation
import Synchronization
import Testing
@testable import PelmetCore

struct HelperLinkTests {
    private func ownIdentity() throws -> HelperPeerIdentity {
        let executable = try #require(Bundle.main.executableURL)
        return try #require(HelperPeerIdentity(executableURL: executable))
    }

    @Test func authenticatedPeersDeliverDataAndVerifiedIdentity() throws {
        let identity = try ownIdentity()
        let received = Mutex<[(Data, String)]>([])
        let name = UUID().uuidString
        let listener = try #require(HelperListener(name: name, peers: ["verified-helper": identity]) { data, peer in
            received.withLock { $0.append((data, peer)) }
        })
        withExtendedLifetime(listener) {
            #expect(HelperLink.send(Data("message".utf8), to: name, peer: identity))
            received.withLock {
                #expect($0.count == 1)
                #expect($0.first?.0 == Data("message".utf8))
                #expect($0.first?.1 == "verified-helper")
            }
        }
    }

    @Test func unauthorizedSenderCannotDeliverCommands() throws {
        let own = try ownIdentity()
        let other = try #require(HelperPeerIdentity(executableURL: URL(fileURLWithPath: "/bin/ls")))
        let received = Mutex(false)
        let name = UUID().uuidString
        let listener = try #require(HelperListener(name: name, peers: ["other": other]) { _, _ in
            received.withLock { $0 = true }
        })
        withExtendedLifetime(listener) {
            #expect(!HelperLink.send(Data("quit".utf8), to: name, peer: own))
            #expect(!received.withLock { $0 })
        }
    }

    @Test func impersonatedServerNeverReceivesApplicationData() throws {
        let own = try ownIdentity()
        let other = try #require(HelperPeerIdentity(executableURL: URL(fileURLWithPath: "/bin/ls")))
        let received = Mutex(false)
        let name = UUID().uuidString
        let listener = try #require(HelperListener(name: name, peers: ["self": own]) { _, _ in
            received.withLock { $0 = true }
        })
        withExtendedLifetime(listener) {
            #expect(!HelperLink.send(Data("private payload".utf8), to: name, peer: other))
            #expect(!received.withLock { $0 })
        }
    }

    @Test func rejectsOversizedMessagesWithoutDisturbingTheListener() throws {
        let identity = try ownIdentity()
        let count = Mutex(0)
        let name = UUID().uuidString
        let listener = try #require(HelperListener(name: name, peers: ["self": identity]) { _, _ in
            count.withLock { $0 += 1 }
        })
        withExtendedLifetime(listener) {
            #expect(!HelperLink.send(Data(count: HelperLink.maximumMessageBytes + 1), to: name, peer: identity))
            #expect(HelperLink.send(Data([1]), to: name, peer: identity))
            #expect(count.withLock { $0 } == 1)
        }
    }

    @Test func matchingSignatureAtAnotherPathIsNotTheExpectedPeer() throws {
        let own = try ownIdentity()
        let executable = try #require(Bundle.main.executableURL)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let copy = directory.appendingPathComponent(executable.lastPathComponent)
        try FileManager.default.copyItem(at: executable, to: copy)
        let copiedIdentity = try #require(HelperPeerIdentity(executableURL: copy))
        let received = Mutex(false)
        let name = UUID().uuidString
        let listener = try #require(HelperListener(name: name, peers: ["copied": copiedIdentity]) { _, _ in
            received.withLock { $0 = true }
        })
        withExtendedLifetime(listener) {
            #expect(!HelperLink.send(Data([1]), to: name, peer: own))
            #expect(!received.withLock { $0 })
        }
    }

    @Test func anotherListenerCannotReplaceALiveEndpoint() throws {
        let identity = try ownIdentity()
        let received = Mutex(0)
        let name = UUID().uuidString
        let listener = try #require(HelperListener(name: name, peers: ["self": identity]) { _, _ in
            received.withLock { $0 += 1 }
        })
        withExtendedLifetime(listener) {
            #expect(HelperListener(name: name, peers: ["self": identity]) { _, _ in } == nil)
            #expect(HelperLink.send(Data([1]), to: name, peer: identity))
            #expect(received.withLock { $0 } == 1)
        }
    }
}
