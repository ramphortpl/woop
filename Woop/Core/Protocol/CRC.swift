import Foundation

/// Checksums used by the WHOOP wire format.
///
/// - WHOOP 4.0 ("gen4"): CRC-8 (poly 0x07) over the 2 length bytes of the 4-byte header.
/// - WHOOP 5.0 / MG ("gen5"): CRC-16/MODBUS over the first 6 bytes of the 8-byte header.
/// - Both: zlib CRC-32 over the 4-byte padded inner payload.
///
/// Protocol facts documented by the OpenStrap `protocol` project and NOOP's `WhoopProtocol`.
enum CRC {
    private static let crc8Table: [UInt8] = {
        (0..<256).map { i -> UInt8 in
            var c = UInt8(i)
            for _ in 0..<8 { c = (c & 0x80) != 0 ? (c << 1) ^ 0x07 : (c << 1) }
            return c
        }
    }()

    private static let crc32Table: [UInt32] = {
        (0..<256).map { n -> UInt32 in
            var c = UInt32(n)
            for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1) }
            return c
        }
    }()

    static func crc8<S: Sequence>(_ data: S) -> UInt8 where S.Element == UInt8 {
        var crc: UInt8 = 0
        for b in data { crc = crc8Table[Int(crc ^ b)] }
        return crc
    }

    static func crc16Modbus<S: Sequence>(_ data: S) -> UInt16 where S.Element == UInt8 {
        var crc: UInt16 = 0xFFFF
        for b in data {
            crc ^= UInt16(b)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xA001 : (crc >> 1)
            }
        }
        return crc
    }

    static func crc32<S: Sequence>(_ data: S) -> UInt32 where S.Element == UInt8 {
        var crc: UInt32 = 0xFFFF_FFFF
        for b in data { crc = crc32Table[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }
}

// MARK: - Little-endian readers over byte arrays

extension Array where Element == UInt8 {
    @inline(__always) func u16(_ o: Int) -> Int {
        guard o >= 0, o + 2 <= count else { return 0 }
        return Int(self[o]) | (Int(self[o + 1]) << 8)
    }

    @inline(__always) func i16(_ o: Int) -> Int {
        let v = u16(o)
        return v >= 0x8000 ? v - 0x10000 : v
    }

    @inline(__always) func u32(_ o: Int) -> Int {
        guard o >= 0, o + 4 <= count else { return 0 }
        return Int(self[o]) | (Int(self[o + 1]) << 8) | (Int(self[o + 2]) << 16) | (Int(self[o + 3]) << 24)
    }

    @inline(__always) func f32(_ o: Int) -> Float {
        guard o >= 0, o + 4 <= count else { return .nan }
        return Float(bitPattern: UInt32(truncatingIfNeeded: u32(o)))
    }

    var hexString: String { map { String(format: "%02x", $0) }.joined() }

    init?(hex: String) {
        let s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(s.count / 2)
        var idx = s.startIndex
        while idx < s.endIndex {
            let next = s.index(idx, offsetBy: 2)
            guard let b = UInt8(s[idx..<next], radix: 16) else { return nil }
            out.append(b)
            idx = next
        }
        self = out
    }
}

extension Array where Element == UInt8 {
    static func le32(_ v: Int) -> [UInt8] {
        [UInt8(truncatingIfNeeded: v), UInt8(truncatingIfNeeded: v >> 8),
         UInt8(truncatingIfNeeded: v >> 16), UInt8(truncatingIfNeeded: v >> 24)]
    }

    static func le16(_ v: Int) -> [UInt8] {
        [UInt8(truncatingIfNeeded: v), UInt8(truncatingIfNeeded: v >> 8)]
    }
}
