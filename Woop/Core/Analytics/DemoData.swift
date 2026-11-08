import Foundation

/// Synthetic but physiologically shaped recording, used ONLY by the clearly labelled demo mode
/// (and tests) so the interface can be explored before a strap is paired. Never mixed with
/// real data: demo samples live in memory and are never written to the database.
enum DemoData {
    private struct Rng {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        mutating func gauss() -> Double {
            let u = max(next(), 1e-12), v = next()
            return (-2 * log(u)).squareRoot() * cos(2 * .pi * v)
        }
    }

    /// Textbook night: 90-minute cycles, deep sleep front-loaded, REM growing toward morning.
    static func stageAt(minute m: Double) -> SleepStage {
        if (95..<98).contains(m) || (300..<303).contains(m) { return .wake }
        let cycle = Int(m / 90), inCycle = m.truncatingRemainder(dividingBy: 90)
        let deep = [40.0, 30, 15, 5, 0, 0][min(cycle, 5)]
        let rem = [10.0, 20, 25, 30, 35, 35][min(cycle, 5)]
        if inCycle < 25 { return .light }
        if inCycle < 25 + deep { return .deep }
        if inCycle < 90 - rem { return .light }
        return .rem
    }

    struct DayPlan {
        var bed: Int        // unix: lights out (still)
        var wake: Int       // unix: wake
        var hrvScale: Double
        var workout: (start: Int, end: Int, hr: Double, cls: Int8)?
    }

    static func generate(days: Int, now: Date = Date(), seed: UInt64 = 7) -> [HistorySample] {
        var rng = Rng(state: seed)
        let nowTs = Int(now.timeIntervalSince1970)
        guard let todayStart = DayKey.startUnix(DayKey.key(now)) else { return [] }
        var plans: [DayPlan] = []
        for d in stride(from: days - 1, through: 0, by: -1) {
            let dayStart = todayStart - d * 86400
            let bed = dayStart - 3600 + Int(rng.gauss() * 2400) // around 23:00 the evening before
            let sleepLen = 6.2 * 3600 + rng.next() * 2.3 * 3600
            let wake = bed + Int(sleepLen)
            var workout: (Int, Int, Double, Int8)?
            if rng.next() < 0.75 {
                let kind = rng.next()
                let hourStart = 9.0 + rng.next() * 9
                let s = dayStart + Int(hourStart * 3600)
                if kind < 0.35 { workout = (s, s + Int(2400 + rng.next() * 1800), 152 + rng.gauss() * 6, 2) }        // run
                else if kind < 0.65 { workout = (s, s + Int(5400 + rng.next() * 3600), 136 + rng.gauss() * 5, 0) }  // ride
                else if kind < 0.85 { workout = (s, s + Int(3000 + rng.next() * 1200), 118 + rng.gauss() * 5, 0) }  // gym
                else { workout = (s, s + Int(2400 + rng.next() * 2400), 108 + rng.gauss() * 4, 1) }                 // hike
            }
            plans.append(DayPlan(bed: bed, wake: wake, hrvScale: 0.75 + rng.next() * 0.55,
                                 workout: workout.map { (start: $0.0, end: $0.1, hr: $0.2, cls: $0.3) }))
        }
        var out: [HistorySample] = []
        out.reserveCapacity(days * 86400)
        var step = 2000
        var beatPhase = 0.0
        var slow = 0.0
        let first = plans.first.map { $0.bed - 3 * 3600 } ?? todayStart
        var planIdx = 0
        for t in first..<nowTs {
            while planIdx + 1 < plans.count && t >= plans[planIdx + 1].bed - 3 * 3600 { planIdx += 1 }
            let p = plans[planIdx]
            var s = HistorySample(ts: t, hr: 0)
            slow = 0.98 * slow + 0.02 * rng.gauss()
            var hr: Double, rsa: Double, breath = 14.0, still = 0.0005
            if t >= p.bed && t < p.wake {
                let into = Double(t - p.bed) / 60
                let st: SleepStage = into < 14 ? .wake : stageAt(minute: into - 14)
                switch st {
                case .deep: hr = 50 + slow * 0.3 + rng.gauss() * 0.3; rsa = 46 * p.hrvScale; breath = 13.4
                case .light: hr = 55 + slow * 1.5 + rng.gauss(); rsa = 30 * p.hrvScale
                case .rem: hr = 59 + slow * 4 + rng.gauss() * 2.5; rsa = 18 * p.hrvScale; breath = 16 + rng.gauss() * 2
                case .wake: hr = 66 + rng.gauss() * 3; rsa = 12; still = 0.08
                }
                s.sleepState = into < 20 ? 1 : (st == .wake ? 0 : 2)
                s.skinTemp = Float(33.4 + slow * 0.2)
                if st != .wake && rng.next() < 0.004 { s.spo2Raw = Int16(96 + Int(rng.next() * 3)) }
            } else if let w = p.workout, t >= w.start && t < w.end {
                let ramp = min(1, Double(t - w.start) / 300)
                hr = 75 + (w.hr - 75) * ramp + rng.gauss() * 4
                rsa = 4; still = 0.2
                s.sleepState = 0
                s.activityClass = w.cls
                if rng.next() < (w.cls == 0 ? 0.2 : 0.9) { step += w.cls == 2 ? 3 : 2 }
                s.skinTemp = 31.5
            } else {
                let hourOfDay = DayKey.minuteOfDay(unix: t) / 60
                hr = 70 + Double(hourOfDay % 5) + rng.gauss() * 4
                rsa = 14; still = 0.03
                s.sleepState = 0
                s.activityClass = 0
                if rng.next() < 0.13 { step += 1 }
                s.skinTemp = 32.0
            }
            s.hr = UInt8(max(35, min(205, hr.rounded())))
            var rr: [Int] = []
            let mean = 60000 / hr
            beatPhase += 1000
            while beatPhase >= mean {
                rr.append(Int((mean + sin(2 * .pi * Double(t) * breath / 60) * rsa + rng.gauss() * 4).rounded()))
                beatPhase -= mean
            }
            s.setRR(rr)
            s.gx = Float(0.1 + rng.gauss() * still)
            s.gy = Float(0.2 + rng.gauss() * still)
            s.gz = Float(0.97 + rng.gauss() * still)
            s.stepCounter = Int32(step & 0xFFFF)
            out.append(s)
        }
        return out
    }
}
