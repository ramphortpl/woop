import Foundation

/// A plausible wall-clock epoch (2023-11 … 2100). Used to sanity-check a field read at a
/// known offset — never to scan for one.
@inline(__always) func plausibleUnix(_ v: Int) -> Bool { v >= 1_700_000_000 && v <= 4_102_444_800 }

// MARK: - HELLO (gen5, GET_HELLO 0x91 reply body)

/// WHOOP 5.0 / MG hello body (revision 1): a fixed 104-byte map read at absolute offsets.
struct Gen5Hello: Equatable, Sendable {
    let revision: Int
    let batteryPct: Double?
    let charging: Bool
    let tsSeconds: Int
    let tsSubseconds: Int
    let serial: String
    let opticalDiscriminator: Int
    let firmware: String
    let wristOn: Bool

    static let semanticBodyLen = 104

    var isWhoop5: Bool { opticalDiscriminator >= 48 && opticalDiscriminator < 86 }
    var isMG: Bool { revision == 1 && opticalDiscriminator < 38 }
    var modelName: String { isMG ? "WHOOP MG" : "WHOOP 5.0" }
    var timestampOrNil: Int? { plausibleUnix(tsSeconds) ? tsSeconds : nil }

    /// `body` = bytes after the 5-byte command-response header (`inner[5...]`).
    static func parse(_ body: [UInt8]) -> Gen5Hello? {
        guard body.count >= semanticBodyLen else { return nil }
        func cstr(_ a: Int, _ b: Int) -> String {
            var s = ""
            for i in a..<min(b, body.count) {
                let c = body[i]
                if c == 0 { break }
                if c < 0x20 || c >= 0x7F { return "" }
                s.append(Character(UnicodeScalar(c)))
            }
            return s
        }
        let batteryRaw = body.u32(1)
        return Gen5Hello(
            revision: Int(body[0]),
            batteryPct: batteryRaw <= 1000 ? Double(batteryRaw) / 10.0 : nil,
            charging: (body[5] & 0x01) != 0,
            tsSeconds: body.u32(6),
            tsSubseconds: body.u32(10),
            serial: cstr(14, 25),
            opticalDiscriminator: body.u32(87),
            firmware: "\(body[91]).\(body[92]).\(body[93]).\(body.u32(94))",
            wristOn: body[102] == 1)
    }
}

// MARK: - COMMAND_RESPONSE (0x24)

/// inner = `[0x24][seq][opcode][echoed req seq][status][body…]`.
/// status: 0 failure, 1 success, 2 pending (a real reply follows), 3 unsupported.
struct CommandResponse: Sendable {
    let opcode: UInt8
    let requestSeq: UInt8?
    let status: Int
    let body: [UInt8]
    let raw: [UInt8]

    var success: Bool { status == 1 }
    var pending: Bool { status == 2 }

    static func parse(_ inner: [UInt8]) -> CommandResponse? {
        guard inner.count >= 3, inner[0] == PacketType.commandResponse else { return nil }
        return CommandResponse(
            opcode: inner[2],
            requestSeq: inner.count >= 4 ? inner[3] : nil,
            status: inner.count >= 5 ? Int(inner[4]) : -1,
            body: inner.count > 5 ? Array(inner[5...]) : [],
            raw: inner)
    }

    /// GET_BATTERY_LEVEL: gen5 = direct percent u8 @ inner[5]; gen4 = deci-percent u16 @ inner[5].
    func batteryPct(profile: BandProfile) -> Double? {
        guard opcode == Cmd.getBatteryLevel else { return nil }
        if profile.isGen5 {
            guard success, raw.count >= 6 else { return nil }
            let p = Double(raw[5])
            return (0...100).contains(p) ? p : nil
        }
        guard raw.count >= 7 else { return nil }
        let p = Double(raw.u16(5)) / 10.0
        return (0...100).contains(p) ? p : nil
    }

    var gen5Hello: Gen5Hello? {
        guard opcode == Cmd.getHello, success else { return nil }
        return Gen5Hello.parse(body)
    }

    /// GET_CLOCK reply: gen4/gen5 opcode 0x0B → `[u32 sec][u32 subsec]` at body[0].
    var clockEpoch: Int? {
        guard opcode == Cmd.getClock, raw.count >= 9 else { return nil }
        let v = raw.u32(5)
        return plausibleUnix(v) ? v : nil
    }

    /// GET_DATA_RANGE reply: oldest @ payload[35], newest @ payload[59] (payload = inner[3...]).
    var dataRange: (oldest: Int, newest: Int)? {
        guard opcode == Cmd.getDataRange, raw.count >= 66, raw[5] == 1 else { return nil }
        let oldest = raw.u32(3 + 35), newest = raw.u32(3 + 59)
        guard plausibleUnix(oldest), plausibleUnix(newest), oldest <= newest else { return nil }
        return (oldest, newest)
    }

    /// GET_CUSTOM_ADVERTISING_NAME (gen5) / GET_ADVERTISING_NAME (gen4): length @ inner[7], name @ inner[8…].
    var advertisingName: String? {
        guard opcode == Cmd.getCustomAdvertisingName || opcode == Cmd.getAdvertisingNameHarvard,
              success, raw.count > 8 else { return nil }
        let len = Int(raw[7])
        guard len > 0, len <= 24 else { return nil }
        var s = ""
        for i in 8..<min(8 + len, raw.count) {
            let c = raw[i]
            if c == 0 { break }
            if c >= 0x20 && c < 0x7F { s.append(Character(UnicodeScalar(c))) }
        }
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }
}

// MARK: - EVENT (0x30)

/// inner = `[0x30][seq][u16 event id][u32 unix][u16 subsec][u16 body len][body…]`.
struct StrapEvent: Sendable {
    let id: Int
    let unix: Int
    let body: [UInt8]

    static func parse(_ inner: [UInt8]) -> StrapEvent? {
        guard inner.count >= 4, inner[0] == PacketType.event else { return nil }
        var body: [UInt8] = []
        if inner.count >= 12 {
            let end = min(inner.count, 12 + inner.u16(10))
            if end > 12 { body = Array(inner[12..<end]) }
        }
        return StrapEvent(id: inner.u16(2), unix: inner.count >= 8 ? inner.u32(4) : 0, body: body)
    }

    /// BATTERY_LEVEL event: `[rev][u32 soc×10][u32 mV][charging]…`.
    var batteryPct: Double? {
        guard id == EventID.batteryLevel, body.count >= 12 else { return nil }
        let soc = Double(body.u32(1)) / 10.0
        return (0...100).contains(soc) ? soc : nil
    }

    var batteryCharging: Bool? {
        guard id == EventID.batteryLevel, body.count >= 12, batteryPct != nil else { return nil }
        return body[9] != 0
    }
}

// MARK: - METADATA (0x31) sync markers

struct HistoryMarker: Sendable {
    let sub: UInt8
    /// HISTORY_END only: packets the strap says this burst contained.
    let expectedPacketCount: Int?
    /// HISTORY_END only: the 8 bytes to echo verbatim in the ACK.
    let token: [UInt8]?
    let strapClock: Int?

    static func parse(_ inner: [UInt8]) -> HistoryMarker? {
        guard inner.count >= 3, inner[0] == PacketType.metadata else { return nil }
        let sub = inner[2]
        var expected: Int?
        var token: [UInt8]?
        var clock: Int?
        if sub == SyncMeta.historyEnd, inner.count >= 13 {
            expected = inner.u32(9)
            let c = inner.u32(3)
            clock = plausibleUnix(c) ? c : nil
        }
        if sub == SyncMeta.historyEnd, inner.count >= 21 {
            token = Array(inner[13..<21])
        }
        return HistoryMarker(sub: sub, expectedPacketCount: expected, token: token, strapClock: clock)
    }
}

// MARK: - Realtime HR (0x28 compact form)

/// inner = `[0x28][rev][u32 unix @2][u16 subsec @6][hr @8][rr count @9][4×u16 rr @10][wearing @18]`.
struct RealtimeHR: Sendable {
    let unix: Int
    let bpm: Int
    let rr: [Int]
    let wearing: Bool

    static func parse(_ inner: [UInt8]) -> RealtimeHR? {
        guard inner.count >= 9, inner[0] == PacketType.realtimeData else { return nil }
        let hr = Int(inner[8])
        guard hr <= 250 else { return nil }
        var rr: [Int] = []
        let n = inner.count > 9 ? Int(inner[9]) : 0
        if n > 0 && n <= 4 {
            for i in 0..<n {
                let off = 10 + 2 * i
                guard off + 2 <= inner.count else { break }
                let v = inner.u16(off)
                if v >= RRBounds.min && v <= RRBounds.max { rr.append(v) }
            }
        }
        let wearing = inner.count > 18 ? inner[18] == 1 : hr > 0
        return RealtimeHR(unix: inner.u32(2), bpm: hr, rr: rr, wearing: wearing && hr > 0)
    }
}
