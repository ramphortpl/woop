import Foundation

/// Activity families, in the order shown in the activity picker.
enum SportCategory: String, CaseIterable, Sendable {
    case running, cycling, racket, team, combat, fitness, mind, dance, water, winter, outdoor, recovery, daily, other

    var title: String {
        switch self {
        case .running: return "Course, marche et multisport"
        case .cycling: return "Vélo"
        case .racket: return "Sports de raquette"
        case .team: return "Sports collectifs"
        case .combat: return "Sports de combat"
        case .fitness: return "Musculation et fitness"
        case .mind: return "Yoga, souplesse et esprit"
        case .dance: return "Danse, gym et scène"
        case .water: return "Sports nautiques"
        case .winter: return "Sports d'hiver"
        case .outdoor: return "Plein air et adresse"
        case .recovery: return "Récupération"
        case .daily: return "Vie quotidienne"
        case .other: return "Autre"
        }
    }
}

/// One activity type: storage key, French name, SF Symbol candidates (first one available on
/// the device wins), MET value (Compendium of Physical Activities, used only to estimate
/// calories when no heart rate was recorded), and search / import terms (French, English and
/// the WHOOP activity names).
struct SportInfo: Identifiable, Hashable, Sendable {
    let key: String
    let label: String
    let category: SportCategory
    let icons: [String]
    let met: Double
    let terms: [String]
    var id: String { key }
}

enum SportCatalog {
    static let generic = "activite"
    static let fallbackIcon = "figure.mixed.cardio"

    private static func s(_ key: String, _ label: String, _ c: SportCategory, _ icons: [String], _ met: Double, _ terms: [String]) -> SportInfo {
        SportInfo(key: key, label: label, category: c, icons: icons, met: met, terms: terms)
    }

    // Keys of the first version (course, cyclisme, … activite) are kept as they are stored.
    static let all: [SportInfo] = [
        // Course, marche et multisport
        s("course", "Course à pied", .running, ["figure.run"], 9.8, ["running", "run", "jogging", "footing", "course a pied", "course"]),
        s("trail", "Trail", .running, ["figure.hiking", "figure.run"], 9.0, ["trail running", "trail", "ultra trail", "course nature", "skyrunning"]),
        s("tapis", "Tapis de course", .running, ["figure.run.treadmill", "figure.run"], 9.0, ["treadmill", "tapis de course", "tapis"]),
        s("marche", "Marche", .running, ["figure.walk"], 3.5, ["walking", "walk", "marche", "promenade", "balade"]),
        s("marche_rapide", "Marche rapide", .running, ["figure.walk.motion", "figure.walk"], 4.3, ["brisk walking", "power walking", "marche rapide", "marche active", "marche sportive"]),
        s("marche_nordique", "Marche nordique", .running, ["figure.walk", "figure.hiking"], 4.8, ["nordic walking", "marche nordique"]),
        s("randonnee", "Randonnée", .running, ["figure.hiking"], 6.0, ["hiking rucking", "hiking", "rucking", "hike", "trek", "trekking", "randonnee", "rando"]),
        s("athletisme", "Athlétisme", .running, ["figure.track.and.field"], 8.0, ["track field", "track and field", "athletisme", "sprint", "piste", "lancer", "saut"]),
        s("escaliers", "Escaliers / gradins", .running, ["figure.stairs"], 8.0, ["stadium steps", "stairs", "escaliers", "gradins", "monter les escaliers"]),
        s("orientation", "Course d'orientation", .running, ["figure.run", "map"], 9.0, ["orienteering", "course d orientation", "orientation"]),
        s("obstacles", "Course d'obstacles", .running, ["figure.climbing", "figure.run"], 9.0, ["obstacle course racing", "ocr", "spartan race", "tough mudder", "course d obstacles", "mud day"]),
        s("poussette", "Course ou marche avec poussette", .running, ["stroller", "figure.walk"], 4.0, ["stroller walking", "stroller jogging", "poussette", "jogging poussette"]),
        s("chien", "Promenade du chien", .running, ["dog", "figure.walk"], 3.0, ["dog walking", "promenade du chien", "sortir le chien", "canicross"]),
        s("triathlon", "Triathlon", .running, ["figure.open.water.swim", "figure.run"], 9.0, ["triathlon", "ironman"]),
        s("duathlon", "Duathlon", .running, ["figure.run", "figure.outdoor.cycle"], 9.0, ["duathlon", "swimrun", "raid"]),
        s("fauteuil", "Fauteuil roulant", .running, ["figure.roll"], 3.8, ["wheelchair pushing", "wheelchair", "fauteuil roulant", "handisport"]),

        // Vélo
        s("cyclisme", "Cyclisme", .cycling, ["figure.outdoor.cycle"], 7.5, ["cycling", "road cycling", "bike", "biking", "velo", "velo de route", "cyclisme"]),
        s("vtt", "VTT", .cycling, ["figure.outdoor.cycle", "bicycle"], 8.5, ["mountain biking", "mtb", "vtt", "enduro", "descente", "cross country"]),
        s("gravel", "Gravel", .cycling, ["figure.outdoor.cycle", "bicycle"], 8.0, ["gravel", "cyclocross", "cyclo cross"]),
        s("spinning", "Vélo d'appartement / spinning", .cycling, ["figure.indoor.cycle"], 8.5, ["spin", "spinning", "indoor cycling", "home trainer", "velo d appartement", "rpm", "peloton", "biking indoor", "zwift"]),
        s("assault_bike", "Assault bike / air bike", .cycling, ["figure.indoor.cycle"], 8.8, ["assault bike", "air bike", "echo bike", "velo d assaut"]),
        s("velotaf", "Vélo (trajet)", .cycling, ["bicycle", "figure.outdoor.cycle"], 6.8, ["velotaf", "velo trajet", "trajet a velo", "bike commute"]),
        s("velo_elec", "Vélo électrique", .cycling, ["bicycle", "figure.outdoor.cycle"], 5.0, ["e bike", "ebike", "velo electrique", "vae"]),
        s("bmx", "BMX", .cycling, ["bicycle", "figure.outdoor.cycle"], 8.5, ["bmx"]),
        s("handbike", "Handbike", .cycling, ["figure.hand.cycling", "figure.roll"], 6.0, ["hand cycling", "handbike", "handcycling"]),

        // Sports de raquette
        s("tennis", "Tennis", .racket, ["figure.tennis"], 7.3, ["tennis"]),
        s("padel", "Padel", .racket, ["figure.tennis", "figure.racquetball"], 6.5, ["padel", "padel tennis"]),
        s("badminton", "Badminton", .racket, ["figure.badminton"], 6.0, ["badminton", "bad"]),
        s("squash", "Squash", .racket, ["figure.squash"], 7.3, ["squash"]),
        s("tennis_table", "Tennis de table / ping-pong", .racket, ["figure.table.tennis"], 4.0, ["table tennis", "ping pong", "tennis de table", "pingpong"]),
        s("pickleball", "Pickleball", .racket, ["figure.pickleball", "figure.tennis"], 4.5, ["pickleball"]),
        s("racquetball", "Racquetball", .racket, ["figure.racquetball"], 7.0, ["racquetball", "racketball"]),
        s("paddle_tennis", "Paddle tennis", .racket, ["figure.racquetball", "figure.tennis"], 6.0, ["paddle tennis", "platform tennis"]),
        s("beach_tennis", "Beach tennis", .racket, ["figure.tennis"], 6.0, ["beach tennis"]),
        s("pelote", "Pelote basque", .racket, ["figure.racquetball", "figure.handball"], 7.0, ["pelote basque", "pelote", "cesta punta", "jai alai", "frontenis", "frontball"]),

        // Sports collectifs
        s("football", "Football", .team, ["figure.soccer"], 7.0, ["soccer", "football", "foot", "five", "foot a 5", "foot a 7"]),
        s("futsal", "Futsal / foot en salle", .team, ["figure.indoor.soccer", "figure.soccer"], 8.0, ["futsal", "foot en salle", "indoor soccer"]),
        s("basketball", "Basket-ball", .team, ["figure.basketball"], 6.5, ["basketball", "basket", "basket ball", "3x3"]),
        s("volleyball", "Volley-ball", .team, ["figure.volleyball"], 4.0, ["volleyball", "volley", "volley ball"]),
        s("beach_volley", "Beach-volley", .team, ["figure.volleyball"], 8.0, ["beach volleyball", "beach volley"]),
        s("handball", "Handball", .team, ["figure.handball"], 8.0, ["handball", "hand ball"]),
        s("rugby", "Rugby", .team, ["figure.rugby"], 8.3, ["rugby", "rugby a 7", "touch rugby", "rugby a xv", "rugby a xiii"]),
        s("football_us", "Football américain", .team, ["figure.american.football"], 8.0, ["american football", "football americain", "flag football"]),
        s("football_australien", "Football australien", .team, ["figure.australian.football"], 8.0, ["australian football", "aussie rules", "australian rules", "football australien"]),
        s("football_gaelique", "Football gaélique", .team, ["figure.australian.football", "figure.soccer"], 8.0, ["gaelic football", "football gaelique"]),
        s("hurling", "Hurling / camogie", .team, ["figure.field.hockey", "figure.hockey"], 8.0, ["hurling camogie", "hurling", "camogie"]),
        s("baseball", "Baseball", .team, ["figure.baseball"], 5.0, ["baseball"]),
        s("softball", "Softball", .team, ["figure.softball"], 5.0, ["softball"]),
        s("cricket", "Cricket", .team, ["figure.cricket"], 4.8, ["cricket"]),
        s("hockey_glace", "Hockey sur glace", .team, ["figure.ice.hockey", "figure.hockey"], 8.0, ["ice hockey", "hockey sur glace", "hockey"]),
        s("hockey_gazon", "Hockey sur gazon", .team, ["figure.field.hockey", "figure.hockey"], 7.8, ["field hockey", "hockey sur gazon", "hockey en salle"]),
        s("roller_hockey", "Roller hockey", .team, ["figure.hockey"], 7.5, ["roller hockey", "inline hockey"]),
        s("lacrosse", "Crosse (lacrosse)", .team, ["figure.lacrosse"], 8.0, ["lacrosse", "crosse"]),
        s("ultimate", "Ultimate frisbee", .team, ["figure.disc.sports"], 8.0, ["ultimate", "ultimate frisbee", "frisbee"]),
        s("water_polo", "Water-polo", .team, ["figure.waterpolo"], 10.0, ["water polo", "waterpolo"]),
        s("netball", "Netball", .team, ["figure.basketball"], 6.5, ["netball"]),
        s("polo", "Polo", .team, ["figure.equestrian.sports"], 8.0, ["polo"]),
        s("spikeball", "Spikeball / roundnet", .team, ["figure.volleyball"], 6.0, ["spikeball", "roundnet"]),
        s("dodgeball", "Balle aux prisonniers / dodgeball", .team, ["figure.play"], 5.0, ["dodgeball", "balle aux prisonniers", "ballon prisonnier"]),

        // Sports de combat
        s("boxe", "Boxe", .combat, ["figure.boxing"], 7.8, ["boxing", "boxe", "boxe anglaise", "sparring", "sac de frappe"]),
        s("kickboxing", "Kick-boxing", .combat, ["figure.kickboxing"], 8.0, ["kickboxing", "kick boxing", "k1", "full contact"]),
        s("boxe_thai", "Boxe thaï / muay-thaï", .combat, ["figure.kickboxing"], 8.0, ["muay thai", "boxe thai", "thai boxing"]),
        s("savate", "Savate / boxe française", .combat, ["figure.kickboxing"], 8.0, ["savate", "boxe francaise"]),
        s("mma", "MMA / combat libre", .combat, ["figure.martial.arts", "figure.boxing"], 8.5, ["mma", "mixed martial arts", "free fight", "combat libre"]),
        s("arts_martiaux", "Arts martiaux", .combat, ["figure.martial.arts"], 7.0, ["martial arts", "arts martiaux", "kung fu", "krav maga", "self defense", "aikido", "capoeira", "wing chun"]),
        s("jjb", "Jiu-jitsu brésilien / grappling", .combat, ["figure.martial.arts", "figure.wrestling"], 7.5, ["jiu jitsu", "bjj", "jjb", "brazilian jiu jitsu", "grappling", "jujitsu", "ju jitsu", "luta livre"]),
        s("judo", "Judo", .combat, ["figure.martial.arts"], 7.5, ["judo"]),
        s("karate", "Karaté", .combat, ["figure.martial.arts"], 7.0, ["karate"]),
        s("taekwondo", "Taekwondo", .combat, ["figure.martial.arts", "figure.kickboxing"], 7.0, ["taekwondo", "tae kwon do"]),
        s("lutte", "Lutte", .combat, ["figure.wrestling"], 6.0, ["wrestling", "lutte", "sumo"]),
        s("escrime", "Escrime", .combat, ["figure.fencing"], 6.0, ["fencing", "escrime", "sabre", "fleuret", "epee"]),
        s("box_fitness", "Cardio boxe / box fitness", .combat, ["figure.boxing"], 7.0, ["box fitness", "cardio boxing", "boxing fitness", "cardio boxe", "boxe fitness", "body combat"]),

        // Musculation et fitness
        s("musculation", "Musculation", .fitness, ["figure.strengthtraining.traditional", "dumbbell.fill"], 5.0, ["weightlifting", "weight lifting", "weights", "musculation", "muscu", "salle de sport", "bodybuilding", "strength training", "gym"]),
        s("powerlifting", "Powerlifting / force athlétique", .fitness, ["figure.strengthtraining.traditional"], 6.0, ["powerlifting", "force athletique", "strongman"]),
        s("halterophilie", "Haltérophilie", .fitness, ["figure.strengthtraining.traditional"], 6.0, ["olympic weightlifting", "halterophilie", "halteres", "arrache", "epaule jete"]),
        s("crossfit", "Cross-training / CrossFit", .fitness, ["figure.cross.training", "figure.strengthtraining.functional"], 8.0, ["functional fitness", "crossfit", "cross training", "cross fit", "wod", "fitness fonctionnel", "entrainement fonctionnel"]),
        s("hyrox", "Hyrox", .fitness, ["figure.cross.training", "figure.run"], 9.0, ["hyrox", "fitness racing"]),
        s("renforcement", "Renforcement musculaire", .fitness, ["figure.strengthtraining.functional"], 5.0, ["strength trainer", "renforcement", "renfo", "bodyweight", "poids du corps", "kettlebell", "trx", "entraineur de force"]),
        s("callisthenie", "Callisthénie / street workout", .fitness, ["figure.strengthtraining.functional", "figure.play"], 6.0, ["calisthenics", "callisthenie", "street workout"]),
        s("hiit", "HIIT", .fitness, ["figure.highintensity.intervaltraining"], 8.0, ["hiit", "high intensity interval training", "tabata", "f45 training", "f45", "barry s", "barrys", "orangetheory", "bootcamp", "fractionne"]),
        s("circuit", "Circuit training", .fitness, ["figure.cross.training", "figure.highintensity.intervaltraining"], 8.0, ["circuit training", "circuit", "body pump", "bodypump"]),
        s("gainage", "Gainage / abdos", .fitness, ["figure.core.training"], 3.8, ["core training", "core", "gainage", "abdos", "abs", "abdominaux"]),
        s("corde", "Corde à sauter", .fitness, ["figure.jumprope"], 11.0, ["jumping rope", "jump rope", "corde a sauter", "skipping"]),
        s("elliptique", "Vélo elliptique", .fitness, ["figure.elliptical"], 5.0, ["elliptical", "elliptique", "cross trainer", "velo elliptique"]),
        s("stepper", "Stepper / climber", .fitness, ["figure.stair.stepper"], 9.0, ["stairmaster", "stair master", "stepper", "climber", "versaclimber", "stair climber"]),
        s("rameur", "Rameur", .fitness, ["figure.indoor.rowing", "figure.rower"], 7.0, ["rowing machine", "indoor rowing", "ergometer", "erg", "concept2", "rameur"]),
        s("step", "Step", .fitness, ["figure.step.training"], 7.0, ["step aerobics", "step"]),
        s("aerobic", "Aérobic / cardio training", .fitness, ["figure.mixed.cardio"], 7.3, ["aerobics", "aerobic", "cardio training", "cardio", "fitness", "lia"]),
        s("parkour", "Parkour", .fitness, ["figure.climbing", "figure.run"], 8.0, ["parkour", "freerun", "free running"]),
        s("trampoline", "Trampoline", .fitness, ["figure.play"], 4.5, ["trampoline", "jumping fitness"]),

        // Yoga, souplesse et esprit
        s("yoga", "Yoga", .mind, ["figure.yoga"], 2.5, ["yoga", "vinyasa", "hatha", "ashtanga", "yin yoga", "kundalini"]),
        s("yoga_chaud", "Yoga chaud (Bikram)", .mind, ["figure.yoga"], 3.5, ["hot yoga", "bikram", "yoga chaud"]),
        s("pilates", "Pilates", .mind, ["figure.pilates"], 3.0, ["pilates", "reformer"]),
        s("barre", "Barre au sol", .mind, ["figure.barre"], 3.5, ["barre", "barre3", "barre au sol"]),
        s("etirements", "Étirements / mobilité", .mind, ["figure.flexibility", "figure.cooldown"], 2.3, ["stretching", "etirements", "etirement", "mobility", "mobilite", "souplesse"]),
        s("meditation", "Méditation", .mind, ["figure.mind.and.body"], 1.3, ["meditation", "mindfulness", "pleine conscience", "sophrologie"]),
        s("respiration", "Respiration", .mind, ["wind", "lungs"], 1.3, ["breathwork", "respiration", "coherence cardiaque", "breathing"]),
        s("tai_chi", "Tai-chi / qi gong", .mind, ["figure.taichi"], 3.0, ["tai chi", "taichi", "qi gong", "qigong"]),

        // Danse, gym et scène
        s("danse", "Danse", .dance, ["figure.dance"], 5.0, ["dance", "dancing", "danse", "hip hop", "danse classique", "danse contemporaine"]),
        s("danse_salon", "Danse de salon / salsa", .dance, ["figure.socialdance"], 4.5, ["social dance", "salsa", "bachata", "rock", "tango", "danse de salon", "kizomba", "swing"]),
        s("zumba", "Zumba / danse fitness", .dance, ["figure.dance"], 6.5, ["zumba", "dance fitness", "danse fitness"]),
        s("gymnastique", "Gymnastique", .dance, ["figure.gymnastics"], 3.8, ["gymnastics", "gymnastique", "gym artistique", "gym rythmique"]),
        s("cirque", "Arts du cirque", .dance, ["figure.gymnastics"], 4.0, ["circus arts", "cirque", "arts du cirque", "trapeze", "acrobatie", "jonglage"]),
        s("pole_dance", "Pole dance", .dance, ["figure.dance", "figure.gymnastics"], 5.0, ["pole dance", "pole fitness"]),
        s("scene", "Spectacle / scène", .dance, ["theatermasks"], 3.0, ["stage performance", "spectacle", "scene", "theatre", "performance scenique"]),
        s("musique", "Musique (concert)", .dance, ["music.mic", "music.note"], 2.5, ["musical performance", "concert", "musique", "performance musicale", "batterie"]),

        // Sports nautiques
        s("natation", "Natation", .water, ["figure.pool.swim"], 7.0, ["swimming", "swim", "natation", "piscine", "nage"]),
        s("eau_libre", "Nage en eau libre", .water, ["figure.open.water.swim"], 8.0, ["open water swimming", "open water", "eau libre", "nage en mer"]),
        s("surf", "Surf", .water, ["figure.surfing"], 3.0, ["surfing", "surf", "bodyboard"]),
        s("paddle", "Stand-up paddle", .water, ["figure.surfing", "figure.rower"], 6.0, ["paddleboarding", "stand up paddle", "sup", "paddle", "planche a pagaie"]),
        s("kayak", "Kayak / canoë", .water, ["figure.rower", "oar.2.crossed"], 5.0, ["kayaking", "kayak", "canoe", "canoe kayak", "rafting", "pirogue"]),
        s("aviron", "Aviron", .water, ["figure.outdoor.rowing", "figure.rower"], 7.0, ["rowing", "aviron", "crew", "sculling"]),
        s("voile", "Voile", .water, ["figure.sailing", "sailboat"], 3.0, ["sailing", "voile", "regate", "catamaran"]),
        s("kitesurf", "Kitesurf", .water, ["figure.surfing", "wind"], 7.0, ["kite boarding", "kiteboarding", "kitesurf", "kiteboard", "kite"]),
        s("planche_voile", "Planche à voile / wingfoil", .water, ["figure.sailing", "wind"], 5.0, ["windsurfing", "planche a voile", "wingfoil", "wing foil", "windsurf"]),
        s("ski_nautique", "Ski nautique / wakeboard", .water, ["figure.water.fitness", "figure.surfing"], 6.0, ["water skiing", "wakeboarding", "ski nautique", "wakeboard"]),
        s("plongee", "Plongée", .water, ["figure.pool.swim", "water.waves"], 7.0, ["diving", "scuba", "plongee", "apnee", "freediving", "snorkeling"]),
        s("aquagym", "Aquagym / aquabike", .water, ["figure.water.fitness"], 5.3, ["water fitness", "aquagym", "aquabike", "aquafitness", "aqua"]),

        // Sports d'hiver
        s("ski", "Ski alpin", .winter, ["figure.skiing.downhill"], 5.3, ["skiing", "ski", "ski alpin", "downhill skiing", "freeride"]),
        s("ski_fond", "Ski de fond", .winter, ["figure.skiing.crosscountry"], 9.0, ["cross country skiing", "ski de fond", "nordic skiing", "skating ski"]),
        s("ski_rando", "Ski de randonnée", .winter, ["figure.skiing.crosscountry"], 9.0, ["ski touring", "ski de randonnee", "skimo", "ski alpinisme", "splitboard", "backcountry skiing"]),
        s("snowboard", "Snowboard", .winter, ["figure.snowboarding"], 5.3, ["snowboarding", "snowboard"]),
        s("patinage", "Patinage", .winter, ["figure.ice.skating", "figure.skating"], 7.0, ["ice skating", "patinage", "patin a glace", "skating", "patinage artistique"]),
        s("raquettes_neige", "Raquettes à neige", .winter, ["figure.hiking"], 5.3, ["snowshoeing", "raquettes a neige", "snowshoe"]),
        s("biathlon", "Biathlon", .winter, ["figure.skiing.crosscountry"], 9.0, ["biathlon"]),
        s("curling", "Curling", .winter, ["figure.curling"], 4.0, ["curling"]),
        s("luge", "Luge / bobsleigh", .winter, ["figure.skiing.downhill"], 5.0, ["sledding", "luge", "bobsleigh", "toboggan", "skeleton"]),

        // Plein air et adresse
        s("escalade", "Escalade", .outdoor, ["figure.climbing"], 8.0, ["rock climbing", "climbing", "escalade", "grimpe", "via ferrata"]),
        s("bloc", "Escalade de bloc", .outdoor, ["figure.climbing"], 7.5, ["bouldering", "bloc", "escalade de bloc"]),
        s("alpinisme", "Alpinisme", .outdoor, ["figure.climbing", "mountain.2"], 7.0, ["mountaineering", "alpinisme", "haute montagne"]),
        s("equitation", "Équitation", .outdoor, ["figure.equestrian.sports"], 5.5, ["horseback riding", "horse riding", "equitation", "cheval", "dressage", "saut d obstacles"]),
        s("golf", "Golf", .outdoor, ["figure.golf"], 4.8, ["golf", "practice de golf"]),
        s("disc_golf", "Disc golf", .outdoor, ["figure.disc.sports"], 3.0, ["disc golf"]),
        s("skateboard", "Skateboard", .outdoor, ["figure.skateboarding", "skateboard", "figure.roll"], 5.0, ["skateboarding", "skateboard", "skate", "longboard"]),
        s("roller", "Roller / trottinette", .outdoor, ["figure.skating"], 7.5, ["inline skating", "roller", "rollers", "patin a roulettes", "trottinette", "roller skating"]),
        s("tir_arc", "Tir à l'arc", .outdoor, ["figure.archery"], 4.3, ["archery", "tir a l arc"]),
        s("chasse", "Chasse", .outdoor, ["figure.hunting"], 5.0, ["hunting", "chasse"]),
        s("peche", "Pêche", .outdoor, ["figure.fishing"], 3.5, ["fishing", "peche"]),
        s("paintball", "Paintball / airsoft", .outdoor, ["scope"], 6.0, ["paintball", "airsoft", "laser game"]),
        s("parapente", "Parapente", .outdoor, ["wind"], 3.5, ["paragliding", "parapente", "deltaplane"]),
        s("motocross", "Motocross / moto", .outdoor, ["motorcycle", "car"], 4.0, ["motocross", "moto", "dirt bike", "enduro moto", "trial"]),
        s("sport_auto", "Sport automobile / karting", .outdoor, ["steeringwheel", "car"], 2.5, ["motor racing", "karting", "kart", "rallye", "sport automobile", "circuit auto"]),
        s("bowling", "Bowling", .outdoor, ["figure.bowling"], 3.8, ["bowling"]),
        s("petanque", "Pétanque / boules", .outdoor, ["figure.bowling"], 2.5, ["petanque", "boules", "boule lyonnaise", "molkky"]),
        s("caddie", "Caddie (golf)", .outdoor, ["figure.golf"], 4.3, ["caddying", "caddie"]),

        // Récupération
        s("sauna", "Sauna / hammam", .recovery, ["flame", "drop"], 1.5, ["sauna", "hammam", "bain turc", "steam room"]),
        s("bain_froid", "Bain froid", .recovery, ["snowflake", "drop"], 1.5, ["ice bath", "cold plunge", "bain froid", "bain de glace", "douche froide"]),
        s("cryotherapie", "Cryothérapie", .recovery, ["snowflake"], 1.3, ["cryotherapy", "cryotherapie"]),
        s("massage", "Massage", .recovery, ["hand.raised"], 1.3, ["massage therapy", "massage", "kine", "kinesitherapie", "massotherapie", "osteopathe"]),
        s("pistolet_massage", "Pistolet de massage", .recovery, ["hand.raised"], 1.3, ["percussive massage", "theragun", "pistolet de massage", "massage percussif"]),
        s("pressotherapie", "Pressothérapie", .recovery, ["drop"], 1.3, ["air compression", "pressotherapie", "normatec", "compression", "compression d air"]),
        s("recup_active", "Récupération active", .recovery, ["figure.cooldown"], 2.5, ["active recovery", "recuperation active", "decrassage", "cooldown", "retour au calme"]),

        // Vie quotidienne
        s("trajet", "Trajet (marche, transports)", .daily, ["tram", "figure.walk"], 3.5, ["commuting", "trajet", "trajet domicile travail", "transport"]),
        s("travail_manuel", "Travail manuel", .daily, ["hammer"], 4.5, ["manual labor", "travail manuel", "bricolage", "chantier", "demenagement"]),
        s("jardinage", "Jardinage", .daily, ["leaf"], 4.0, ["yard work", "jardinage", "jardin", "tonte"]),
        s("menage", "Ménage", .daily, ["sparkles", "house"], 3.3, ["cleaning", "menage", "nettoyage"]),
        s("cuisine", "Cuisine", .daily, ["fork.knife"], 2.0, ["cooking", "cuisine"]),
        s("enfants", "Temps avec les enfants", .daily, ["figure.2.and.child.holdinghands", "figure.and.child.holdinghands"], 2.8, ["dedicated parenting", "parenting", "enfants", "parentalite", "jouer avec les enfants"]),
        s("portage", "Portage bébé", .daily, ["figure.and.child.holdinghands"], 3.0, ["babywearing", "toddlerwear", "portage", "porte bebe"]),
        s("travail_stress", "Travail sous pression", .daily, ["briefcase"], 1.5, ["high stress work", "travail stressant", "travail tres stressant", "travail a haute pression", "stress"]),
        s("prise_parole", "Prise de parole", .daily, ["mic"], 1.8, ["public speaking", "prise de parole", "presentation", "conference"]),
        s("jeux_video", "Jeux vidéo / e-sport", .daily, ["gamecontroller"], 1.5, ["gaming", "jeux video", "esport", "e sport"]),
        s("spectateur", "Regarder du sport", .daily, ["tv"], 1.3, ["watching sports", "regarder du sport", "spectateur"]),
        s("coaching", "Coaching / entraîner", .daily, ["figure.wave", "person.wave.2"], 4.0, ["coaching", "coach", "entrainer", "encadrement", "arbitrage"]),
        s("operations", "Opérations (militaire, secours)", .daily, ["shield", "cross.case"], 5.0, ["operations tactical", "operations medical", "operations flying", "operations water", "operations", "militaire", "pompier", "secours"]),

        // Autre
        s("activite", "Activité", .other, ["figure.mixed.cardio"], 6.0, ["activity", "activite", "sport", "workout", "entrainement", "seance"]),
        s("autre", "Autre", .other, ["sparkles", "figure.mixed.cardio"], 4.0, ["other", "autre"]),
    ]

    static let byKey: [String: SportInfo] = Dictionary(all.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })

    static func info(_ key: String) -> SportInfo? { byKey[key] }

    /// Activities of a family, alphabetical.
    static func inCategory(_ c: SportCategory) -> [SportInfo] {
        all.filter { $0.category == c }.sorted { normalize($0.label) < normalize($1.label) }
    }

    static func label(_ key: String) -> String { byKey[key]?.label ?? key.replacingOccurrences(of: "_", with: " ").capitalized }

    /// Activities counted in "Temps de musculation".
    static let strengthKeys: Set<String> = ["musculation", "powerlifting", "halterophilie", "crossfit", "renforcement",
                                             "callisthenie", "gainage", "circuit"]

    /// Display name of an activity: an imported WHOOP name that had no exact equivalent is kept.
    static func displayName(_ a: ActivityRecord) -> String {
        if a.source == .imported, let n = a.note, !n.isEmpty, a.sport == generic || a.sport == "autre" { return n }
        return label(a.sport)
    }

    // MARK: Search & import mapping

    static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR")).lowercased()
        var out = ""
        var space = false
        for ch in folded {
            if ch.isLetter || ch.isNumber {
                out.append(ch)
                space = false
            } else if !space && !out.isEmpty {
                out.append(" ")
                space = true
            }
        }
        while out.hasSuffix(" ") { out.removeLast() }
        return out
    }

    /// Activities matching a search (name, terms or family), best matches first.
    static func search(_ query: String) -> [SportInfo] {
        let q = normalize(query)
        guard !q.isEmpty else { return all }
        var scored: [(SportInfo, Int)] = []
        for s in all {
            let label = normalize(s.label)
            var score = -1
            if label.hasPrefix(q) { score = 0 }
            else if label.split(separator: " ").contains(where: { $0.hasPrefix(q) }) { score = 1 }
            else if s.terms.contains(where: { normalize($0).hasPrefix(q) }) { score = 2 }
            else if label.contains(q) || s.terms.contains(where: { normalize($0).contains(q) }) { score = 3 }
            else if normalize(s.category.title).contains(q) { score = 4 }
            if score >= 0 { scored.append((s, score)) }
        }
        return scored.sorted { a, b in
            if a.1 != b.1 { return a.1 < b.1 }
            if a.1 <= 1 && a.0.label.count != b.0.label.count { return a.0.label.count < b.0.label.count }
            return normalize(a.0.label) < normalize(b.0.label)
        }.map(\.0)
    }

    private static let exactIndex: [String: String] = {
        var m: [String: String] = [:]
        for s in all {
            for t in [s.label] + s.terms {
                let n = normalize(t)
                if m[n] == nil { m[n] = s.key }
            }
        }
        return m
    }()

    /// Longest phrases first, so "table tennis" wins over "tennis".
    private static let phraseIndex: [(String, String)] = {
        var list: [(String, String)] = []
        for s in all { for t in [s.label] + s.terms { list.append((normalize(t), s.key)) } }
        return list.filter { $0.0.count >= 3 }.sorted { $0.0.count > $1.0.count }
    }()

    /// Map an activity name from the WHOOP export (English or French) to a key. In WHOOP's
    /// English export "Football" is American football ("Soccer" is football).
    static func match(whoopName: String, englishExport: Bool = false) -> String {
        let n = normalize(whoopName)
        guard !n.isEmpty else { return generic }
        if n == "football" { return englishExport ? "football_us" : "football" }
        if let k = exactIndex[n] { return k }
        let padded = " \(n) "
        for (phrase, key) in phraseIndex where padded.contains(" \(phrase) ") { return key }
        return generic
    }
}
