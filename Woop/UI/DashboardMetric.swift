import SwiftUI

/// The metrics offered in "Personnaliser le tableau de bord" (same set and wording as the
/// WHOOP app in French).
enum DashboardMetric: String, Codable, CaseIterable, Identifiable {
    case hrv, rhr, steps, zones13, zones45, vo2max, calories, strainRecovery, dailyStrain, weight, strengthTime
    case sleepDebt, sleepEfficiency, respRate, avgHR, hoursOfSleep, sleepNeeded, leanMass, recovery
    case sleepConsistency, restorativePct, restorativeHours, timeInBed, allZones, sleepPerformance

    var id: String { rawValue }

    static let defaultSelection: [DashboardMetric] = [
        .hrv, .rhr, .steps, .zones13, .zones45, .vo2max, .calories, .strainRecovery, .dailyStrain, .weight, .strengthTime,
    ]

    var title: String {
        switch self {
        case .hrv: return "Variabilité de la fréquence cardiaque"
        case .rhr: return "Fréquence cardiaque au repos"
        case .steps: return "Pas"
        case .zones13: return "Zones de FC 1 à 3 (hebdomadaire)"
        case .zones45: return "Zones de FC 4 et 5 (hebdomadaire)"
        case .vo2max: return "VO₂ max"
        case .calories: return "Calories"
        case .strainRecovery: return "Effort et récupération"
        case .dailyStrain: return "Efforts quotidiens"
        case .weight: return "Poids"
        case .strengthTime: return "Temps de musculation"
        case .sleepDebt: return "Dette de sommeil"
        case .sleepEfficiency: return "Efficacité du sommeil"
        case .respRate: return "Fréquence respiratoire"
        case .avgHR: return "Fréquence cardiaque moyenne"
        case .hoursOfSleep: return "Heures de sommeil"
        case .sleepNeeded: return "Heures de sommeil nécessaires"
        case .leanMass: return "Masse corporelle maigre"
        case .recovery: return "Récupération"
        case .sleepConsistency: return "Régularité du sommeil"
        case .restorativePct: return "Sommeil réparateur (%)"
        case .restorativeHours: return "Sommeil réparateur (heures)"
        case .timeInBed: return "Temps passé au lit"
        case .allZones: return "Toutes les zones de FC (hebdomadaire)"
        case .sleepPerformance: return "Votre sommeil"
        }
    }

    var icon: String {
        switch self {
        case .hrv: return "waveform.path.ecg"
        case .rhr: return "arrow.down.heart"
        case .steps: return "shoeprints.fill"
        case .zones13: return "heart.text.square"
        case .zones45: return "bolt.heart"
        case .vo2max: return "lungs"
        case .calories: return "flame"
        case .strainRecovery: return "figure.strengthtraining.functional"
        case .dailyStrain: return "figure.strengthtraining.functional"
        case .weight: return "scalemass"
        case .strengthTime: return "dumbbell"
        case .sleepDebt: return "moon.zzz"
        case .sleepEfficiency: return "chart.bar.doc.horizontal"
        case .respRate: return "lungs"
        case .avgHR: return "heart"
        case .hoursOfSleep: return "moon"
        case .sleepNeeded: return "moon.haze"
        case .leanMass: return "figure.arms.open"
        case .recovery: return "figure.mind.and.body"
        case .sleepConsistency: return "moon.stars"
        case .restorativePct, .restorativeHours: return "sparkles"
        case .timeInBed: return "stopwatch"
        case .allZones: return "heart.circle"
        case .sleepPerformance: return "moon.fill"
        }
    }

    /// Shown with a chart badge in the customize list (the WHOOP "Effort et récupération" tile).
    var isChart: Bool { self == .strainRecovery }

    var unit: String {
        switch self {
        case .hrv: return "ms"
        case .rhr, .avgHR: return "bpm"
        case .steps: return "pas"
        case .vo2max: return "ml/kg/min"
        case .calories: return "kcal"
        case .weight, .leanMass: return "kg"
        case .respRate: return "rpm"
        default: return ""
        }
    }

    /// nil = neutral (no good/bad colouring).
    var higherIsBetter: Bool? {
        switch self {
        case .hrv, .steps, .vo2max, .sleepEfficiency, .hoursOfSleep, .recovery, .sleepConsistency,
             .restorativePct, .restorativeHours, .sleepPerformance, .zones13, .zones45, .allZones, .strengthTime:
            return true
        case .rhr, .sleepDebt: return false
        default: return nil
        }
    }

    /// Numeric value for a day (nil when not measured).
    @MainActor
    func value(day: DayMetrics, state: AppState) -> Double? {
        let p = state.settings.profile
        switch self {
        case .hrv: return day.hrv
        case .rhr: return day.rhr
        case .steps: return day.steps.map(Double.init)
        case .zones13: return weeklyZones(day, state, 1...3)
        case .zones45: return weeklyZones(day, state, 4...5)
        case .allZones: return weeklyZones(day, state, 1...5)
        case .vo2max: return day.vo2max
        case .calories: return day.calories
        case .strainRecovery: return day.strain
        case .dailyStrain: return day.strain
        case .weight: return p.weightKg
        case .leanMass: return p.leanBodyMass
        case .strengthTime: return weeklySport(day, state, SportCatalog.strengthKeys)
        case .sleepDebt: return day.sleepDebtSec
        case .sleepEfficiency: return day.sleep.map { $0.efficiency * 100 }
        case .respRate: return day.respRate
        case .avgHR: return day.avgHR
        case .hoursOfSleep: return day.sleep.map { Double($0.asleepSec) }
        case .sleepNeeded: return day.tonightNeedSec ?? day.sleepNeedSec
        case .recovery: return day.recovery
        case .sleepConsistency: return day.sleepConsistency
        case .restorativePct: return day.sleep.map { $0.restorativeFraction * 100 }
        case .restorativeHours: return day.sleep.map { Double($0.restorativeSec) }
        case .timeInBed: return day.sleep.map { Double($0.inBedSec) }
        case .sleepPerformance: return day.sleepPerformance
        }
    }

    func format(_ v: Double?) -> String {
        guard let v else { return "—" }
        switch self {
        case .hrv, .rhr, .avgHR, .calories: return Fmt.int(v)
        case .steps: return Fmt.int(v)
        case .zones13, .zones45, .allZones, .strengthTime, .sleepDebt, .hoursOfSleep, .sleepNeeded,
             .restorativeHours, .timeInBed:
            return Fmt.hm(v)
        case .vo2max, .respRate, .weight, .leanMass, .strainRecovery, .dailyStrain: return Fmt.dec1(v)
        case .sleepEfficiency, .recovery, .sleepConsistency, .restorativePct, .sleepPerformance: return Fmt.pct(v)
        }
    }

    @MainActor
    private func weeklyZones(_ day: DayMetrics, _ state: AppState, _ zones: ClosedRange<Int>) -> Double? {
        let week = (0..<7).compactMap { state.day(DayKey.adding(-$0, to: day.date)) }
        guard !week.isEmpty else { return nil }
        let secs = week.reduce(0) { acc, d in acc + zones.reduce(0) { $0 + (d.zoneSeconds.indices.contains($1) ? d.zoneSeconds[$1] : 0) } }
        return Double(secs)
    }

    @MainActor
    private func weeklySport(_ day: DayMetrics, _ state: AppState, _ sports: Set<String>) -> Double? {
        let week = (0..<7).compactMap { state.day(DayKey.adding(-$0, to: day.date)) }
        let secs = week.flatMap(\.activities).filter { sports.contains($0.sport) }.reduce(0) { $0 + $1.durationSec }
        return Double(secs)
    }
}
