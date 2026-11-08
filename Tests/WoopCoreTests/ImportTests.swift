import XCTest
@testable import WoopCore

final class ImportTests: XCTestCase {
    // Header row in the French export's wording (as WHOOP localizes it).
    let cyclesFR = """
    Heure de début du cycle,Heure de fin du cycle,Fuseau horaire du cycle,Score de récupération %,Fréquence cardiaque au repos (bpm),Variabilité de la fréquence cardiaque (ms),Température cutanée (celsius),Niveau d'oxygène %,Effort du jour,Dépense énergétique (cal),FC max (bpm),FC moyenne (bpm),Premiers signes de sommeil,Premiers signes de réveil,Performance sommeil %,Fréquence respiratoire (tr/min),Durée du sommeil (min),Temps passé au lit (min),Durée du sommeil léger (min),Durée du sommeil profond (min),Durée du sommeil paradoxal (min),Temps d'éveil (min),Besoins en sommeil (min),Dette de sommeil (min),Efficacité du sommeil %,Régularité du sommeil %\r
    2026-11-08 02:31:00,,UTC+01:00,45,58,52,33.4,96.1,12.8,2534,171,79,2026-11-08 02:31:00,2026-11-08 08:24:00,76,15.2,340,353,180,70,90,13,447,60,96,71\r
    2026-11-06 23:10:00,2026-11-08 02:31:00,UTC+01:00,68,54,61,33.2,96.5,9.4,2310,160,74,2026-11-06 23:10:00,2026-11-07 07:05:00,92,14.8,450,475,240,95,115,25,489,20,95,80\r

    """

    let workoutsFR = """
    Heure de début du cycle,Heure de fin du cycle,Fuseau horaire du cycle,Heure de début de l'entraînement,Heure de fin de l'entraînement,Durée (min),Nom de l'activité,Effort activité,Dépense énergétique (cal),FC max (bpm),FC moyenne (bpm),Zone FC 1 %,Zone FC 2 %,Zone FC 3 %,Zone FC 4 %,Zone FC 5 %,GPS activé
    2026-11-08 02:31:00,,UTC+01:00,2026-11-08 09:24:00,2026-11-08 11:50:00,146,Cyclisme,12.6,1350,171,135,10,30,40,15,5,false
    2026-11-08 02:31:00,,UTC+01:00,2026-11-08 14:38:00,2026-11-08 15:18:00,40,"Randonnée",4.1,240,120,105,60,30,10,0,0,false
    """

    func testFrenchExport() {
        let r = WhoopExport.importTexts([cyclesFR, workoutsFR])
        XCTAssertEqual(r.cycles, 2)
        XCTAssertEqual(r.workouts, 2)
        let today = r.days.first { $0.date == "2026-11-08" }
        XCTAssertNotNil(today)
        XCTAssertEqual(today?.recovery, 45)
        XCTAssertEqual(today?.strain, 12.8)
        XCTAssertEqual(today?.sleepPerformance, 76)
        XCTAssertEqual(today?.hrv, 52)
        XCTAssertEqual(today?.sleep?.asleepSec, 340 * 60)
        XCTAssertEqual(today?.sleep?.deepSec, 70 * 60)
        XCTAssertTrue(today?.imported ?? false)
        // The earlier cycle (started the 6th, woke the 7th) belongs to the 7th.
        XCTAssertNotNil(r.days.first { $0.date == "2026-11-07" })
        XCTAssertEqual(r.activities.map(\.sport), ["cyclisme", "randonnee"])
        XCTAssertEqual(r.activities.first?.strain, 12.6)
        XCTAssertEqual(r.activities.first?.durationSec, 146 * 60)
    }

    func testMergePrefersWhoopScores() {
        var computed = DayMetrics(date: "2026-11-08")
        computed.recovery = 50
        computed.hrTrace = [60, 61]
        computed.steps = 8000
        var imported = DayMetrics(date: "2026-11-08")
        imported.recovery = 45
        let m = DayMetrics.merged(computed: computed, imported: imported)!
        XCTAssertEqual(m.recovery, 45)
        XCTAssertEqual(m.steps, 8000)
        XCTAssertEqual(m.hrTrace, [60, 61])
    }

    func testCSVQuotes() {
        let rows = WhoopExport.parseCSV("a,\"b,c\",\"d \"\"e\"\"\"\r\n1,2,3\r\n")
        XCTAssertEqual(rows, [["a", "b,c", "d \"e\""], ["1", "2", "3"]])
    }
}
