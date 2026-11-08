import XCTest
@testable import WoopCore

final class SportTests: XCTestCase {
    func testCatalogIsConsistent() {
        let keys = SportCatalog.all.map(\.key)
        XCTAssertEqual(Set(keys).count, keys.count, "duplicate keys")
        XCTAssertGreaterThan(keys.count, 150)
        // Keys stored by the first version must still resolve.
        for k in ["course", "cyclisme", "randonnee", "marche", "musculation", "natation", "yoga", "hiit", "crossfit",
                  "football", "tennis", "padel", "ski", "aviron", "boxe", "danse", "escalade", "activite"] {
            XCTAssertNotNil(SportCatalog.info(k), k)
        }
        for s in SportCatalog.all {
            XCTAssertFalse(s.icons.isEmpty, s.key)
            XCTAssertGreaterThan(s.met, 1, s.key)
        }
        XCTAssertGreaterThanOrEqual(SportCatalog.inCategory(.racket).count, 10)
    }

    func testWhoopActivityNames() {
        let english: [String: String] = [
            "Running": "course", "Cycling": "cyclisme", "Hiking/Rucking": "randonnee", "Functional Fitness": "crossfit",
            "Weightlifting": "musculation", "Table Tennis": "tennis_table", "Tennis": "tennis", "Padel": "padel",
            "Paddle Tennis": "paddle_tennis", "Pickleball": "pickleball", "Badminton": "badminton", "Squash": "squash",
            "Soccer": "football", "Football": "football_us", "Track & Field": "athletisme", "Jiu Jitsu": "jjb",
            "Operations - Tactical": "operations", "Ice Bath": "bain_froid", "Spin": "spinning", "Assault Bike": "assault_bike",
            "Climber": "stepper", "Rock Climbing": "escalade", "Barry's": "hiit", "F45 Training": "hiit", "Hot Yoga": "yoga_chaud",
            "Stroller Jogging": "poussette", "Kite Boarding": "kitesurf", "Australian Football": "football_australien",
            "Hurling/Camogie": "hurling", "Wheelchair Pushing": "fauteuil", "Strength Trainer": "renforcement",
            "Cross Country Skiing": "ski_fond", "Skiing": "ski", "Ice Hockey": "hockey_glace", "Field Hockey": "hockey_gazon",
            "Obstacle Course Racing": "obstacles", "Activity": "activite", "Other": "autre",
        ]
        for (name, key) in english {
            XCTAssertEqual(SportCatalog.match(whoopName: name, englishExport: true), key, name)
        }
        let french: [String: String] = [
            "Course à pied": "course", "Football": "football", "Football américain": "football_us", "Tennis de table": "tennis_table",
            "Vélo d'appartement": "spinning", "Musculation": "musculation", "Randonnée": "randonnee", "Patinage sur glace": "patinage",
            "Hockey sur glace": "hockey_glace", "Opérations - Tactique": "operations", "Volley-ball": "volleyball",
        ]
        for (name, key) in french {
            XCTAssertEqual(SportCatalog.match(whoopName: name), key, name)
        }
        XCTAssertEqual(SportCatalog.match(whoopName: "Kin-ball"), "activite")
    }

    func testSearch() {
        XCTAssertEqual(SportCatalog.search("pad").first?.key, "padel")
        XCTAssertTrue(SportCatalog.search("raquette").contains { $0.key == "badminton" })
        XCTAssertTrue(SportCatalog.search("ping").contains { $0.key == "tennis_table" })
        XCTAssertEqual(SportCatalog.search("velo").first?.category, .cycling)
        XCTAssertTrue(SportCatalog.search("muscu").contains { $0.key == "musculation" })
        XCTAssertEqual(SportCatalog.search("").count, SportCatalog.all.count)
    }

    func testImportedNameKept() {
        var a = ActivityRecord(id: "whoop-1", sport: "activite", start: 0, end: 60, source: .imported)
        a.note = "Kin-ball"
        XCTAssertEqual(SportCatalog.displayName(a), "Kin-ball")
        a.sport = "padel"
        XCTAssertEqual(SportCatalog.displayName(a), "Padel")
    }
}
