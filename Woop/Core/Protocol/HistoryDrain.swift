import Foundation

/// Pure state machine for the strap's history offload ("drain").
///
/// The strap streams its flash in bursts: `HISTORY_START`, N data/event packets,
/// `HISTORY_END(token, expectedCount)`, … `HISTORY_COMPLETE`. After each END the host must
/// persist the burst and only THEN echo the 8-byte token (the strap trims flash on that ACK).
///
/// Invariants (from OpenStrap edge's hardware-verified engine):
/// - commit before ACK, never ACK a partial burst;
/// - if fewer packets arrived than the strap declared, refuse the burst (the strap re-offers it);
/// - bursts we did not request (another app on the same phone driving the sync) are banked but
///   never acknowledged by us.
final class HistoryDrain {
    enum Decision: Equatable {
        case none
        /// Persist these samples durably, then (if `ackToken` != nil) send the success ACK.
        case commit(samples: [HistorySample], events: [StoredEvent], ackToken: [UInt8]?)
        /// Burst incomplete: discard it and send the failure result so the strap re-sends it.
        case refuse(shortfall: Int)
        /// Too many refused attempts: abort the transfer for this connection.
        case abort
        /// The strap has no more history.
        case complete
    }

    let profile: BandProfile
    /// True while a drain we requested is in flight.
    private(set) var ownDrainActive = false
    private(set) var inBurst = false
    private var samples: [HistorySample] = []
    private var events: [StoredEvent] = []
    private var burstPackets = 0
    private var consecutiveFailures = 0
    private(set) var totalSamples = 0
    private(set) var totalBursts = 0
    private(set) var newestTs: Int?

    static let attemptLimit = 15

    init(profile: BandProfile) { self.profile = profile }

    func beginOwnDrain() {
        ownDrainActive = true
        consecutiveFailures = 0
    }

    func endOwnDrain() {
        ownDrainActive = false
        inBurst = false
        samples.removeAll()
        events.removeAll()
        burstPackets = 0
    }

    /// A historical data packet (0x2F). Returns the decoded sample (also buffered).
    @discardableResult
    func onHistoricalPacket(_ frame: Frame) -> HistorySample? {
        burstPackets += 1
        guard let s = HistoryDecoder.decode(frame.inner, profile: profile) else { return nil }
        guard plausibleUnix(s.ts) else { return nil } // un-clocked strap: never bank 1970 records
        samples.append(s)
        return s
    }

    /// Any other burst-count member (events, console logs, battery-pack packets).
    func onBurstMember(_ frame: Frame) {
        burstPackets += 1
        if frame.packetType == PacketType.event, let e = StrapEvent.parse(frame.inner), plausibleUnix(e.unix) {
            events.append(StoredEvent(ts: e.unix, id: e.id, body: e.body))
        }
    }

    func onMarker(_ m: HistoryMarker) -> Decision {
        switch m.sub {
        case SyncMeta.historyStart:
            // A START during an open burst means the strap restarted it: drop the partial chunk.
            samples.removeAll()
            events.removeAll()
            burstPackets = 0
            inBurst = true
            return .none

        case SyncMeta.historyEnd:
            guard let token = m.token else { return .none }
            let expected = m.expectedPacketCount ?? 0
            let slack = consecutiveFailures >= 3 ? 2 : 0
            let received = burstPackets
            let haveSamples = samples
            let haveEvents = events
            samples.removeAll()
            events.removeAll()
            burstPackets = 0
            inBurst = false
            if !ownDrainActive {
                // Someone else's transfer: bank what we saw, never answer for them.
                record(haveSamples)
                return haveSamples.isEmpty && haveEvents.isEmpty ? .none
                    : .commit(samples: haveSamples, events: haveEvents, ackToken: nil)
            }
            if expected > 0 && received + slack < expected {
                consecutiveFailures += 1
                if consecutiveFailures >= Self.attemptLimit { return .abort }
                return .refuse(shortfall: expected - received)
            }
            consecutiveFailures = 0
            totalBursts += 1
            record(haveSamples)
            return .commit(samples: haveSamples, events: haveEvents, ackToken: token)

        case SyncMeta.historyComplete:
            let wasOwn = ownDrainActive
            ownDrainActive = false
            inBurst = false
            samples.removeAll()
            events.removeAll()
            burstPackets = 0
            return wasOwn ? .complete : .none

        default:
            return .none
        }
    }

    private func record(_ batch: [HistorySample]) {
        totalSamples += batch.count
        if let last = batch.map(\.ts).max() { newestTs = max(newestTs ?? 0, last) }
    }
}

/// A strap event persisted alongside the samples (wrist on/off, charging, double tap…).
struct StoredEvent: Equatable, Sendable, Codable {
    let ts: Int
    let id: Int
    let body: [UInt8]
}
