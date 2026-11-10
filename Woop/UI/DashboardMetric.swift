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

// MARK: - Detail screens ("Sommeil des dernières nuits", "MODIFIER")

extension DashboardMetric {
    /// Metrics offered in each score screen's statistics section.
    static let sleepChoices: [DashboardMetric] = [
        .hoursOfSleep, .sleepPerformance, .sleepConsistency, .sleepEfficiency, .restorativeHours, .restorativePct,
        .timeInBed, .sleepDebt, .sleepNeeded, .respRate,
    ]
    static let recoveryChoices: [DashboardMetric] = [.recovery, .hrv, .rhr, .respRate, .sleepPerformance, .vo2max, .avgHR]
    static let strainChoices: [DashboardMetric] = [.dailyStrain, .calories, .avgHR, .steps, .zones13, .zones45, .allZones, .strengthTime, .vo2max]

    static let sleepDefaults: [DashboardMetric] = [.hoursOfSleep, .sleepPerformance, .sleepConsistency, .sleepEfficiency, .restorativeHours, .respRate, .sleepDebt]
    static let recoveryDefaults: [DashboardMetric] = [.recovery, .hrv, .rhr, .respRate, .sleepPerformance]
    static let strainDefaults: [DashboardMetric] = [.dailyStrain, .calories, .avgHR, .steps, .zones13, .zones45]

    /// Chart colour of the metric.
    var color: Color {
        switch self {
        case .recovery: return Theme.recoveryGreen
        case .dailyStrain, .strainRecovery, .calories, .zones13, .zones45, .allZones, .strengthTime, .steps: return Theme.strain
        case .hrv, .rhr, .avgHR, .respRate, .vo2max: return Color(hex: 0xE0E3E6)
        default: return Theme.sleep
        }
    }

    /// Text of the (i) button.
    var explanation: String {
        switch self {
        case .hrv: return "Variabilité de la fréquence cardiaque (RMSSD) : valeur médiane des fenêtres de 5 minutes de ta nuit, calculée uniquement entre battements réellement consécutifs. Plus elle est haute par rapport à ta norme, mieux ton système nerveux récupère."
        case .rhr: return "Fréquence cardiaque au repos : la demi-heure la plus basse de ta nuit. Une valeur plus haute que d'habitude signale souvent fatigue, stress, alcool ou début de maladie."
        case .vo2max: return "Estimation à partir du rapport FC max / FC au repos (méthode d'Uth et al., 2004). Ce n'est pas une mesure de laboratoire."
        case .steps: return "Pas comptés par le capteur de mouvement du bracelet pendant la journée."
        case .calories: return "Métabolisme de base (Mifflin–St Jeor) plus la dépense liée à la fréquence cardiaque (Keytel et al., 2005)."
        case .zones13, .zones45, .allZones: return "Temps passé dans les zones de fréquence cardiaque sur les 7 derniers jours. Comme sur WHOOP, les zones sont des parts de ta réserve cardiaque (entre ta FC au repos et ta FC max) : zone 1 à partir de 50 %, zone 5 à partir de 90 %."
        case .respRate: return "Respirations par minute pendant le sommeil, déduites des variations du rythme cardiaque (arythmie sinusale respiratoire). Elle varie très peu d'une nuit à l'autre : un écart peut annoncer une maladie."
        case .weight, .leanMass: return "Valeur issue de ton profil (Plus › Profil). La masse maigre est estimée avec la formule de Boer."
        case .hoursOfSleep: return "Temps réellement endormi (sommeil léger, profond et paradoxal), sans les éveils. Le graphique montre ta fréquence cardiaque pendant la nuit ; touche une phase pour la mettre en évidence. La zone en pointillés indique ta plage habituelle sur 30 jours."
        case .sleepPerformance: return "Ton score de sommeil combine, comme sur WHOOP, les heures dormies par rapport à ton besoin (la plus grande part), la régularité de tes horaires, l'efficacité de la nuit et le stress pendant le sommeil."
        case .sleepConsistency: return "Régularité de tes heures de coucher et de lever sur les 4 dernières nuits : la probabilité d'être dans le même état (endormi ou éveillé) à la même heure d'un jour sur l'autre. Optimal à partir de 80 %."
        case .sleepEfficiency: return "Part du temps passé au lit pendant laquelle tu dormais. Optimal à partir de 90 %."
        case .restorativeHours, .restorativePct: return "Sommeil réparateur : sommeil profond (SOL, ondes lentes) et sommeil paradoxal (SP). C'est là que le corps et le cerveau récupèrent le plus."
        case .timeInBed: return "De l'endormissement au réveil final, éveils compris. Un réveil en pleine nuit suivi d'un rendormissement reste la même nuit."
        case .sleepDebt: return "Part du sommeil manqué la nuit précédente (environ la moitié) reportée sur ton besoin de cette nuit. Elle s'efface dès que tu dors ton besoin complet."
        case .sleepNeeded: return "Ton besoin de sommeil pour la nuit à venir : besoin de base, dette, effort de la journée et siestes."
        case .recovery: return "La récupération compare ta VFC, ta fréquence cardiaque au repos, ta respiration et ton sommeil à tes propres moyennes. Vert : prêt pour un effort important ; jaune : effort modéré ; rouge : repos."
        case .dailyStrain, .strainRecovery: return "L'effort mesure ta charge cardiovasculaire de 0 à 21 à partir du temps passé dans chaque zone de fréquence cardiaque. L'échelle est logarithmique : chaque point coûte plus cher que le précédent, et une journée monte peu après une grosse séance."
        case .avgHR: return "Fréquence cardiaque moyenne sur la journée (du réveil au réveil suivant)."
        case .strengthTime: return "Temps passé en musculation, haltérophilie, CrossFit… sur les 7 derniers jours."
        }
    }
}
