import Foundation

/// One minute of heart rate for the charts.
struct HRPoint: Equatable, Sendable {
    let ts: Int
    let bpm: Double
}

extension AppState {
    /// Per-minute mean heart rate over [from, to), read off the main thread from the database
    /// (or from the in-memory demo recording). Cached until the data changes.
    func minuteHR(from: Int, to: Int) async -> [HRPoint] {
        guard to > from else { return [] }
        let key = "\(settings.demoMode ? 1 : 0):\(dataVersion):\(from):\(to)"
        if let cached = hrCache[key] { return cached }
        let demo = settings.demoMode ? demoSamples : nil
        let points: [HRPoint] = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                if let demo {
                    cont.resume(returning: Self.minuteMeans(demo, from: from, to: to))
                } else {
                    cont.resume(returning: Database.shared.minuteHR(from: from, to: to).map { HRPoint(ts: $0.ts, bpm: $0.bpm) })
                }
            }
        }
        hrCache[key] = points
        hrCacheOrder.append(key)
        if hrCacheOrder.count > 40 {
            let old = hrCacheOrder.removeFirst()
            hrCache[old] = nil
        }
        return points
    }

    /// Per-minute means of time-sorted 1 Hz samples.
    nonisolated static func minuteMeans(_ s: [HistorySample], from: Int, to: Int) -> [HRPoint] {
        var lo = 0, hi = s.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if s[mid].ts < from { lo = mid + 1 } else { hi = mid }
        }
        var out: [HRPoint] = []
        var minute = Int.min, sum = 0.0, n = 0
        var i = lo
        while i < s.count, s[i].ts < to {
            let m = s[i].ts - ((s[i].ts % 60) + 60) % 60
            if m != minute {
                if n > 0 { out.append(HRPoint(ts: minute, bpm: sum / Double(n))) }
                minute = m
                sum = 0
                n = 0
            }
            if s[i].hr > 0 {
                sum += Double(s[i].hr)
                n += 1
            }
            i += 1
        }
        if n > 0 { out.append(HRPoint(ts: minute, bpm: sum / Double(n))) }
        return out
    }

    /// Usual share of each sleep stage (25th–75th percentile of the 30 nights before `key`),
    /// as fractions of the time in bed.
    func usualStageShares(before key: String) -> [SleepStage: ClosedRange<Double>] {
        let nights = history(upTo: DayKey.adding(-1, to: key), count: 30).compactMap(\.sleep).filter { $0.inBedSec > 3600 }
        guard nights.count >= 3 else { return [:] }
        func band(_ f: (SleepSession) -> Int) -> ClosedRange<Double>? {
            let v = nights.map { Double(f($0)) / Double($0.inBedSec) }
            guard let a = Stats.percentile(v, 25), let b = Stats.percentile(v, 75) else { return nil }
            return min(a, b)...max(a, b)
        }
        var out: [SleepStage: ClosedRange<Double>] = [:]
        out[.wake] = band { $0.awakeSec }
        out[.light] = band { $0.lightSec }
        out[.deep] = band { $0.deepSec }
        out[.rem] = band { $0.remSec }
        return out
    }

    /// Mean of a value over the 30 days before `key`.
    func average30(before key: String, _ f: (DayMetrics) -> Double?) -> Double? {
        Stats.mean(history(upTo: DayKey.adding(-1, to: key), count: 30).compactMap(f))
    }

    /// Typical band (mean ± 1 SD) over the 30 days before `key`.
    func usualRange30(before key: String, _ f: (DayMetrics) -> Double?) -> ClosedRange<Double>? {
        let v = history(upTo: DayKey.adding(-1, to: key), count: 30).compactMap(f)
        guard v.count >= 4, let m = Stats.mean(v), let sd = Stats.std(v) else { return nil }
        return (m - sd)...(m + sd)
    }
}
