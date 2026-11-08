import XCTest
@testable import WoopCore

/// Golden tests against real, CRC-verified WHOOP 5.0 captures published with the OpenStrap
/// `protocol` project's test suite.
final class ProtocolTests: XCTestCase {
    func bytes(_ hex: String) -> [UInt8] { [UInt8](hex: hex)! }

    func testCRC16ModbusMatchesHelloHeader() {
        // header `aa 01 08 00 00 01` → 0x71E6
        XCTAssertEqual(CRC.crc16Modbus([0xAA, 0x01, 0x08, 0x00, 0x00, 0x01]), 0x71E6)
    }

    func testCRC8Table() {
        XCTAssertEqual(CRC.crc8([0x01]), 7)
        XCTAssertEqual(CRC.crc8([0x02]), 14)
    }

    func testGen5ClientHelloIsByteExact() {
        XCTAssertEqual(WhoopCommands.hello(seq: 1, profile: .gen5).hexString, "aa0108000001e67123019101363e5c8d")
    }

    func testGen5HistoryAckIsByteExact() {
        let ack = WhoopCommands.historyResultOK(seq: 0, token: bytes("41b6010010000000"), profile: .gen5)
        XCTAssertEqual(ack?.hexString, "aa0110000001e0d12300170141b6010010000000667da4fb")
    }

    func testGen5V18RealCapture() throws {
        let frame = bytes(
            "aa01740001003fb12f1280733d8401b69f266a66460066025a0265020000000"
            + "000007b0a8d656463ff0012163cf6a439bf2924fd3ed763fe3e3200aa000000"
            + "000000000000f7000901f10b0007010c020c000000000000000000000000000"
            + "00000000000000000000100656f1e1e0000009d61a7c00000003e862817")
        let parsed = try XCTUnwrap(Framing.parseFrame(frame, profile: .gen5))
        XCTAssertTrue(parsed.valid)
        XCTAssertEqual(parsed.inner[1], 18)
        let s = try XCTUnwrap(HistoryDecoder.decode(parsed.inner, profile: .gen5))
        XCTAssertEqual(s.ts, 1_780_916_150)
        XCTAssertEqual(s.hr, 102)
        XCTAssertEqual(s.rr, [602, 613])
        XCTAssertEqual(Double(s.gx), -0.7252, accuracy: 1e-3)
        XCTAssertEqual(Double(s.gy), 0.4944, accuracy: 1e-3)
        XCTAssertEqual(Double(s.gz), 0.4969, accuracy: 1e-3)
        XCTAssertEqual(Double(s.dynAccel), 0.00916, accuracy: 1e-3)
        XCTAssertTrue((0...3).contains(Int(s.sleepState)))
    }

    func testGen5RealtimeHR() throws {
        let frame = bytes("aa011800010022e128029ea0266aae4762025b024b020000000001005ed515dc")
        let parsed = try XCTUnwrap(Framing.parseFrame(frame, profile: .gen5))
        XCTAssertTrue(parsed.valid)
        let hr = try XCTUnwrap(RealtimeHR.parse(parsed.inner))
        XCTAssertEqual(hr.unix, 1_780_916_382)
        XCTAssertEqual(hr.bpm, 98)
        XCTAssertEqual(hr.rr, [603, 587])
        XCTAssertTrue(hr.wearing)
    }

    func testGen5HistoryEndMarker() throws {
        let frame = bytes("aa011c00010023d1319102b949596a705d3b000000fdba010010000000000000f269faec")
        let parsed = try XCTUnwrap(Framing.parseFrame(frame, profile: .gen5))
        XCTAssertTrue(parsed.valid)
        let m = try XCTUnwrap(HistoryMarker.parse(parsed.inner))
        XCTAssertEqual(m.sub, SyncMeta.historyEnd)
        let token = try XCTUnwrap(m.token)
        XCTAssertEqual(token.u32(0), 113_405)
    }

    func testReassemblerSplitsAndJoins() {
        let f1 = Framing.buildFrame([0x2F, 24, 0, 1, 0, 0, 0], profile: .gen5)
        let f2 = Framing.buildFrame([0x2F, 24, 0, 2, 0, 0, 0], profile: .gen5)
        let r = FrameReassembler(profile: .gen5)
        let got = r.feed(f1 + Array(f2[0..<5]))
        XCTAssertEqual(got.count, 1)
        XCTAssertTrue(got[0].valid)
        let rest = r.feed(Array(f2[5...]))
        XCTAssertEqual(rest.count, 1)
        XCTAssertTrue(rest[0].valid)
        XCTAssertEqual(rest[0].inner[3], 2)
    }

    func testReassemblerSurvivesSOFInsidePayload() {
        let inner: [UInt8] = [0x2F, 18, 0xAA, 0xAA, 0x01, 0xAA, 0x10, 0x00]
        let f = Framing.buildFrame(inner, profile: .gen5)
        let r = FrameReassembler(profile: .gen5)
        var frames: [Frame] = []
        for b in f { frames += r.feed([b]) } // one byte per notification
        XCTAssertEqual(frames.count, 1)
        XCTAssertTrue(frames[0].valid)
        XCTAssertEqual(Array(frames[0].inner.prefix(inner.count)), inner)
    }

    func testGen4RoundTrip() throws {
        let f = Framing.buildFrame([0x23, 0, 0x0B], profile: .gen4)
        let p = try XCTUnwrap(Framing.parseFrame(f, profile: .gen4))
        XCTAssertTrue(p.valid)
        XCTAssertEqual(WhoopCommands.gen4InitPackets.count, 5)
    }

    func testCommandShapes() {
        let clock = WhoopCommands.setClock(seq: 9, date: Date(timeIntervalSince1970: 1_780_000_000.5), profile: .gen5)
        let p = Framing.parseFrame(clock, profile: .gen5)!
        XCTAssertTrue(p.valid)
        XCTAssertEqual(p.inner[2], Cmd.setClock)
        XCTAssertEqual(p.inner.u32(3), 1_780_000_000)
        XCTAssertEqual(p.inner.u32(7), 16384) // 0.5 s in 1/32768 units
        let alarm = Framing.parseFrame(WhoopCommands.setAlarm(seq: 1, at: Date(timeIntervalSince1970: 1_780_000_000), profile: .gen5), profile: .gen5)!
        XCTAssertEqual(alarm.inner[3], 0x04)
        XCTAssertEqual(alarm.inner[4], 0x01) // slot 1
        XCTAssertEqual(alarm.inner.u32(5), 1_780_000_000)
    }

    func testGen5HelloParse() {
        var body = [UInt8](repeating: 0, count: 107)
        body[0] = 1
        body.replaceSubrange(1..<5, with: [UInt8].le32(873)) // 87.3 %
        body[5] = 1 // charging
        body.replaceSubrange(6..<10, with: [UInt8].le32(1_780_000_000))
        let serial = Array("4C1234567".utf8)
        body.replaceSubrange(14..<(14 + serial.count), with: serial)
        body.replaceSubrange(87..<91, with: [UInt8].le32(82))
        body[91] = 50; body[92] = 41; body[93] = 1
        body[102] = 1
        let inner: [UInt8] = [PacketType.commandResponse, 0xA0, Cmd.getHello, 0xA0, 1] + body
        let r = CommandResponse.parse(inner)!
        let h = r.gen5Hello!
        XCTAssertEqual(h.batteryPct, 87.3)
        XCTAssertTrue(h.charging)
        XCTAssertEqual(h.tsSeconds, 1_780_000_000)
        XCTAssertEqual(h.serial, "4C1234567")
        XCTAssertTrue(h.isWhoop5)
        XCTAssertEqual(h.firmware, "50.41.1.0")
        XCTAssertTrue(h.wristOn)
    }
}

final class DrainTests: XCTestCase {
    func v18Frame(ts: Int, hr: UInt8) -> Frame {
        var inner = [UInt8](repeating: 0, count: 112)
        inner[0] = PacketType.historicalData
        inner[1] = 18
        inner.replaceSubrange(7..<11, with: [UInt8].le32(ts))
        inner[14] = hr
        return Frame(inner: inner, headerOK: true, crc32OK: true, revisionOK: true)
    }

    func marker(_ sub: UInt8, expected: Int = 0, token: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8]) -> HistoryMarker {
        var inner = [UInt8](repeating: 0, count: 24)
        inner[0] = PacketType.metadata
        inner[2] = sub
        inner.replaceSubrange(9..<13, with: [UInt8].le32(expected))
        inner.replaceSubrange(13..<21, with: token)
        return HistoryMarker.parse(inner)!
    }

    func testOwnBurstCommitsThenAcks() {
        let d = HistoryDrain(profile: .gen5)
        d.beginOwnDrain()
        XCTAssertEqual(d.onMarker(marker(SyncMeta.historyStart)), .none)
        d.onHistoricalPacket(v18Frame(ts: 1_780_000_000, hr: 60))
        d.onHistoricalPacket(v18Frame(ts: 1_780_000_001, hr: 61))
        guard case let .commit(samples, _, token) = d.onMarker(marker(SyncMeta.historyEnd, expected: 2)) else {
            return XCTFail("expected commit")
        }
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(token, [1, 2, 3, 4, 5, 6, 7, 8])
        XCTAssertEqual(d.onMarker(marker(SyncMeta.historyComplete)), .complete)
    }

    func testShortBurstIsRefused() {
        let d = HistoryDrain(profile: .gen5)
        d.beginOwnDrain()
        _ = d.onMarker(marker(SyncMeta.historyStart))
        d.onHistoricalPacket(v18Frame(ts: 1_780_000_000, hr: 60))
        XCTAssertEqual(d.onMarker(marker(SyncMeta.historyEnd, expected: 3)), .refuse(shortfall: 2))
    }

    func testForeignBurstIsBankedButNeverAcked() {
        let d = HistoryDrain(profile: .gen5)
        _ = d.onMarker(marker(SyncMeta.historyStart))
        d.onHistoricalPacket(v18Frame(ts: 1_780_000_000, hr: 60))
        guard case let .commit(samples, _, token) = d.onMarker(marker(SyncMeta.historyEnd, expected: 1)) else {
            return XCTFail("expected commit")
        }
        XCTAssertEqual(samples.count, 1)
        XCTAssertNil(token)
    }

    func testUnclockedRecordsAreNeverBanked() {
        let d = HistoryDrain(profile: .gen5)
        d.beginOwnDrain()
        _ = d.onMarker(marker(SyncMeta.historyStart))
        d.onHistoricalPacket(v18Frame(ts: 31_000_000, hr: 60)) // 1970/71: strap RTC unset
        guard case let .commit(samples, _, token) = d.onMarker(marker(SyncMeta.historyEnd, expected: 1)) else {
            return XCTFail("expected commit")
        }
        XCTAssertTrue(samples.isEmpty)
        XCTAssertNotNil(token)
    }
}
