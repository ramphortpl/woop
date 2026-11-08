import Foundation

/// WHOOP wire-protocol constants (uncopyrightable protocol facts, as documented by
/// OpenStrap `protocol` and NOOP `WhoopProtocol`).
enum Wire {
    static let sof: UInt8 = 0xAA
    static let revision1: UInt8 = 0x01
}

/// Generation of the strap. WHOOP 5.0 / MG speak the "gen5" (fd4b) envelope;
/// WHOOP 4.0 speaks the "gen4" (6108) envelope. Inner payloads are shared.
enum BandGeneration: String, Codable, CaseIterable, Sendable {
    case gen4
    case gen5

    var label: String { self == .gen5 ? "WHOOP 5.0 / MG" : "WHOOP 4.0" }
}

/// GATT service / characteristic UUID strings. Wrapped in CBUUID by the BLE layer.
struct GattProfile: Sendable {
    let service: String
    let cmdTo: String      // write (with response) app → strap
    let cmdFrom: String    // notify: command responses
    let events: String     // notify: events
    let data: String       // notify: realtime + historical data
    let memfault: String   // notify: diagnostics (optional)

    static let gen4 = GattProfile(
        service: "61080001-8D6D-82B8-614A-1C8CB0F8DCC6",
        cmdTo: "61080002-8D6D-82B8-614A-1C8CB0F8DCC6",
        cmdFrom: "61080003-8D6D-82B8-614A-1C8CB0F8DCC6",
        events: "61080004-8D6D-82B8-614A-1C8CB0F8DCC6",
        data: "61080005-8D6D-82B8-614A-1C8CB0F8DCC6",
        memfault: "61080007-8D6D-82B8-614A-1C8CB0F8DCC6")

    static let gen5 = GattProfile(
        service: "FD4B0001-CCE1-4033-93CE-002D5875F58A",
        cmdTo: "FD4B0002-CCE1-4033-93CE-002D5875F58A",
        cmdFrom: "FD4B0003-CCE1-4033-93CE-002D5875F58A",
        events: "FD4B0004-CCE1-4033-93CE-002D5875F58A",
        data: "FD4B0005-CCE1-4033-93CE-002D5875F58A",
        memfault: "FD4B0007-CCE1-4033-93CE-002D5875F58A")

    static func of(_ g: BandGeneration) -> GattProfile { g == .gen5 ? gen5 : gen4 }

    /// 16-bit member UUID some WHOOP 5 straps advertise.
    static let whoopMemberUUID16 = "FD4B"
    /// Standard Bluetooth SIG services the strap also exposes.
    static let heartRateService = "180D"
    static let heartRateMeasurement = "2A37"
    static let batteryService = "180F"
    static let batteryLevel = "2A19"
}

/// inner[0] packet type.
enum PacketType {
    static let command: UInt8 = 0x23
    static let commandResponse: UInt8 = 0x24
    static let puffinCommand: UInt8 = 0x25
    static let puffinCommandResponse: UInt8 = 0x26
    static let realtimeData: UInt8 = 0x28
    static let realtimeRawData: UInt8 = 0x2B
    static let historicalData: UInt8 = 0x2F
    static let event: UInt8 = 0x30
    static let metadata: UInt8 = 0x31
    static let consoleLogs: UInt8 = 0x32
    static let realtimeImu: UInt8 = 0x33
    static let historicalImu: UInt8 = 0x34
    static let relativePuffinEvents: UInt8 = 0x35
    static let puffinEventsFromStrap: UInt8 = 0x36
    static let relativeBatteryPackConsoleLogs: UInt8 = 0x37
    static let puffinMetadata: UInt8 = 0x38

    /// Packet types that are members of a history burst's declared packet count
    /// (besides the historical data packets themselves).
    static func isBurstCountMember(_ t: UInt8) -> Bool {
        t == event || t == consoleLogs || t == relativePuffinEvents
            || t == puffinEventsFromStrap || t == relativeBatteryPackConsoleLogs
    }
}

/// Command opcodes (inner[2] of a 0x23 COMMAND).
enum Cmd {
    static let linkValid: UInt8 = 0x01
    static let toggleRealtimeHr: UInt8 = 0x03
    static let setClock: UInt8 = 0x0A
    static let getClock: UInt8 = 0x0B
    static let runHapticPatternMaverick: UInt8 = 0x13 // gen5 buzz
    static let abortHistoricalTransmits: UInt8 = 0x14
    static let sendHistoricalData: UInt8 = 0x16
    static let historicalDataResult: UInt8 = 0x17
    static let getBatteryLevel: UInt8 = 0x1A
    static let getDataRange: UInt8 = 0x22
    static let getHelloHarvard: UInt8 = 0x23 // gen4 hello
    static let sendEventPackets: UInt8 = 0x30
    static let sendR10R11Realtime: UInt8 = 0x3F // gen4 only
    static let setAlarmTime: UInt8 = 0x42
    static let getAlarmTime: UInt8 = 0x43
    static let runAlarm: UInt8 = 0x44
    static let disableAlarm: UInt8 = 0x45
    static let getAdvertisingNameHarvard: UInt8 = 0x4C // gen4
    static let runHapticsPattern: UInt8 = 0x4F // gen4 buzz
    static let toggleImuMode: UInt8 = 0x6A
    static let stopHaptics: UInt8 = 0x7A
    static let getCustomAdvertisingName: UInt8 = 0x8D // gen5
    static let getHello: UInt8 = 0x91 // gen5 hello

    /// Opcodes that can erase flash, reboot, brick or persistently reconfigure the strap.
    /// The BLE layer refuses to send any of these.
    static let dangerous: Set<UInt8> = [
        0x19, // force trim
        0x21, // set read pointer
        0x9A, 0x99, // persistent IMU / optical save
        119, 120, // persistent config writes
        0x0E, // generic HR profile (NV)
        0x94, // wear detect override
        0x95, 0x8A, // LED accessibility / signal config
        0x0F, // forget bonds
        0x1D, 0x20, // reboot / power cycle
        0x24, 0x25, 0x26, 0x8E, 0x8F, 0x90, // firmware update
    ]
}

/// METADATA (0x31) sub-type at inner[2].
enum SyncMeta {
    static let historyStart: UInt8 = 1
    static let historyEnd: UInt8 = 2
    static let historyComplete: UInt8 = 3
}

/// EVENT (0x30) ids at inner[2..4].
enum EventID {
    static let batteryLevel = 3
    static let chargingOn = 7
    static let chargingOff = 8
    static let wristOn = 9
    static let wristOff = 10
    static let rtcLost = 13
    static let doubleTap = 14
    static let boot = 15
    static let setRtc = 16
    static let bleBonded = 31
    static let bleRealtimeHrOn = 33
    static let bleRealtimeHrOff = 34
    static let strapConditionReport = 29
    static let strapDrivenAlarmSet = 56
    static let strapDrivenAlarmExecuted = 57
    static let hapticsFired = 60
    static let hapticsTerminated = 100
}

/// Physiological bounds for beat-to-beat intervals (ms).
enum RRBounds {
    static let min = 200
    static let max = 2500
}
