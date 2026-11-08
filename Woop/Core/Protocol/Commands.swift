import Foundation

/// Builders for host → strap COMMAND (0x23) frames.
///
/// Inner = `[0x23][seq][opcode][payload…]`, wrapped in the generation's envelope.
/// Bodies follow the hardware-verified shapes documented by OpenStrap/NOOP.
enum WhoopCommands {
    static func build(seq: UInt8, opcode: UInt8, payload: [UInt8], profile: BandProfile) -> [UInt8] {
        Framing.buildFrame([PacketType.command, seq, opcode] + payload, profile: profile)
    }

    /// 6-byte `[u32 sec LE][u16 subsec LE]` timestamp, subsec in 1/32768 s.
    static func timestampBytes(_ date: Date) -> [UInt8] {
        let ms = Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
        let sec = Int(ms / 1000)
        let subsec = Int((ms % 1000) * 32768 / 1000)
        return [UInt8].le32(sec) + [UInt8].le16(subsec)
    }

    /// gen5: GET_HELLO (0x91) `[0x01]` — mandatory first exchange after subscribing.
    /// gen4: GET_HELLO_HARVARD (0x23) `[0x00]`.
    static func hello(seq: UInt8, profile: BandProfile) -> [UInt8] {
        profile.isGen5
            ? build(seq: seq, opcode: Cmd.getHello, payload: [0x01], profile: profile)
            : build(seq: seq, opcode: Cmd.getHelloHarvard, payload: [0x00], profile: profile)
    }

    /// SET_CLOCK (0x0A): `[u32 sec][u32 subsec(1/32768)]` — 8 bytes on both generations.
    static func setClock(seq: UInt8, date: Date = Date(), profile: BandProfile) -> [UInt8] {
        build(seq: seq, opcode: Cmd.setClock, payload: timestampBytes(date) + [0, 0], profile: profile)
    }

    static func getClock(seq: UInt8, profile: BandProfile) -> [UInt8] {
        build(seq: seq, opcode: Cmd.getClock, payload: [], profile: profile)
    }

    static func linkValid(seq: UInt8, profile: BandProfile) -> [UInt8] {
        build(seq: seq, opcode: Cmd.linkValid, payload: [0x00], profile: profile)
    }

    static func getBattery(seq: UInt8, profile: BandProfile) -> [UInt8] {
        build(seq: seq, opcode: Cmd.getBatteryLevel, payload: [], profile: profile)
    }

    static func toggleRealtimeHR(seq: UInt8, on: Bool, profile: BandProfile) -> [UInt8] {
        build(seq: seq, opcode: Cmd.toggleRealtimeHr, payload: [on ? 0x01 : 0x00], profile: profile)
    }

    /// GET_DATA_RANGE (0x22): empty body on gen5, `[0x00]` on gen4.
    static func getDataRange(seq: UInt8, profile: BandProfile) -> [UInt8] {
        build(seq: seq, opcode: Cmd.getDataRange, payload: profile.isGen5 ? [] : [0x00], profile: profile)
    }

    /// SEND_HISTORICAL_DATA (0x16): starts the flash drain. Empty body on gen5, `[0x00]` on gen4.
    static func sendHistorical(seq: UInt8, profile: BandProfile) -> [UInt8] {
        build(seq: seq, opcode: Cmd.sendHistoricalData, payload: profile.isGen5 ? [] : [0x00], profile: profile)
    }

    /// HISTORICAL_DATA_RESULT (0x17) success: `[0x01] + verbatim 8-byte HISTORY_END token`.
    /// The strap trims its flash only after this ACK — send it only after the batch is durable.
    static func historyResultOK(seq: UInt8, token: [UInt8], profile: BandProfile) -> [UInt8]? {
        guard token.count == 8 else { return nil }
        return build(seq: seq, opcode: Cmd.historicalDataResult, payload: [Wire.revision1] + token, profile: profile)
    }

    /// HISTORICAL_DATA_RESULT failure: the strap re-offers the same batch.
    static func historyResultFail(seq: UInt8, profile: BandProfile) -> [UInt8] {
        build(seq: seq, opcode: Cmd.historicalDataResult, payload: profile.isGen5 ? [0x00, 0x00] : [0x00], profile: profile)
    }

    static func abortHistorical(seq: UInt8, profile: BandProfile) -> [UInt8] {
        build(seq: seq, opcode: Cmd.abortHistoricalTransmits, payload: [0x00], profile: profile)
    }

    static func getAdvertisingName(seq: UInt8, profile: BandProfile) -> [UInt8] {
        profile.isGen5
            ? build(seq: seq, opcode: Cmd.getCustomAdvertisingName, payload: [Wire.revision1], profile: profile)
            : build(seq: seq, opcode: Cmd.getAdvertisingNameHarvard, payload: [0x00], profile: profile)
    }

    /// Short haptic buzz. gen5 uses RUN_HAPTIC_PATTERN_MAVERICK (0x13) with the `[47, 152]`
    /// waveform pair; gen4 uses RUN_HAPTICS_PATTERN (0x4F).
    static func buzz(seq: UInt8, loops: Int = 1, profile: BandProfile) -> [UInt8] {
        if profile.isGen5 {
            let loop = UInt8(max(0, min(255, loops)))
            return build(seq: seq, opcode: Cmd.runHapticPatternMaverick,
                         payload: [0x01, 47, 152, 0, 0, 0, 0, 0, 0, 0, 0, loop], profile: profile)
        }
        return build(seq: seq, opcode: Cmd.runHapticsPattern, payload: [2, 0, 0, 0, 0], profile: profile)
    }

    /// Stock wake-buzz haptic pattern: 8 effect slots, u16 loop control, overall loop, max seconds.
    static let alarmHaptics: [UInt8] = [47, 152, 0, 0, 0, 0, 0, 0, 0, 0, 7, 30]

    /// SET_ALARM_TIME (0x42). gen5: rich 21-byte body at slot 1 (slot 0 is rejected) +
    /// crescendo flag. gen4: the REV-1 9-byte form the firmware executes.
    static func setAlarm(seq: UInt8, at date: Date, profile: BandProfile) -> [UInt8] {
        let ts = timestampBytes(date)
        if profile.isGen5 {
            let body: [UInt8] = [0x04, 0x01] + ts + alarmHaptics + [0x00]
            return build(seq: seq, opcode: Cmd.setAlarmTime, payload: body, profile: profile)
        }
        return build(seq: seq, opcode: Cmd.setAlarmTime, payload: [0x01] + ts + [0x00, 0x00], profile: profile)
    }

    /// DISABLE_ALARM (0x45). gen5: `[0x02][0xFF]` (all slots); gen4: `[0x01]`.
    static func disableAlarm(seq: UInt8, profile: BandProfile) -> [UInt8] {
        build(seq: seq, opcode: Cmd.disableAlarm, payload: profile.isGen5 ? [0x02, 0xFF] : [0x01], profile: profile)
    }

    /// gen4 five-packet INIT handshake (seq 0…4); the last packet starts the drain.
    static var gen4InitPackets: [[UInt8]] {
        let p = BandProfile.gen4
        return [
            build(seq: 0, opcode: Cmd.getHelloHarvard, payload: [0x00], profile: p),
            build(seq: 1, opcode: Cmd.getAdvertisingNameHarvard, payload: [0x00], profile: p),
            build(seq: 2, opcode: Cmd.getDataRange, payload: [0x00], profile: p),
            build(seq: 3, opcode: Cmd.getAlarmTime, payload: [Wire.revision1], profile: p),
            build(seq: 4, opcode: Cmd.sendHistoricalData, payload: [0x00], profile: p),
        ]
    }
}

/// Sequence allocator: live commands use 0xA0…0xFF, history ACKs use 5…0x9F, so their
/// replies never collide.
struct SeqAllocator {
    private var live: Int = 0xA0
    private var sync: Int = 5

    mutating func nextLive() -> UInt8 {
        let v = live
        live = live >= 0xFF ? 0xA0 : live + 1
        return UInt8(v)
    }

    mutating func nextSync() -> UInt8 {
        let v = sync
        sync = sync >= 0x9F ? 5 : sync + 1
        return UInt8(v)
    }

    mutating func reset() { live = 0xA0; sync = 5 }
}
