import Foundation
@testable import RecAnimeCore
@testable import RecAnimeKit
import Testing

@Suite("EpisodeOutbox")
@MainActor
struct EpisodeOutboxTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test-\(UUID().uuidString)")!
    }

    @Test("a replayed target is sent once and removed")
    func successRemoves() async {
        let api = FakeAPI()
        let outbox = EpisodeOutbox(defaults: makeDefaults(), key: "outbox")
        outbox.enqueue(malID: 1, target: 3)
        #expect(outbox.isPending(1))
        let error = await outbox.replay(api: api)
        #expect(error == nil)
        #expect(outbox.isEmpty)
        #expect(api.adjustCalls.count == 1)
        #expect(api.adjustCalls.first?.1.episodesWatched == 3)
    }

    @Test("a transient server error keeps the entry queued")
    func serverErrorKeeps() async {
        let api = FakeAPI()
        api.adjustErrors = [.server(status: 503, code: "unavailable", message: nil)]
        let outbox = EpisodeOutbox(defaults: makeDefaults(), key: "outbox")
        outbox.enqueue(malID: 1, target: 3)
        let error = await outbox.replay(api: api)
        #expect(error == .server(status: 503, code: "unavailable", message: nil))
        #expect(outbox.isPending(1))
    }

    @Test("a permanent server error drops the entry")
    func permanentErrorDrops() async {
        let api = FakeAPI()
        api.adjustErrors = [.server(status: 404, code: "not_found", message: nil), .server(status: 422, code: "invalid", message: nil)]
        let outbox = EpisodeOutbox(defaults: makeDefaults(), key: "outbox")
        outbox.enqueue(malID: 1, target: 3)
        await outbox.replay(api: api)
        #expect(outbox.isEmpty)
        outbox.enqueue(malID: 2, target: 4)
        await outbox.replay(api: api)
        #expect(outbox.isEmpty)
    }

    @Test("an expired session keeps everything queued and stops the replay")
    func unauthorizedStops() async {
        let api = FakeAPI()
        api.adjustErrors = [.unauthorized, .unauthorized]
        let outbox = EpisodeOutbox(defaults: makeDefaults(), key: "outbox")
        outbox.enqueue(malID: 1, target: 3)
        outbox.enqueue(malID: 2, target: 4)
        let error = await outbox.replay(api: api)
        #expect(error == .unauthorized)
        #expect(outbox.pendingIDs == [1, 2])
        #expect(api.adjustCalls.count == 1)
    }

    @Test("an enqueue during the replay is not lost")
    func enqueueDuringReplay() async {
        let api = FakeAPI()
        let outbox = EpisodeOutbox(defaults: makeDefaults(), key: "outbox")
        outbox.enqueue(malID: 1, target: 3)
        let fired = Fired()
        api.onAdjust = { _, _ in
            guard !fired.value else { return }
            fired.value = true
            outbox.enqueue(malID: 1, target: 5)
        }
        await outbox.replay(api: api)
        #expect(outbox.isPending(1))
        api.onAdjust = nil
        await outbox.replay(api: api)
        #expect(outbox.isEmpty)
        #expect(api.adjustCalls.map(\.1.episodesWatched) == [3, 5])
    }

    @Test("a reentrant replay returns immediately")
    func reentrancy() async {
        let api = FakeAPI()
        let outbox = EpisodeOutbox(defaults: makeDefaults(), key: "outbox")
        outbox.enqueue(malID: 1, target: 3)
        let inner = Inner()
        api.onAdjust = { _, _ in
            guard !inner.ran else { return }
            inner.ran = true
            inner.result = await outbox.replay(api: api)
        }
        await outbox.replay(api: api)
        #expect(inner.ran)
        #expect(inner.result == nil)
        #expect(api.adjustCalls.count == 1)
        #expect(outbox.isEmpty)
    }

    @Test("the queue survives a relaunch and clear() persists")
    func persistence() {
        let defaults = makeDefaults()
        let outbox = EpisodeOutbox(defaults: defaults, key: "outbox")
        outbox.enqueue(malID: 7, target: 2)
        #expect(EpisodeOutbox(defaults: defaults, key: "outbox").isPending(7))
        outbox.clear()
        #expect(outbox.isEmpty)
        #expect(EpisodeOutbox(defaults: defaults, key: "outbox").isEmpty)
    }

    @Test("replay with nothing queued returns nil and never touches the API")
    func replayEmptyQueue() async {
        let api = FakeAPI()
        let outbox = EpisodeOutbox(defaults: makeDefaults(), key: "outbox")
        let error = await outbox.replay(api: api)
        #expect(error == nil)
        #expect(api.adjustCalls.isEmpty)
    }

    @Test("pendingIDs tracks enqueue and clear")
    func pendingIDsTracksEnqueueAndClear() {
        let outbox = EpisodeOutbox(defaults: makeDefaults(), key: "outbox")
        #expect(outbox.pendingIDs.isEmpty)
        outbox.enqueue(malID: 1, target: 3)
        outbox.enqueue(malID: 2, target: 4)
        #expect(outbox.pendingIDs == [1, 2])
        outbox.clear()
        #expect(outbox.pendingIDs.isEmpty)
    }

    @Test("multiple pending targets round-trip across instances sharing the same UserDefaults")
    func multiplePendingRoundTrip() async {
        let defaults = makeDefaults()
        let outbox = EpisodeOutbox(defaults: defaults, key: "outbox")
        outbox.enqueue(malID: 1, target: 3)
        outbox.enqueue(malID: 2, target: 4)

        // A second instance backed by the same defaults sees both targets, values included.
        let reloaded = EpisodeOutbox(defaults: defaults, key: "outbox")
        #expect(reloaded.pendingIDs == [1, 2])
        let api = FakeAPI()
        await reloaded.replay(api: api)
        #expect(Set(api.adjustCalls.map(\.0)) == [1, 2])
        #expect(api.adjustCalls.compactMap(\.1.episodesWatched).sorted() == [3, 4])
    }
}

/// Main-actor boxes so the `onAdjust` hooks can flag what happened.
@MainActor
private final class Fired {
    var value = false
}

@MainActor
private final class Inner {
    var ran = false
    var result: APIError?
}
