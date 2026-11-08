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

/// Finds sleep periods (main night + naps) in a minute series.
enum SleepDetector {
    struct Candidate: Equatable {
        var start: Int
        var end: Int
        var bandBased: Bool
        var asleepMinutes: Int
    }

    static func detect(_ m: MinuteSeries) -> [Candidate] {
        // Live-only seconds (realtime HR while the app is open) carry no band state, so judge on
        // the amount of band-state data rather than its share of the window.
        m.bandStateMinutes >= 120 ? detectFromBand(m) : detectFromMotion(m)
    }

    /// Minute state from the band envelope: 2 asleep, 1 settling, 0 awake, -1 no data.
    static func bandMinuteState(_ m: MinuteSeries, _ i: Int) -> Int {
        guard m.present[i] >= 20 else { return -1 }
        if !m.worn(i) && m.hrN[i] == 0 { return -1 } // strap off the wrist
        if m.bandSleep[i] >= 30 { return 2 }
        if m.bandSleep[i] + m.bandStill[i] >= 30 { return 1 }
        return 0
    }

    static func detectFromBand(_ m: MinuteSeries) -> [Candidate] {
        let states = (0..<m.count).map { bandMinuteState(m, $0) }
        // Raw runs of settling/asleep minutes.
        var runs: [(Int, Int)] = []
        var i = 0
        while i < states.count {
            if states[i] >= 1 {
                var j = i
                while j + 1 < states.count && states[j + 1] >= 1 { j += 1 }
                runs.append((i, j))
                i = j + 1
            } else { i += 1 }
        }
        // Merge runs separated by short awakenings (bathroom, turning over).
        var merged: [(Int, Int)] = []
        for r in runs {
            if let last = merged.last, r.0 - last.1 - 1 <= 20 {
                merged[merged.count - 1].1 = r.1
            } else {
                merged.append(r)
            }
        }
        var out: [Candidate] = []
        for (a, b) in merged {
            guard let firstSleep = (a...b).first(where: { states[$0] == 2 }),
                  let lastSleep = (a...b).last(where: { states[$0] == 2 }) else { continue }
            let asleep = (a...b).filter { states[$0] == 2 }.count
            guard asleep >= 15 else { continue }
            // Band "still" can start long before real bedtime (sofa, reading): cap it.
            let startIdx = max(a, firstSleep - 45)
            let endIdx = lastSleep
            let worn = (startIdx...endIdx).filter { m.worn($0) }.count
            guard Double(worn) >= 0.5 * Double(endIdx - startIdx + 1) else { continue }
            out.append(Candidate(start: m.unix(startIdx), end: m.unix(endIdx + 1), bandBased: true, asleepMinutes: asleep))
        }
        return out
    }

    /// Fallback without the band envelope: sustained stillness with a lowered heart rate.
    static func detectFromMotion(_ m: MinuteSeries) -> [Candidate] {
        let motions = (0..<m.count).compactMap { m.worn($0) ? m.motion($0) : nil }
        let hrs = (0..<m.count).compactMap { m.hr($0) }
        guard motions.count >= 60, hrs.count >= 60,
              let floor = Stats.percentile(motions, 20), let hrRef = Stats.percentile(hrs, 50) else { return [] }
        let stillThr = max(floor * 4, 0.002)
        var sleepish = [Bool](repeating: false, count: m.count)
        for i in 0..<m.count where m.worn(i) {
            guard let mo = m.motion(i) else { continue }
            let hrOK = (m.hr(i) ?? hrRef) <= hrRef - 2
            sleepish[i] = mo <= stillThr && hrOK
        }
        // Smooth: a minute counts if ≥ 7 of the surrounding 11 are sleep-ish.
        var smooth = [Bool](repeating: false, count: m.count)
        for i in 0..<m.count {
            let lo = max(0, i - 5), hi = min(m.count - 1, i + 5)
            let n = (lo...hi).filter { sleepish[$0] }.count
            smooth[i] = n >= 7
        }
        var out: [Candidate] = []
        var i = 0
        while i < m.count {
            if smooth[i] {
                var j = i
                var gap = 0
                var k = i + 1
                while k < m.count {
                    if smooth[k] { j = k; gap = 0 } else { gap += 1; if gap > 15 { break } }
                    k += 1
                }
                let minutes = j - i + 1
                if minutes >= 30 {
                    out.append(Candidate(start: m.unix(i), end: m.unix(j + 1), bandBased: false,
                                         asleepMinutes: (i...j).filter { smooth[$0] }.count))
                }
                i = j + 1
            } else { i += 1 }
        }
        return out
    }
}
