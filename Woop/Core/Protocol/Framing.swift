import Foundation

/// Per-generation frame envelope.
///
/// gen4: `[0xAA][u16 LE declared][crc8(len bytes)] + inner(padded /4) + u32 LE crc32`
/// gen5: `[0xAA][0x01][u16 LE declared][dir0][dir1][u16 LE crc16modbus(hdr[0..<6])] + inner + crc32`
///
/// `declared` = padded inner length + 4 (the trailing CRC-32).
struct BandProfile: Sendable, Equatable {
    let generation: BandGeneration

    static let gen4 = BandProfile(generation: .gen4)
    static let gen5 = BandProfile(generation: .gen5)
    static func of(_ g: BandGeneration) -> BandProfile { g == .gen5 ? .gen5 : .gen4 }

    var isGen5: Bool { generation == .gen5 }
    var headerLen: Int { isGen5 ? 8 : 4 }
    var sizeFieldOffset: Int { isGen5 ? 2 : 1 }

    func declaredLen(_ b: [UInt8], at base: Int = 0) -> Int {
        let o = base + sizeFieldOffset
        guard o + 1 < b.count else { return 0 }
        return Int(b[o]) | (Int(b[o + 1]) << 8)
    }

    func headerValid(_ b: [UInt8], at base: Int = 0) -> Bool {
        if isGen5 {
            guard base + 8 <= b.count else { return false }
            let want = Int(b[base + 6]) | (Int(b[base + 7]) << 8)
            return Int(CRC.crc16Modbus(b[base..<(base + 6)])) == want
        }
        guard base + 4 <= b.count else { return false }
        return b[base + 3] == CRC.crc8([b[base + 1], b[base + 2]])
    }

    /// Header for an OUTBOUND (host → strap) command frame.
    func buildHeader(declared: Int) -> [UInt8] {
        let lo = UInt8(declared & 0xFF), hi = UInt8((declared >> 8) & 0xFF)
        if isGen5 {
            var h: [UInt8] = [Wire.sof, 0x01, lo, hi, 0x00, 0x01]
            let c = CRC.crc16Modbus(h)
            h.append(UInt8(c & 0xFF))
            h.append(UInt8(c >> 8))
            return h
        }
        return [Wire.sof, lo, hi, CRC.crc8([lo, hi])]
    }
}

/// A parsed frame envelope.
struct Frame: Sendable {
    /// Padded inner payload: `[packetType][seq/version][opcode/...][body…]`.
    let inner: [UInt8]
    let headerOK: Bool
    let crc32OK: Bool
    /// gen5 header[1] must be the revision-1 marker for the rev-1 inner offsets to hold.
    let revisionOK: Bool

    var valid: Bool { headerOK && crc32OK }
    var decodable: Bool { valid && revisionOK }
    var packetType: UInt8 { inner.first ?? 0 }
    var seq: UInt8 { inner.count > 1 ? inner[1] : 0 }
    var opcode: UInt8 { inner.count > 2 ? inner[2] : 0 }
}

enum Framing {
    static func pad4(_ data: [UInt8]) -> [UInt8] {
        let rem = data.count % 4
        return rem == 0 ? data : data + [UInt8](repeating: 0, count: 4 - rem)
    }

    static func buildFrame(_ inner: [UInt8], profile: BandProfile) -> [UInt8] {
        let padded = pad4(inner)
        let declared = padded.count + 4
        let crc = CRC.crc32(padded)
        return profile.buildHeader(declared: declared) + padded + [UInt8].le32(Int(crc))
    }

    /// Parse exactly one complete frame starting at index 0.
    static func parseFrame(_ raw: [UInt8], profile: BandProfile) -> Frame? {
        let h = profile.headerLen
        guard raw.count >= h + 4, raw[0] == Wire.sof else { return nil }
        let declared = profile.declaredLen(raw)
        guard declared >= 4 else { return nil }
        let total = h + declared
        guard raw.count >= total else { return nil }
        let inner = Array(raw[h..<(h + declared - 4)])
        let stored = raw.u32(h + declared - 4)
        let revOK = !profile.isGen5 || raw[1] == Wire.revision1
        return Frame(inner: inner,
                     headerOK: profile.headerValid(raw),
                     crc32OK: UInt32(truncatingIfNeeded: stored) == CRC.crc32(inner),
                     revisionOK: revOK)
    }
}

/// Length-based frame reassembler. BLE notifications split frames arbitrarily and
/// sensor payloads contain 0xAA, so frames are carved by declared length, never by SOF.
final class FrameReassembler {
    let profile: BandProfile
    private var buf: [UInt8] = []
    private(set) var resyncs = 0
    private(set) var lostFrames = 0

    init(profile: BandProfile) { self.profile = profile }

    func reset() {
        buf.removeAll(keepingCapacity: true)
        resyncs = 0
        lostFrames = 0
    }

    /// Feed a notification chunk; returns every complete frame carved out of the buffer.
    func feed(_ chunk: [UInt8]) -> [Frame] {
        var out: [Frame] = []
        buf.append(contentsOf: chunk)
        let h = profile.headerLen

        func resync() -> Bool {
            resyncs += 1
            if let next = buf.dropFirst().firstIndex(of: Wire.sof) {
                buf.removeSubrange(0..<next)
                return true
            }
            buf.removeAll(keepingCapacity: true)
            return false
        }

        while buf.count >= h + 4 {
            if buf[0] != Wire.sof {
                if !resync() { break }
                continue
            }
            let declared = profile.declaredLen(buf)
            let total = h + declared
            if declared < 4 || total > 4096 {
                if !resync() { break }
                continue
            }
            // The header check protects only the length field; verify it before trusting it.
            if !profile.headerValid(buf) {
                if !resync() { break }
                continue
            }
            if buf.count < total { break } // wait for the rest of this frame
            guard let frame = Framing.parseFrame(Array(buf[0..<total]), profile: profile) else {
                if !resync() { break }
                continue
            }
            out.append(frame)
            if !frame.valid { lostFrames += 1 }
            if !frame.crc32OK {
                // A payload CRC failure means `declared` itself may be corrupt: resync instead
                // of stepping over a possibly wrong length (which would swallow good frames).
                if !resync() { break }
                continue
            }
            buf.removeSubrange(0..<total)
            // Skip inter-record NUL padding.
            if let firstNonZero = buf.firstIndex(where: { $0 != 0 }) {
                if firstNonZero > 0 { buf.removeSubrange(0..<firstNonZero) }
            } else {
                buf.removeAll(keepingCapacity: true)
            }
        }
        if buf.count > 8192 { buf.removeAll(keepingCapacity: true) }
        return out
    }
}
