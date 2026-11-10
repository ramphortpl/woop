import Foundation

/// Per-minute aggregation of the 1 Hz history over a window. Minute `i` covers
/// `[start + 60·i, start + 60·i + 60)`.
struct MinuteSeries {
    let start: Int
    let count: Int
    var hrSum: [Double]
    var hrN: [Int]
    var hrMax: [Int]
    /// Σ per-second gravity jerk |g(t) − g(t−1)| (g) and the number of jerk pairs.
    var jerkSum: [Double]
    var jerkN: [Int]
    /// Seconds per band sleep state (gen5): 0 wake, 1 still, 2 sleep, 3 up.
    var bandWake: [Int]
    var bandStill: [Int]
    var bandSleep: [Int]
    var bandUp: [Int]
    var present: [Int]
    var stepInc: [Int]
    var skinSum: [Double]
    var skinN: [Int]

    init(start: Int, minutes: Int) {
        self.start = start - (start % 60 + 60) % 60
        count = max(0, minutes)
        hrSum = Array(repeating: 0, count: count)
        hrN = Array(repeating: 0, count: count)
        hrMax = Array(repeating: 0, count: count)
        jerkSum = Array(repeating: 0, count: count)
        jerkN = Array(repeating: 0, count: count)
        bandWake = Array(repeating: 0, count: count)
        bandStill = Array(repeating: 0, count: count)
        bandSleep = Array(repeating: 0, count: count)
        bandUp = Array(repeating: 0, count: count)
        present = Array(repeating: 0, count: count)
        stepInc = Array(repeating: 0, count: count)
        skinSum = Array(repeating: 0, count: count)
        skinN = Array(repeating: 0, count: count)
    }

    /// Build from ts-sorted samples.
    static func build(_ samples: [HistorySample], from: Int, to: Int) -> MinuteSeries {
        var m = MinuteSeries(start: from, minutes: Int((Double(to - from) / 60).rounded(.up)) + 1)
        var prev: HistorySample?
        for s in samples {
            let i = (s.ts - m.start) / 60
            guard s.ts >= m.start, i >= 0, i < m.count else { prev = s; continue }
            m.present[i] += 1
            if s.hr > 0 {
                m.hrSum[i] += Double(s.hr)
                m.hrN[i] += 1
                if Int(s.hr) > m.hrMax[i] { m.hrMax[i] = Int(s.hr) }
            }
            switch s.sleepState {
            case 0: m.bandWake[i] += 1
            case 1: m.bandStill[i] += 1
            case 2: m.bandSleep[i] += 1
            case 3: m.bandUp[i] += 1
            default: break
            }
            if !s.skinTemp.isNaN { m.skinSum[i] += Double(s.skinTemp); m.skinN[i] += 1 }
            if let p = prev {
                if s.ts - p.ts == 1, s.hasGravity, p.hasGravity {
                    let dx = Double(s.gx - p.gx), dy = Double(s.gy - p.gy), dz = Double(s.gz - p.gz)
                    m.jerkSum[i] += (dx * dx + dy * dy + dz * dz).squareRoot()
                    m.jerkN[i] += 1
                }
                if s.stepCounter >= 0, p.stepCounter >= 0 {
                    let d = (Int(s.stepCounter) - Int(p.stepCounter)) & 0xFFFF
                    if d > 0 && d < 512 { m.stepInc[i] += d }
                }
            }
            prev = s
        }
        return m
    }

    func unix(_ i: Int) -> Int { start + 60 * i }
    func index(of unix: Int) -> Int { (unix - start) / 60 }

    func hr(_ i: Int) -> Double? { hrN[i] >= 10 ? hrSum[i] / Double(hrN[i]) : nil }
    func worn(_ i: Int) -> Bool { hrN[i] >= 20 }
    func hasBandState(_ i: Int) -> Bool { bandWake[i] + bandStill[i] + bandSleep[i] + bandUp[i] >= 20 }

    /// Mean per-second jerk in the minute, or nil without motion data.
    func motion(_ i: Int) -> Double? { jerkN[i] >= 10 ? jerkSum[i] / Double(jerkN[i]) : nil }

    /// Minutes carrying the band's sleep-state envelope (WHOOP 5.0 / MG history).
    var bandStateMinutes: Int { (0..<count).filter { hasBandState($0) }.count }

    /// Fraction of minutes (with any data) carrying the band's sleep-state envelope.
    var bandStateCoverage: Double {
        var withData = 0, withState = 0
        for i in 0..<count where present[i] >= 20 {
            withData += 1
            if hasBandState(i) { withState += 1 }
        }
        return withData == 0 ? 0 : Double(withState) / Double(withData)
    }
}
