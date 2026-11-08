import SwiftUI
import UserNotifications

struct MoreView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var strap: StrapManager
    @ObservedObject private var notifier = Notifier.shared
    @State private var showCustomize = false
    @State private var showNotifications = false
    @State private var showImport = false

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    HStack {
                        Text("Plus").font(WFont.title(28)).foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.top, 12)

                    NavigationLink { ProfileEditView() } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(LinearGradient(colors: [Color(hex: 0x6EDBCB), Color(hex: 0x3FB3A6)], startPoint: .top, endPoint: .bottom))
                                Text(app.settings.profile.initials).font(WFont.text(20, weight: .bold)).foregroundColor(Color(hex: 0x10302C))
                            }
                            .frame(width: 56, height: 56)
                            VStack(alignment: .leading, spacing: 3) {
                                let p = app.settings.profile
                                Text("\(p.firstName) \(p.lastName)".trimmingCharacters(in: .whitespaces).isEmpty ? "Mon profil" : "\(p.firstName) \(p.lastName)")
                                    .font(WFont.text(19, weight: .semibold)).foregroundColor(.white)
                                Text("\(p.age) ans · \(Int(p.heightCm)) cm · \(Fmt.dec1(p.weightKg)) kg").font(WFont.text(13)).foregroundColor(Theme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundColor(Theme.textTertiary)
                        }
                        .wCard()
                    }
                    .buttonStyle(.plain)

                    group("Appareil") {
                        link("Mon bracelet", "applewatch.side.right", detail: strap.state.label) { DeviceView() }
                    }
                    group("Notifications") {
                        link("Notifications", "bell.badge", detail: notifier.status == .denied ? "Désactivées" : nil) { NotificationSettingsView() }
                    }
                    group("Sommeil") {
                        link("Besoin de sommeil de base", "moon", detail: Fmt.hmLong(app.settings.profile.baselineSleepNeedHours * 3600)) { SleepSettingsView() }
                    }
                    group("Affichage") {
                        Button { showCustomize = true } label: {
                            rowLabel("Personnaliser le tableau de bord", "slider.horizontal.3", detail: nil)
                        }.buttonStyle(.plain)
                    }
                    group("Données") {
                        link("Importer depuis WHOOP", "square.and.arrow.down", detail: app.importedDays.isEmpty ? nil : "\(app.importedDays.count) j") { WhoopImportView() }
                        Divider().overlay(Theme.separator)
                        link("Données et stockage", "externaldrive", detail: nil) { DataSettingsView() }
                        Divider().overlay(Theme.separator)
                        Toggle(isOn: Binding(get: { app.settings.demoMode }, set: { app.setDemoMode($0) })) {
                            rowLabel("Mode démo", "play.rectangle", detail: nil)
                        }
                        .tint(Theme.recoveryGreen)
                    }
                    group("À propos") {
                        link("Licences et crédits", "doc.text", detail: nil) { AboutView() }
                    }
                    Text("Woop \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")) — application indépendante, non affiliée à WHOOP, Inc.")
                        .font(WFont.text(11)).foregroundColor(Theme.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .withAppRoutes()
        .fullScreenCover(isPresented: $showCustomize) { DashboardCustomizeView() }
        .navigationDestination(isPresented: $showNotifications) { NotificationSettingsView() }
        .navigationDestination(isPresented: $showImport) { WhoopImportView() }
        .onAppear {
            // CI screenshots (-woopScreen).
            switch app.launchScreen {
            case "notifications": if !showNotifications { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showNotifications = true } }
            case "import": if !showImport { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showImport = true } }
            default: break
            }
        }
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).wLabel(11.4, color: Color(hex: 0x8C8F92)).padding(.leading, 4)
            VStack(spacing: 12, content: content).wCard()
        }
    }

    private func rowLabel(_ t: String, _ icon: String, detail: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 17, weight: .light)).foregroundColor(Color(hex: 0x9A9EA2)).frame(width: 26)
            Text(t).font(WFont.text(15.5, weight: .medium)).foregroundColor(.white)
            Spacer()
            if let detail { Text(detail).font(WFont.text(13)).foregroundColor(Theme.textSecondary).lineLimit(1) }
        }
        .contentShape(Rectangle())
    }

    private func link<D: View>(_ t: String, _ icon: String, detail: String?, @ViewBuilder _ dest: @escaping () -> D) -> some View {
        NavigationLink {
            dest()
        } label: {
            HStack {
                rowLabel(t, icon, detail: detail)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .light)).foregroundColor(Theme.textTertiary)
            }
        }
        .buttonStyle(.plain)
    }
}

struct ProfileEditView: View {
    @EnvironmentObject var app: AppState
    @State private var p = UserProfile()
    @State private var maxHR = ""
    @State private var loaded = false

    var body: some View {
        DetailScaffold(title: "Profil") {
            CardBox(title: "Identité") {
                field("Prénom", text: $p.firstName)
                field("Nom", text: $p.lastName)
                Picker("Sexe", selection: $p.sex) {
                    Text("Homme").tag(UserProfile.Sex.male)
                    Text("Femme").tag(UserProfile.Sex.female)
                }
                .pickerStyle(.segmented)
                Stepper("Année de naissance : \(String(p.birthYear))", value: $p.birthYear, in: 1930...2015)
                    .foregroundColor(.white)
            }
            CardBox(title: "Mensurations") {
                Stepper("Taille : \(Int(p.heightCm)) cm", value: $p.heightCm, in: 120...230, step: 1).foregroundColor(.white)
                Stepper("Poids : \(Fmt.dec1(p.weightKg)) kg", value: $p.weightKg, in: 30...250, step: 0.5).foregroundColor(.white)
            }
            CardBox(title: "Fréquence cardiaque maximale") {
                TextField("Automatique (\(Int(p.tanakaMaxHR)) bpm estimés)", text: $maxHR)
                    .keyboardType(.numberPad)
                    .foregroundColor(.white)
                Text("Laisse vide pour une estimation automatique, ajustée avec tes pics observés.")
                    .font(WFont.text(12)).foregroundColor(Theme.textTertiary)
            }
            OutlineButton(title: "Enregistrer") {
                p.maxHROverride = Int(maxHR.trimmingCharacters(in: .whitespaces))
                app.settings.profile = p
                app.recomputeAll()
            }
            .padding(.horizontal, 28)
        }
        .onAppear {
            if !loaded {
                p = app.settings.profile
                maxHR = p.maxHROverride.map(String.init) ?? ""
                loaded = true
            }
        }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        TextField(label, text: text)
            .textInputAutocapitalization(.words)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.cardInner.opacity(0.6)))
            .foregroundColor(.white)
    }
}

struct SleepSettingsView: View {
    @EnvironmentObject var app: AppState
    @State private var need = 7.75
    @State private var wake = Date()

    var body: some View {
        DetailScaffold(title: "Sommeil") {
            CardBox(title: "Besoin de sommeil de base") {
                Stepper("\(Fmt.hmLong(need * 3600))", value: $need, in: 6...10, step: 0.25).foregroundColor(.white)
                Text("Ton besoin réel de chaque nuit y ajoute l'effort de la veille et la dette de sommeil, moins les siestes.")
                    .font(WFont.text(12)).foregroundColor(Theme.textTertiary)
            }
            CardBox(title: "Heure de lever habituelle") {
                DatePicker("Réveil", selection: $wake, displayedComponents: .hourAndMinute).foregroundColor(.white)
                Text("Utilisée pour l'heure de coucher recommandée quand l'alarme est désactivée (sinon la médiane de tes réveils récents).")
                    .font(WFont.text(12)).foregroundColor(Theme.textTertiary)
            }
            OutlineButton(title: "Enregistrer") {
                app.settings.profile.baselineSleepNeedHours = need
                let c = DayKey.calendar.dateComponents([.hour, .minute], from: wake)
                app.settings.profile.usualWakeMinute = (c.hour ?? 7) * 60 + (c.minute ?? 0)
                app.recomputeAll()
            }
            .padding(.horizontal, 28)
        }
        .onAppear {
            need = app.settings.profile.baselineSleepNeedHours
            let m = app.settings.profile.usualWakeMinute
            wake = DayKey.calendar.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
        }
    }
}

struct DataSettingsView: View {
    @EnvironmentObject var app: AppState
    @State private var stats: (oldest: Int?, newest: Int?, count: Int) = (nil, nil, 0)
    @State private var size: Int64 = 0
    @State private var confirmWipe = false
    @State private var calibration = 1.0

    var body: some View {
        DetailScaffold(title: "Données et stockage") {
            CardBox(title: "Sur cet iPhone") {
                row("Secondes enregistrées", Fmt.int(Double(stats.count)))
                row("Première donnée", stats.oldest.map { Date(timeIntervalSince1970: TimeInterval($0)).formatted(date: .abbreviated, time: .shortened) } ?? "—")
                row("Dernière donnée", stats.newest.map { Date(timeIntervalSince1970: TimeInterval($0)).formatted(date: .abbreviated, time: .shortened) } ?? "—")
                row("Jours calculés", "\(app.days.count)")
                row("Taille de la base", ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
            }
            CardBox(title: "Importer depuis WHOOP") {
                NavigationLink { WhoopImportView() } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Importer mon export WHOOP").font(WFont.text(16, weight: .semibold)).foregroundColor(.white)
                            Text(app.importedDays.isEmpty ? "Scores WHOOP exacts pour tes jours passés" : "\(app.importedDays.count) jours WHOOP importés")
                                .font(WFont.text(12)).foregroundColor(app.importedDays.isEmpty ? Theme.textTertiary : Theme.recoveryGreen)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundColor(Theme.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            CardBox(title: "Calibrage des pas") {
                Stepper("Diviseur : \(Fmt.dec1(calibration))×", value: $calibration, in: 0.5...30, step: 0.1).foregroundColor(.white)
                Text("Si le bracelet compte trop de pas, augmente ce diviseur.").font(WFont.text(12)).foregroundColor(Theme.textTertiary)
                Button { app.settings.stepCalibration = calibration; app.recomputeAll() } label: {
                    Text("Appliquer").wLabel(12.5, color: Theme.accentBlue)
                }.buttonStyle(.plain)
            }
            CardBox(title: "Recalcul") {
                Button { app.recomputeAll() } label: {
                    HStack {
                        Text("Recalculer toutes les journées").wLabel(12.5, color: Theme.accentBlue)
                        if app.computing { ProgressView().tint(.white) }
                    }
                }.buttonStyle(.plain)
            }
            CardBox(title: "Effacer") {
                Button(role: .destructive) { confirmWipe = true } label: {
                    Text("Supprimer toutes mes données").wLabel(12.5, color: Theme.recoveryRed)
                }.buttonStyle(.plain)
            }
        }
        .onAppear(perform: refresh)
        .confirmationDialog("Supprimer toutes les données ?", isPresented: $confirmWipe, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                Database.shared.wipeAll()
                app.loadStored()
                refresh()
            }
            Button("Annuler", role: .cancel) {}
        } message: { Text("Cette action est irréversible.") }
    }

    private func refresh() {
        stats = Database.shared.sampleStats()
        size = Database.shared.fileSize
        calibration = app.settings.stepCalibration
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(WFont.text(14)).foregroundColor(Theme.textSecondary)
            Spacer()
            Text(v).font(WFont.text(14, weight: .semibold)).foregroundColor(.white)
        }
    }
}

struct AboutView: View {
    var body: some View {
        DetailScaffold(title: "Licences et crédits") {
            CardBox {
                Text("Woop est une application indépendante et non officielle. Elle n'est ni affiliée, ni approuvée par WHOOP, Inc. « WHOOP » est une marque de son propriétaire, utilisée uniquement pour désigner le matériel compatible.")
                    .font(WFont.text(13)).foregroundColor(Theme.textSecondary)
            }
            CardBox(title: "Sources") {
                Text("NOOP (ryanbr/noop) — Licence PolyForm Noncommercial 1.0.0. Required Notice: Copyright 2026 NoopApp. Recette de stadification du sommeil et score de récupération adaptés, pour un usage personnel non commercial.")
                    .font(WFont.text(12)).foregroundColor(Theme.textSecondary)
                Text("OpenStrap edge / protocol / analytics — documentation du protocole WHOOP 5.0 (séquence d'appairage, enregistrements v18, acquittement de l'historique) et méthodes publiées utilisées pour l'effort et le coaching du sommeil.")
                    .font(WFont.text(12)).foregroundColor(Theme.textSecondary)
                Text("Polices Barlow Semi Condensed, Montserrat et Figtree — SIL Open Font License 1.1.")
                    .font(WFont.text(12)).foregroundColor(Theme.textSecondary)
            }
            CardBox(title: "Méthodes publiées") {
                Text("RMSSD (Task Force 1996), filtre de Malik, TRIMP de Banister (1991), réserve cardiaque de Karvonen, FC max de Tanaka (2001), dépense de Keytel (2005), métabolisme de Mifflin–St Jeor, VO₂max d'Uth (2004), arythmie sinusale respiratoire.")
                    .font(WFont.text(12)).foregroundColor(Theme.textSecondary)
            }
            CardBox {
                Text("Woop n'est pas un dispositif médical. Toutes les mesures sont des estimations.")
                    .font(WFont.text(12)).foregroundColor(Theme.textTertiary)
            }
        }
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var strap: StrapManager
    @State private var step = 0
    @State private var p = UserProfile()

    var body: some View {
        ZStack {
            ScreenBackground()
            VStack(spacing: 0) {
                switch step {
                case 0: welcome
                case 1: profile
                default: pair
                }
            }
            .padding(20)
        }
        .preferredColorScheme(.dark)
    }

    private var welcome: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                ScoreRing(progress: 0.76, color: Theme.sleep, lineWidth: 8, size: 170, valueText: "", valueSize: 1)
                ScoreRing(progress: 0.62, color: Theme.recoveryGreen, lineWidth: 8, size: 140, valueText: "", valueSize: 1)
                ScoreRing(progress: 0.55, color: Theme.strain, lineWidth: 8, size: 110, valueText: "", valueSize: 1)
            }
            Wordmark()
            Text("Ton WHOOP, sans abonnement.\nSommeil, récupération et effort calculés sur ton iPhone, sans compte ni cloud.")
                .font(WFont.text(16)).foregroundColor(Theme.textSecondary).multilineTextAlignment(.center)
            Spacer()
            OutlineButton(title: "Commencer") { step = 1 }
        }
    }

    private var profile: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ton profil").font(WFont.title(26)).foregroundColor(.white).padding(.top, 20)
            Text("Utilisé pour la fréquence cardiaque maximale, les calories et ta récupération.")
                .font(WFont.text(14)).foregroundColor(Theme.textSecondary)
            ScrollView {
                VStack(spacing: 14) {
                    TextField("Prénom", text: $p.firstName)
                        .padding(14).background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                    TextField("Nom", text: $p.lastName)
                        .padding(14).background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                    Picker("Sexe", selection: $p.sex) {
                        Text("Homme").tag(UserProfile.Sex.male)
                        Text("Femme").tag(UserProfile.Sex.female)
                    }
                    .pickerStyle(.segmented)
                    Stepper("Année de naissance : \(String(p.birthYear))", value: $p.birthYear, in: 1930...2015)
                    Stepper("Taille : \(Int(p.heightCm)) cm", value: $p.heightCm, in: 120...230)
                    Stepper("Poids : \(Fmt.dec1(p.weightKg)) kg", value: $p.weightKg, in: 30...250, step: 0.5)
                }
                .foregroundColor(.white)
            }
            OutlineButton(title: "Continuer") {
                app.settings.profile = p
                step = 2
                strap.start()
                strap.startScan()
            }
        }
    }

    private var pair: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connecte ton WHOOP").font(WFont.title(26)).foregroundColor(.white).padding(.top, 20)
            ScrollView { PairingCard() }
            if strap.state.isConnected {
                Text("Connecté ! La première synchronisation de l'historique peut prendre quelques minutes.")
                    .font(WFont.text(14)).foregroundColor(Theme.recoveryGreen)
            }
            OutlineButton(title: strap.state.isConnected ? "Terminer" : "Plus tard") {
                strap.stopScan()
                app.settings.onboardingDone = true
                app.recompute(daysBack: nil)
                Notifier.shared.requestAuthorization()
            }
            Button {
                strap.stopScan()
                app.settings.onboardingDone = true
                app.setDemoMode(true)
            } label: {
                Text("Découvrir avec des données de démo").wLabel(12, color: Theme.textSecondary)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
    }
}
