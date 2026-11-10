import Foundation

/// The wearer's profile, used for heart-rate reserve, calories and baselines.
struct UserProfile: Codable, Equatable, Sendable {
    enum Sex: String, Codable, CaseIterable, Sendable { case male, female }

    var firstName: String = ""
    var lastName: String = ""
    var birthYear: Int = 1995
    var sex: Sex = .male
    var heightCm: Double = 178
    var weightKg: Double = 75
    /// Manual max HR (bpm); nil = estimate (Tanaka, raised by observed peaks).
    var maxHROverride: Int?
    /// Baseline nightly sleep need, hours.
    var baselineSleepNeedHours: Double = 7.75
    /// Usual wake time (minutes after midnight) when no alarm is set.
    var usualWakeMinute: Int = 7 * 60

    var age: Int {
        let y = Calendar(identifier: .gregorian).component(.year, from: Date())
        return max(14, min(95, y - birthYear))
    }

    var initials: String {
        let a = firstName.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? ""
        let b = lastName.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? ""
        let s = (a + b).uppercased()
        return s.isEmpty ? "W" : s
    }

    /// Mifflin–St Jeor basal metabolic rate, kcal/day.
    var bmr: Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        return sex == .male ? base + 5 : base - 161
    }

    /// Boer lean body mass estimate, kg.
    var leanBodyMass: Double {
        sex == .male ? 0.407 * weightKg + 0.267 * heightCm - 19.2
                     : 0.252 * weightKg + 0.473 * heightCm - 48.3
    }

    /// Tanaka et al. 2001.
    var tanakaMaxHR: Double { 208 - 0.7 * Double(age) }
}

enum SleepStage: String, Codable, CaseIterable, Sendable {
    case wake, light, deep, rem
}

struct StageSegment: Codable, Equatable, Sendable {
    var start: Int
    var end: Int
    var stage: SleepStage
    var duration: Int { max(0, end - start) }
}

struct SleepSession: Codable, Equatable, Sendable, Identifiable {
    var id: Int { start }
    /// In bed (first still minute) → out of bed (last asleep minute), unix seconds.
    var start: Int
    var end: Int
    var isNap: Bool = false
    var stages: [StageSegment] = []
    var awakeSec: Int = 0
    var lightSec: Int = 0
    var deepSec: Int = 0
    var remSec: Int = 0
    var latencySec: Int = 0
    var disturbances: Int = 0
    var cycles: Int = 0
    var hrv: Double?
    var rhr: Double?
    var respRate: Double?
    var spo2: Double?
    var skinTemp: Double?
    var avgHR: Double?
    /// true when the night was found from motion (or imported), false for the heart-rate-only fallback.
    var bandDetected: Bool = true
    /// Seconds inside the window that were not observed (no sample, or no heart rate nearby):
    /// they count as neither asleep nor awake.
    var unobservedSec: Int?
    /// 5-minute windows behind the HRV figure (0 = pooled over the night).
    var hrvWindows: Int?
    /// Lag-1 autocorrelation of the beat-to-beat differences (≈ 0 clean, −0.5 pure timing noise).
    var hrvNoise: Double?
    /// Share of the time asleep spent with a markedly raised heart rate, 0–100.
    var highStressPct: Double?

    var asleepSec: Int { lightSec + deepSec + remSec }
    var inBedSec: Int { max(0, end - start) }
    /// Asleep ÷ observed time in bed.
    var efficiency: Double {
        let observed = inBedSec - (unobservedSec ?? 0)
        return observed > 0 ? min(1, Double(asleepSec) / Double(observed)) : 0
    }
    var restorativeSec: Int { deepSec + remSec }
    var restorativeFraction: Double { asleepSec > 0 ? Double(restorativeSec) / Double(asleepSec) : 0 }
}

/// One GPS fix of an activity route.
struct RoutePoint: Codable, Equatable, Sendable {
    var lat: Double
    var lon: Double
    var ts: Int
}

/// A workout / activity inside a day.
struct ActivityRecord: Codable, Equatable, Sendable, Identifiable {
    enum Source: String, Codable, Sendable { case auto, manual, live, imported }

    var id: String
    var sport: String
    var start: Int
    var end: Int
    var source: Source
    var strain: Double?
    var avgHR: Double?
    var maxHR: Int?
    var calories: Double?
    /// Seconds in WHOOP zones 0…5 (zone 0 = below 50 % HRmax).
    var zoneSeconds: [Int] = Array(repeating: 0, count: 6)
    var distanceKm: Double?
    var note: String?
    /// GPS track recorded with "Suivi d'itinéraire" (live activities).
    var route: [RoutePoint]?

    var durationSec: Int { max(0, end - start) }
}

/// Everything shown for one day ("cycle" in WHOOP terms: from the night's sleep to the next).
struct DayMetrics: Codable, Equatable, Sendable {
    static let algoVersion = 5

    var date: String
    var algoVersion: Int = DayMetrics.algoVersion
    /// Carries scores imported from the official WHOOP export.
    var imported: Bool = false
    var computedAt: Int = 0
    var cycleStart: Int?
    var cycleEnd: Int?

    // Sleep (the night that ended this day)
    var sleep: SleepSession?
    var naps: [SleepSession] = []
    var sleepNeedSec: Double?
    /// WHOOP's composite sleep score ("Votre sommeil"), 0–100.
    var sleepPerformance: Double?
    /// Hours slept against the need, 0–100 (one of the four parts of the sleep score).
    var sleepHoursVsNeed: Double?
    var sleepConsistency: Double?
    var sleepDebtSec: Double?
    /// Need for the coming night (shown as "Heures de sommeil nécessaires").
    var tonightNeedSec: Double?

    // Recovery
    var recovery: Double?
    /// Nights collected so far while the baseline is still calibrating.
    var calibrationNights: Int?
    var hrv: Double?
    var rhr: Double?
    var respRate: Double?
    var spo2: Double?
    var skinTemp: Double?
    var skinTempDev: Double?
    /// The night's values exactly as measured, before any personal WHOOP calibration.
    var hrvRaw: Double?
    var rhrRaw: Double?
    var respRaw: Double?
    /// True when the recovery came from the model fitted on the wearer's WHOOP export.
    var recoveryCalibrated: Bool?

    // Strain
    var strain: Double?
    /// Cumulative day strain sampled every 15 min from cycle start (for charts).
    var strainCurve: [Double] = []
    var calories: Double?
    var activeCalories: Double?
    var steps: Int?
    var avgHR: Double?
    var maxHR: Int?
    var zoneSeconds: [Int] = Array(repeating: 0, count: 6)
    var activities: [ActivityRecord] = []
    var vo2max: Double?
    /// This day's quiet waking heart-rate-reserve fraction (feeds the personal strain baseline).
    var quietHRR: Double?
    var restingHRUsed: Double?
    var maxHRUsed: Double?

    // Coverage
    var wornMinutes: Int = 0
    /// Minutes of the cycle with any strap data, and the cycle's length in minutes.
    var dataMinutes: Int?
    var cycleMinutes: Int?
    /// 5-minute mean HR over the cycle (0 = no data), for the day chart.
    var hrTrace: [Int] = []
    var hrTraceStart: Int?

    var hasData: Bool { wornMinutes > 0 || sleep != nil }
}

extension DayMetrics {
    static func empty(_ date: String) -> DayMetrics { DayMetrics(date: date) }
}
