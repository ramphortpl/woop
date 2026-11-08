import SwiftUI
import MapKit
import CoreLocation

/// "Commencer l'activité", as in the WHOOP app: full-screen map, dark header with the sport,
/// "Suivi d'itinéraire" switch, a big blue circle with the live heart rate ("DÉCONNECTÉ" when the
/// strap is not connected), and a white bottom sheet with the strain target and the start button.
/// While the activity runs: same layout with the live effort, time, calories and route.
struct StartActivityView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var strap: StrapManager
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var workout = LiveWorkout.shared
    @State private var sport: String = SportRecents.keys.first ?? "course"
    @State private var showSports = false
    @State private var confirmCancel = false
    private let demoTick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var session: LiveSession? { app.liveSession }
    private var today: DayMetrics? { app.day(app.today) }
    private var target: Double? { StrainTarget.optimal(for: today?.recovery) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                RouteMapView(route: workout.route, follow: app.settings.routeTracking)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    header(topInset: geo.safeAreaInsets.top)
                    routeSwitch.padding(.top, 9)
                    Spacer(minLength: 0)
                    bottomSheet(bottomInset: geo.safeAreaInsets.bottom)
                }
                .ignoresSafeArea()

                // The circle sits in the middle of the map between the header and the sheet.
                LiveHRCircleContainer(recording: session != nil)
                    .position(x: geo.size.width / 2, y: circleY(geo))
            }
        }
        .background(Color.black)
        .statusBarHidden(false)
        .onAppear {
            if let s = session { sport = s.sport }
            workout.preview(routeTracking: app.settings.routeTracking)
            StrapManager.shared.setLiveWanted(true)
        }
        .onDisappear {
            workout.stopPreview()
            if app.liveSession == nil { StrapManager.shared.setLiveWanted(false) }
        }
        .onReceive(demoTick) { _ in
            // Demo mode: a plausible heart rate so the live screens can be explored.
            guard app.settings.demoMode else { return }
            let base = app.liveSession == nil ? 74.0 : 134.0
            let v = base + 7 * sin(Date().timeIntervalSince1970 / 9) + Double.random(in: -2...2)
            StrapManager.shared.simulateLive(Int(v.rounded()))
        }
        .sheet(isPresented: $showSports) {
            SportPickerView(selected: sport) { picked in
                sport = picked
                if session != nil { app.changeLiveSport(picked) }
            }
        }
        .confirmationDialog("Annuler l'activité ?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Annuler sans enregistrer", role: .destructive) {
                app.endLiveSession(save: false)
                dismiss()
            }
            Button("Continuer l'activité", role: .cancel) {}
        }
        .preferredColorScheme(.dark)
    }

    /// Centre of the circle, in safe-area coordinates: midway between the header band (84 pt
    /// under the status bar) and the top of the bottom sheet (195 pt high, taller while recording).
    private func circleY(_ geo: GeometryProxy) -> CGFloat {
        let top: CGFloat = 84
        let bottom = geo.size.height + geo.safeAreaInsets.bottom - sheetHeight(geo.safeAreaInsets.bottom)
        return (top + bottom) / 2
    }

    private func sheetHeight(_ bottomInset: CGFloat) -> CGFloat {
        session == nil ? 195 : 268
    }

    // MARK: Header

    private func header(topInset: CGFloat) -> some View {
        HStack(spacing: 0) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 19, weight: .regular)).foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.pressable)
            Button { showSports = true } label: {
                HStack(spacing: 0) {
                    Image(systemName: Sport.icon(sport)).font(.system(size: 25, weight: .regular)).foregroundColor(.white)
                        .frame(width: 30)
                        .padding(.leading, 9)
                    Text(Sport.label(sport)).wLabel(12.9, weight: .semibold, tracking: 0.6).lineLimit(1).minimumScaleFactor(0.7)
                        .padding(.leading, 13)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down").font(.system(size: 15, weight: .regular)).foregroundColor(.white)
                        .padding(.trailing, 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 15)
        .padding(.trailing, 15)
        .frame(height: 44)
        .padding(.top, topInset + 21)
        .padding(.bottom, 19)
        .background(Color(hex: 0x0A0B0F).opacity(0.93))
    }

    private var routeSwitch: some View {
        VStack(alignment: .trailing, spacing: 8) {
            routeToggle
            if app.settings.routeTracking && (workout.authorization == .denied || workout.authorization == .restricted) {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    Text("Position refusée : Réglages › Woop › Position")
                        .font(WFont.text(12, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 20)
            }
        }
    }

    private var routeToggle: some View {
        HStack(spacing: 18) {
            Spacer()
            Text("Suivi d'itinéraire").font(WFont.label(14, weight: .semibold)).tracking(1.6)
                .foregroundColor(Color.black.opacity(0.62))
            WhoopSwitch(isOn: Binding(get: { app.settings.routeTracking }, set: { on in
                app.settings.routeTracking = on
                if on { workout.preview(routeTracking: true) }
            }), onColor: Theme.strainBadge, track: Color.black.opacity(0.42))
        }
        .padding(.trailing, 20)
    }

    // MARK: Bottom sheet

    private func bottomSheet(bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(hex: 0xE6E6E6)).frame(width: 63, height: 4.3).padding(.top, 10)
            if let s = session {
                running(s)
            } else {
                targetRow.frame(height: 57)
                VStack(spacing: 0) {
                    PrimaryButton(title: "Commencer l'activité") {
                        Haptics.success()
                        SportRecents.add(sport)
                        app.startLiveSession(sport: sport)
                    }
                    .padding(.horizontal, 60)
                    .padding(.top, 35)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 124 + max(0, bottomInset - 34))
                .background(Color(hex: 0xF6F6F6))
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(TopRoundedShape(radius: 14))
    }

    /// Strain target of the day: ring = today's effort so far against the target.
    private var targetRow: some View {
        let dayStrain: Double = today?.strain ?? 0
        let current: Double = session == nil ? dayStrain : (workout.dayStrain ?? dayStrain)
        let goal: Double? = app.settings.strainTargetOn ? target : nil
        let progress: Double = goal.map { current / max(1, $0) } ?? 0
        return HStack(spacing: 0) {
            MiniStrainRing(progress: progress)
                .frame(width: 25, height: 25)
            Text(target.map { Fmt.dec1($0) } ?? "—").font(WFont.number(20.5, weight: .bold)).foregroundColor(.black)
                .padding(.leading, 15)
            Text("Objectif d'effort").wLabel(12.9, color: .black, tracking: 0.55)
                .padding(.leading, 30)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            WhoopSwitch(isOn: Binding(get: { app.settings.strainTargetOn }, set: { app.settings.strainTargetOn = $0 }),
                        onColor: .black, track: Color(hex: 0xE6E6E6))
        }
        .padding(.leading, 27)
        .padding(.trailing, 20)
        .opacity(target == nil ? 0.5 : 1)
    }

    private var distanceText: String {
        guard workout.distanceM >= 1 else { return "—" }
        let km: String = String(format: "%.2f", workout.distanceM / 1000).replacingOccurrences(of: ".", with: ",")
        return km + " km"
    }

    private var runningProgress: Double {
        let live: Double = workout.dayStrain ?? 0
        if let t = target { return live / max(1, t) }
        return workout.strain / 21
    }

    private func running(_ s: LiveSession) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                MiniStrainRing(progress: runningProgress)
                    .frame(width: 25, height: 25)
                Text(Fmt.dec1(workout.strain)).font(WFont.number(20.5, weight: .bold)).foregroundColor(.black)
                    .padding(.leading, 15)
                Text("Effort de l'activité").wLabel(12.3, color: .black, tracking: 0.5)
                    .padding(.leading, 20).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 6)
                if let t = target, app.settings.strainTargetOn {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Objectif").wLabel(8.5, color: Color(hex: 0x8A8D91))
                        Text(Fmt.dec1(t)).font(WFont.number(15, weight: .bold)).foregroundColor(.black)
                    }
                }
            }
            .padding(.horizontal, 22)
            .frame(height: 50)

            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                HStack(spacing: 0) {
                    stat("Durée", Fmt.timer(Int(ctx.date.timeIntervalSince1970) - s.start))
                    if app.settings.routeTracking {
                        stat("Distance", distanceText)
                    }
                    stat("Calories", Fmt.int(workout.calories))
                    stat("FC moy.", workout.avgHR.map { Fmt.int($0) } ?? "—")
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

            VStack(spacing: 6) {
                PrimaryButton(title: "Terminer l'activité") {
                    Haptics.success()
                    app.endLiveSession(save: true)
                    dismiss()
                }
                .padding(.horizontal, 50)
                Button { confirmCancel = true } label: {
                    Text("Annuler l'activité").wLabel(10.5, color: Color(hex: 0x8A8D91)).padding(8)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            .padding(.top, 18)
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .background(Color(hex: 0xF6F6F6))
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(title).wLabel(8.8, color: Color(hex: 0x8A8D91))
            Text(value).font(WFont.number(21, weight: .bold)).foregroundColor(.black).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Rounded only at the top (bottom sheet).
struct TopRoundedShape: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: [.topLeft, .topRight],
                          cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}

/// Only the circle follows the 1 Hz heart rate.
private struct LiveHRCircleContainer: View {
    var recording: Bool
    @EnvironmentObject var app: AppState
    @EnvironmentObject var strap: StrapManager
    @ObservedObject private var live = StrapManager.shared.live
    @ObservedObject private var workout = LiveWorkout.shared

    var body: some View {
        LiveHRCircle(bpm: (strap.state.isConnected || app.settings.demoMode) ? live.bpm : nil,
                     zone: recording ? workout.zone : nil, recording: recording)
    }
}

/// Big blue circle with its halo: live BPM, or "DÉCONNECTÉ" with the Bluetooth rune.
struct LiveHRCircle: View {
    var bpm: Int?
    var zone: Int?
    var recording: Bool

    private let blue = Color(hex: 0x438DD4)

    var body: some View {
        ZStack {
            Circle().fill(blue.opacity(0.2)).frame(width: 325, height: 325)
            TimelineView(.animation(minimumInterval: 1 / 30, paused: bpm == nil)) { ctx in
                // Gentle pulse at the heart rate.
                let t: Double = ctx.date.timeIntervalSinceReferenceDate
                let beat: Double = bpm.map { Double($0) / 60 } ?? 0
                let wave: Double = max(0, sin(t * beat * Double.pi))
                let phase: Double = beat > 0 ? pow(wave, 8) : 0
                Circle().fill(blue.opacity(0.93))
                    .frame(width: 193, height: 193)
                    .scaleEffect(1 + 0.025 * phase)
            }
            if let bpm {
                VStack(spacing: 0) {
                    Text("\(bpm)").font(WFont.number(78, weight: .bold)).foregroundColor(.white)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.25), value: bpm)
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill").font(.system(size: 12))
                        Text("BPM").wLabel(13, weight: .bold, tracking: 1)
                    }
                    .foregroundColor(.white.opacity(0.9))
                    .offset(y: -6)
                    if recording, let zone, zone > 0 {
                        Text("Zone \(zone)").wLabel(10.5, color: Color(hex: 0x16365E), tracking: 0.8).padding(.top, 6)
                    }
                }
                .offset(y: 4)
            } else {
                VStack(spacing: 22) {
                    Text("Déconnecté").wLabel(18.6, weight: .bold, tracking: 0.2)
                    BluetoothGlyph()
                        .stroke(Color(hex: 0x225586), style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .miter))
                        .frame(width: 12, height: 23)
                }
                .offset(y: 13)
            }
        }
        .frame(width: 325, height: 325)
        .allowsHitTesting(false)
    }
}

/// The Bluetooth rune.
struct BluetoothGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.26))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.73))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.27))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.74))
        return p
    }
}

/// Small ring of the strain target row.
struct MiniStrainRing: View {
    var progress: Double

    var body: some View {
        ZStack {
            Circle().inset(by: 1.4).stroke(Color(hex: 0xEEEEEE), lineWidth: 2.8)
            Circle().inset(by: 1.4)
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(LinearGradient(colors: [Color(hex: 0x1F4A80), Color(hex: 0x3B7BC0)], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 2.8, lineCap: .butt))
                .rotationEffect(.degrees(-90))
        }
        .animation(.easeOut(duration: 0.5), value: progress)
    }
}

/// WHOOP-style switch: big round knob on a pill track (54 × 30 pt).
struct WhoopSwitch: View {
    @Binding var isOn: Bool
    var onColor: Color
    var track: Color

    var body: some View {
        Button {
            Haptics.select()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(track).frame(width: 55, height: 30)
                Circle().fill(isOn ? onColor : Color(hex: 0xBDBFC2))
                    .frame(width: 28.5, height: 28.5)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            }
            .frame(width: 55, height: 30)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "activé" : "désactivé")
    }
}

/// Dark, muted Apple map that follows the wearer and draws the route.
struct RouteMapView: UIViewRepresentable {
    var route: [CLLocationCoordinate2D]
    var follow: Bool
    var interactive = true

    func makeUIView(context: Context) -> MKMapView {
        let m = MKMapView()
        m.overrideUserInterfaceStyle = .dark
        m.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        m.showsCompass = false
        m.showsScale = false
        m.isPitchEnabled = false
        m.isRotateEnabled = false
        m.isUserInteractionEnabled = interactive
        m.delegate = context.coordinator
        m.showsUserLocation = true
        let start = route.last ?? CLLocationManager().location?.coordinate ?? CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522)
        m.setRegion(MKCoordinateRegion(center: start, latitudinalMeters: 1100, longitudinalMeters: 1100), animated: false)
        if follow { m.setUserTrackingMode(.follow, animated: false) }
        return m
    }

    func updateUIView(_ m: MKMapView, context: Context) {
        let c = context.coordinator
        if route.count != c.drawn {
            if let old = c.line { m.removeOverlay(old) }
            c.line = nil
            if route.count >= 2 {
                let l = MKPolyline(coordinates: route, count: route.count)
                m.addOverlay(l)
                c.line = l
            }
            c.drawn = route.count
        }
        if follow && m.userTrackingMode == .none && m.isUserLocationVisible == false && c.followRequested == false {
            c.followRequested = true
            m.setUserTrackingMode(.follow, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var line: MKPolyline?
        var drawn = 0
        var followRequested = false

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let r = MKPolylineRenderer(overlay: overlay)
            r.strokeColor = UIColor(red: 0.26, green: 0.57, blue: 0.89, alpha: 1)
            r.lineWidth = 5
            r.lineCap = .round
            r.lineJoin = .round
            return r
        }
    }
}

/// Static map of a recorded route (activity detail).
struct RouteSnapshotMap: UIViewRepresentable {
    var route: [RoutePoint]

    func makeUIView(context: Context) -> MKMapView {
        let m = MKMapView()
        m.overrideUserInterfaceStyle = .dark
        m.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        m.isUserInteractionEnabled = false
        m.showsCompass = false
        m.delegate = context.coordinator
        let coords = route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        let line = MKPolyline(coordinates: coords, count: coords.count)
        m.addOverlay(line)
        m.setVisibleMapRect(line.boundingMapRect, edgePadding: UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30), animated: false)
        return m
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {}

    func makeCoordinator() -> RouteMapView.Coordinator { RouteMapView.Coordinator() }
}
