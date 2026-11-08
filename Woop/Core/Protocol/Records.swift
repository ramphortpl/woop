import Foundation

/// One second of strap history, band-agnostic. Compact fixed-size layout (no heap arrays)
/// because a day holds up to 86 400 of these.
///
/// Absent fields use sentinels: `.nan` for floats, `-1` for integers.
struct HistorySample: Equatable, Sendable {
    var ts: Int
    /// bpm; 0 = no reading this second (off-skin / warming up).
    var hr: UInt8
    var rrCount: UInt8 = 0
    var rr0: UInt16 = 0
    var rr1: UInt16 = 0
    var rr2: UInt16 = 0
    var rr3: UInt16 = 0
    /// Per-axis mean acceleration (g).
    var gx: Float = .nan
    var gy: Float = .nan
    var gz: Float = .nan
    /// Max adjacent acceleration-magnitude delta in this second (g) — gen5 only.
    var dynAccel: Float = .nan
    /// Cumulative on-chip step counter (u16, wraps) — gen5 only.
    var stepCounter: Int32 = -1
    var cadence: Int16 = -1
    /// 0 unclassified, 1 walk, 2 run; -1 absent.
    var activityClass: Int8 = -1
    /// Skin temperature °C (gen5 AS6221 sensor).
    var skinTemp: Float = .nan
    /// Band's own envelope: 0 wake, 1 still, 2 sleep, 3 up; -1 absent.
    var sleepState: Int8 = -1
    /// Raw SpO₂ estimate/status byte (gen5, overnight only); -1 absent.
    var spo2Raw: Int16 = -1
    /// Band's per-second optical signal log-variance (lower = cleaner).
    var quality: Float = .nan

    init(ts: Int, hr: UInt8) {
        self.ts = ts
        self.hr = hr
    }

    var rr: [Int] {
        var out: [Int] = []
        let n = Int(rrCount)
        if n > 0 { out.append(Int(rr0)) }
        if n > 1 { out.append(Int(rr1)) }
        if n > 2 { out.append(Int(rr2)) }
        if n > 3 { out.append(Int(rr3)) }
        return out
    }

    mutating func setRR(_ values: [Int]) {
        let v = values.prefix(4).map { UInt16(clamping: $0) }
        rrCount = UInt8(v.count)
        rr0 = v.count > 0 ? v[0] : 0
        rr1 = v.count > 1 ? v[1] : 0
        rr2 = v.count > 2 ? v[2] : 0
        rr3 = v.count > 3 ? v[3] : 0
    }

    var hasGravity: Bool { !gx.isNaN && !gy.isNaN && !gz.isNaN }
    var worn: Bool { hr > 0 }

    static func == (a: HistorySample, b: HistorySample) -> Bool {
        func feq(_ x: Float, _ y: Float) -> Bool { (x.isNaN && y.isNaN) || x == y }
        return a.ts == b.ts && a.hr == b.hr && a.rr == b.rr && feq(a.gx, b.gx) && feq(a.gy, b.gy)
            && feq(a.gz, b.gz) && feq(a.dynAccel, b.dynAccel) && a.stepCounter == b.stepCounter
            && a.cadence == b.cadence && a.activityClass == b.activityClass && feq(a.skinTemp, b.skinTemp)
            && a.sleepState == b.sleepState && a.spo2Raw == b.spo2Raw && feq(a.quality, b.quality)
    }
}

enum HistoryDecoder {
    /// Decode a historical (0x2F) inner payload into a 1 Hz sample, or nil when the record is
    /// not a per-second record (deep buffers, waveforms, unknown layouts).
    static func decode(_ inner: [UInt8], profile: BandProfile) -> HistorySample? {
        guard inner.count >= 11, inner[0] == PacketType.historicalData else { return nil }
        return profile.isGen5 ? decodeGen5V18(inner) : decodeGen4R24(inner)
    }

    // MARK: WHOOP 5.0 / MG — v18 per-second biometric summary (112-byte inner)

    static let v18MinReadable = 109

    static func decodeGen5V18(_ inner: [UInt8]) -> HistorySample? {
        guard inner.count >= v18MinReadable, inner[1] == 18 else { return nil }
        let ts = inner.u32(7)
        let hrRaw = Int(inner[14])
        var s = HistorySample(ts: ts, hr: (25...230).contains(hrRaw) ? UInt8(hrRaw) : 0)

        let declared = Int(inner[15])
        var rr: [Int] = []
        if declared <= 4 {
            for i in 0..<declared where 16 + 2 * i + 2 <= inner.count {
                let v = inner.i16(16 + 2 * i)
                if v >= RRBounds.min && v <= RRBounds.max { rr.append(v) }
            }
        }
        s.setRR(rr)

        let fullScale: Float = 16
        let dyn = inner.f32(33)
        if dyn.isFinite && dyn >= 0 && dyn <= fullScale { s.dynAccel = dyn }
        let gx = inner.f32(37), gy = inner.f32(41), gz = inner.f32(45)
        if gx.isFinite && gy.isFinite && gz.isFinite && abs(gx) <= fullScale && abs(gy) <= fullScale && abs(gz) <= fullScale {
            s.gx = gx; s.gy = gy; s.gz = gz
        }
        s.stepCounter = Int32(inner.u16(49))
        s.cadence = Int16(inner[51])
        let act = inner[55]
        s.activityClass = act <= 2 ? Int8(act) : -1
        let skinRaw = inner.i16(65)
        if skinRaw != -5000 {
            let t = Float(skinRaw) / 100
            if t > 0 && t < 45 { s.skinTemp = t }
        }
        s.sleepState = Int8((inner[73] >> 4) & 0x03)
        s.spo2Raw = Int16(inner[74])
        let q = inner.f32(105)
        if q.isFinite { s.quality = q }
        return s
    }

    // MARK: WHOOP 4.0 — v24 / v12 per-second record (≥ 89-byte inner)

    static func decodeGen4R24(_ inner: [UInt8]) -> HistorySample? {
        let version = inner[1]
        guard version == 24 || version == 12, inner.count >= 89 else { return nil }
        let hrRaw = Int(inner[17])
        var s = HistorySample(ts: inner.u32(7), hr: (25...230).contains(hrRaw) ? UInt8(hrRaw) : 0)
        let declared = Int(inner[18])
        var rr: [Int] = []
        if declared <= 4 {
            for i in 0..<declared where 19 + 2 * i + 2 <= inner.count {
                let v = inner.i16(19 + 2 * i)
                if v >= RRBounds.min && v <= RRBounds.max { rr.append(v) }
            }
        }
        s.setRR(rr)
        let gx = inner.f32(36), gy = inner.f32(40), gz = inner.f32(44)
        if gx.isFinite && gy.isFinite && gz.isFinite { s.gx = gx; s.gy = gy; s.gz = gz }
        return s
    }
}
