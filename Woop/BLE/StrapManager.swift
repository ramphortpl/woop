import Foundation
import CoreBluetooth
import Combine

enum StrapConnState: Equatable {
    case bluetoothOff
    case unauthorized
    case idle
    case scanning
    case connecting
    case settingUp
    case connected
    case failed(String)

    var label: String {
        switch self {
        case .bluetoothOff: return "Bluetooth désactivé"
        case .unauthorized: return "Accès Bluetooth refusé"
        case .idle: return "Non connecté"
        case .scanning: return "Recherche…"
        case .connecting: return "Connexion…"
        case .settingUp: return "Initialisation…"
        case .connected: return "Connecté"
        case .failed(let m): return m
        }
    }

    var isConnected: Bool { self == .connected }
}

struct DiscoveredStrap: Identifiable, Equatable {
    let id: UUID
    var name: String
    var rssi: Int
    var generation: BandGeneration?
}

struct StrapLogLine: Identifiable {
    let id = UUID()
    let date: Date
    let text: String
}

/// CoreBluetooth driver for WHOOP 5.0 / MG (and 4.0).
///
/// Connection sequence for WHOOP 5.0 follows the order OpenStrap edge pinned from the official
/// client: discover → (iOS bonds on the first encrypted access) → 600 ms → subscribe
/// cmd-from (0003) → memfault (0007, optional) → data (0005) → events (0004) → 500 ms →
/// mandatory GET_HELLO (0x91) → clock contract (SET_CLOCK when ≥ 2 s off) → advertising name →
/// READY → history drain (GET_DATA_RANGE + SEND_HISTORICAL_DATA) with commit-before-ACK.
///
/// All mutable state lives on `queue`; published values are mirrored to the main thread.
/// Realtime heart rate from the strap (about once per second while streaming).
final class LiveHeartRate: ObservableObject {
    @Published fileprivate(set) var bpm: Int?
    /// When the last beat value arrived (not published: it changes every second).
    fileprivate(set) var date: Date?

    fileprivate func set(_ v: Int?, at d: Date? = nil) {
        date = d
        if bpm != v { bpm = v }
    }
}

/// History transfer progress (updated many times per second during a sync).
final class SyncProgress: ObservableObject {
    @Published fileprivate(set) var seconds = 0
    @Published fileprivate(set) var newest: Date?
}

/// Bluetooth journal shown in Plus › Appareil › Journal.
final class StrapLog: ObservableObject {
    @Published fileprivate(set) var lines: [StrapLogLine] = []
}

final class StrapManager: NSObject, ObservableObject {
    static let shared = StrapManager()

    // MARK: Published (main thread)
    @Published private(set) var state: StrapConnState = .idle
    @Published private(set) var discovered: [DiscoveredStrap] = []
    @Published private(set) var battery: Double?
    @Published private(set) var charging = false
    @Published private(set) var wristOn: Bool?
    @Published private(set) var strapName: String?
    @Published private(set) var serial: String?
    @Published private(set) var firmware: String?
    @Published private(set) var model: String?
    @Published private(set) var syncing = false
    @Published private(set) var lastSync: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var pairedID: UUID?

    // Fast-changing values live in their own small observable objects, so a 1 Hz heart rate or
    // a sync progress counter only redraws the few views that display them (not every screen
    // observing the strap).
    let live = LiveHeartRate()
    let progress = SyncProgress()
    let logs = StrapLog()
    var liveHR: Int? { live.bpm }
    var liveHRDate: Date? { live.date }
    var syncedThisSession: Int { progress.seconds }
    var syncNewest: Date? { progress.newest }
    var log: [StrapLogLine] { logs.lines }

    /// Called on the BLE queue after a history batch is durable (sample count, newest ts).
    var onHistoryCommitted: ((Int, Int?) -> Void)?
    /// Called on the BLE queue when the strap reports its history is fully drained.
    var onDrainComplete: (() -> Void)?

    // MARK: Private (queue)
    private let queue = DispatchQueue(label: "woop.ble", qos: .userInitiated)
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var generation: BandGeneration = .gen5
    private var bandProfile: BandProfile { .of(generation) }
    private var gatt: GattProfile { .of(generation) }
    private var chars: [String: CBCharacteristic] = [:] // keyed by role
    private var hrMeasurement: CBCharacteristic?
    private var batteryChar: CBCharacteristic?
    private var reassemblers: [CBUUID: FrameReassembler] = [:]
    private var seq = SeqAllocator()
    private var drain = HistoryDrain(profile: .gen5)
    private var pendingServices = 0
    private var subscribeQueue: [CBCharacteristic] = []
    private var bootstrapped = false
    private var wantScan = false
    private var userInitiatedConnect = false
    private var foreground = true
    private var liveWanted = false
    private var liveEnabledOnStrap = false
    private var liveBuffer: [HistorySample] = []
    private var lastLiveFlush = Date()
    private var lastLinkValid = Date.distantPast
    private var lastBatteryPoll = Date.distantPast
    private var lastHistoryTraffic = Date()
    private var drainStartedAt: Date?
    private var reconnectDelay: TimeInterval = 2
    private var timer: DispatchSourceTimer?
    private var hello: Gen5Hello?
    /// Queue-side mirrors of published values (never read @Published state off the main thread).
    private var qState: StrapConnState = .idle
    private var qPairedID: UUID?
    private var found: [DiscoveredStrap] = []
    private var lastForeignTraffic = Date.distantPast
    private var backgroundLive = false
    private var drainWaiters: [(Bool) -> Void] = []
    private var drainStarting = false

    private struct Waiter {
        let id: Int
        let opcode: UInt8
        let seq: UInt8?
        let completion: (CommandResponse?) -> Void
    }
    private var waiters: [Waiter] = []
    private var waiterID = 0

    private enum Keys {
        static let paired = "woop.strap.paired"
        static let generation = "woop.strap.generation"
        static let name = "woop.strap.name"
        static let lastSync = "woop.strap.lastSync"
    }

    private override init() {
        super.init()
        let saved = UserDefaults.standard.string(forKey: Keys.paired).flatMap(UUID.init(uuidString:))
        pairedID = saved
        qPairedID = saved
        if let t = UserDefaults.standard.object(forKey: Keys.lastSync) as? Date {
            lastSync = t
            lastSyncDateOnQueue = t
        }
        if let g = UserDefaults.standard.string(forKey: Keys.generation).flatMap(BandGeneration.init(rawValue:)) {
            generation = g
        }
        strapName = UserDefaults.standard.string(forKey: Keys.name)
    }

    /// Create the central (prompts for Bluetooth permission on first launch).
    func start() {
        queue.async {
            guard self.central == nil else { return }
            self.central = CBCentralManager(delegate: self, queue: self.queue, options: [
                CBCentralManagerOptionRestoreIdentifierKey: "woop.central",
                CBCentralManagerOptionShowPowerAlertKey: true,
            ])
            self.startTimer()
        }
    }

    // MARK: - Public API

    func startScan() {
        queue.async {
            self.wantScan = true
            self.found.removeAll()
            self.publish { $0.discovered = [] }
            self.scanIfPossible()
        }
    }

    func stopScan() {
        queue.async {
            self.wantScan = false
            if self.central?.isScanning == true { self.central.stopScan() }
            if self.qState == .scanning, self.peripheral == nil { self.setState(.idle) }
        }
    }

    func connect(to id: UUID) {
        queue.async {
            guard let central = self.central, central.state == .poweredOn else { return }
            self.wantScan = false
            if central.isScanning { central.stopScan() }
            guard let p = central.retrievePeripherals(withIdentifiers: [id]).first else {
                self.logLine("Bracelet introuvable — relance la recherche.")
                return
            }
            if let d = self.found.first(where: { $0.id == id }), let g = d.generation { self.generation = g }
            self.userInitiatedConnect = true
            self.attach(p)
        }
    }

    /// Forget the strap: disconnect and stop auto-reconnecting.
    func forget() {
        queue.async {
            if let p = self.peripheral { self.central?.cancelPeripheralConnection(p) }
            self.peripheral = nil
            UserDefaults.standard.removeObject(forKey: Keys.paired)
            UserDefaults.standard.removeObject(forKey: Keys.name)
            self.qPairedID = nil
            self.userInitiatedConnect = false
            self.publish { $0.pairedID = nil; $0.strapName = nil; $0.battery = nil; $0.live.set(nil) }
            self.setState(.idle)
        }
    }

    func disconnect() {
        queue.async {
            if let p = self.peripheral { self.central?.cancelPeripheralConnection(p) }
        }
    }

    /// Ask the strap for everything it has banked since the last sync.
    func syncNow() {
        queue.async { self.startDrain(reason: "manuel") }
    }

    /// Keep the realtime HR stream on while the app is in the background (continuous live data;
    /// costs strap battery). Off by default.
    func setBackgroundLive(_ on: Bool) {
        queue.async {
            self.backgroundLive = on
            self.reconcileLive()
        }
    }

    /// Start a sync (if connected) and wait for it to finish, up to `timeout` seconds.
    /// Used by the background refresh task. Returns whether a drain completed.
    func syncAndWait(timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            queue.async {
                guard self.bootstrapped, let p = self.peripheral, p.state == .connected else {
                    cont.resume(returning: false)
                    return
                }
                var resumed = false
                let finish: (Bool) -> Void = { ok in
                    if resumed { return }
                    resumed = true
                    cont.resume(returning: ok)
                }
                let running = self.drain.ownDrainActive || self.drainStarting
                if !running && !self.startDrain(reason: "arrière-plan") {
                    // Nothing was started (another app is transferring, or not ready).
                    finish(false)
                    return
                }
                self.drainWaiters.append(finish)
                self.queue.asyncAfter(deadline: .now() + timeout) {
                    self.drainWaiters.removeAll()
                    finish(false)
                }
            }
        }
    }

    func setForeground(_ fg: Bool) {
        queue.async {
            self.foreground = fg
            self.reconcileLive()
            if fg { self.maybeAutoSync(minInterval: 120) }
        }
    }

    /// Keep the realtime HR stream on (live activity / live screen).
    /// Demo mode only: a simulated heart rate for the live screens.
    func simulateLive(_ bpm: Int?) {
        DispatchQueue.main.async { self.live.set(bpm, at: bpm == nil ? nil : Date()) }
    }

    func setLiveWanted(_ on: Bool) {
        queue.async {
            self.liveWanted = on
            self.reconcileLive()
        }
    }

    func buzz() {
        queue.async { self.send(WhoopCommands.buzz(seq: self.seq.nextLive(), profile: self.bandProfile)) }
    }

    /// Arm the strap's own (firmware) wake alarm.
    func setAlarm(_ date: Date?) {
        queue.async {
            guard self.bootstrapped else { return }
            if let date {
                self.send(WhoopCommands.setAlarm(seq: self.seq.nextLive(), at: date, profile: self.bandProfile))
                self.logLine("Alarme programmée sur le bracelet : \(date.formatted(date: .abbreviated, time: .shortened))")
            } else {
                self.send(WhoopCommands.disableAlarm(seq: self.seq.nextLive(), profile: self.bandProfile))
                self.logLine("Alarme du bracelet désactivée")
            }
        }
    }

    // MARK: - Internals

    private func publish(_ f: @escaping (StrapManager) -> Void) {
        DispatchQueue.main.async { f(self) }
    }

    private func setState(_ s: StrapConnState) {
        qState = s
        publish { $0.state = s }
    }

    private func logLine(_ s: String) {
        let line = StrapLogLine(date: Date(), text: s)
        publish {
            $0.logs.lines.append(line)
            if $0.logs.lines.count > 400 { $0.logs.lines.removeFirst($0.logs.lines.count - 400) }
        }
    }

    private func scanIfPossible() {
        guard wantScan, let c = central, c.state == .poweredOn else { return }
        if !c.isScanning {
            c.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
        if peripheral == nil { setState(.scanning) }
        // Straps already connected at the OS level (e.g. bonded to this iPhone) don't advertise.
        let connected = c.retrieveConnectedPeripherals(withServices: [CBUUID(string: GattProfile.gen5.service), CBUUID(string: GattProfile.gen4.service)])
        for p in connected {
            addDiscovered(DiscoveredStrap(id: p.identifier, name: p.name ?? "WHOOP", rssi: 0, generation: nil))
        }
    }

    private func addDiscovered(_ d: DiscoveredStrap) {
        if let i = found.firstIndex(where: { $0.id == d.id }) {
            found[i].rssi = d.rssi
            if found[i].generation == nil { found[i].generation = d.generation }
        } else {
            found.append(d)
        }
        let snapshot = found.sorted { $0.rssi > $1.rssi }
        publish { $0.discovered = snapshot }
    }

    private func attach(_ p: CBPeripheral) {
        peripheral = p
        p.delegate = self
        bootstrapped = false
        setState(.connecting)
        logLine("Connexion à \(p.name ?? "WHOOP")…")
        central.connect(p, options: nil)
    }

    private func reconnectSaved() {
        guard let c = central, c.state == .poweredOn, peripheral == nil else { return }
        let services = [CBUUID(string: GattProfile.gen5.service), CBUUID(string: GattProfile.gen4.service)]
        if let id = qPairedID, let p = c.retrievePeripherals(withIdentifiers: [id]).first {
            attach(p) // pending connect: iOS completes it whenever the strap is in range
        } else if qPairedID != nil, let p = c.retrieveConnectedPeripherals(withServices: services).first {
            attach(p)
        }
    }

    private func resetLink() {
        chars.removeAll()
        hrMeasurement = nil
        batteryChar = nil
        reassemblers.removeAll()
        subscribeQueue.removeAll()
        pendingServices = 0
        bootstrapped = false
        liveEnabledOnStrap = false
        hello = nil
        seq.reset()
        let w = waiters
        waiters.removeAll()
        w.forEach { $0.completion(nil) }
        if drain.ownDrainActive { drain.endOwnDrain() }
        drain = HistoryDrain(profile: bandProfile)
        drainStarting = false
        failDrainWaiters()
        publish { $0.syncing = false; $0.live.set(nil) }
    }

    // MARK: Writes & awaited responses

    @discardableResult
    private func send(_ frame: [UInt8]) -> Bool {
        guard let p = peripheral, let c = chars["cmdTo"], p.state == .connected else { return false }
        guard let f = Framing.parseFrame(frame, profile: bandProfile), !Cmd.dangerous.contains(f.opcode) else {
            logLine("Commande refusée (opcode dangereux)")
            return false
        }
        p.writeValue(Data(frame), for: c, type: .withResponse)
        return true
    }

    /// Send a command and wait for ITS reply (matched on opcode, and on sequence when echoed).
    private func request(_ frame: [UInt8], opcode: UInt8, seq: UInt8, timeout: TimeInterval,
                         completion: @escaping (CommandResponse?) -> Void) {
        waiterID += 1
        let id = waiterID
        waiters.append(Waiter(id: id, opcode: opcode, seq: seq, completion: completion))
        if !send(frame) {
            resolveWaiter(id: id, with: nil)
            return
        }
        queue.asyncAfter(deadline: .now() + timeout) { [weak self] in self?.resolveWaiter(id: id, with: nil) }
    }

    private func resolveWaiter(id: Int, with r: CommandResponse?) {
        guard let i = waiters.firstIndex(where: { $0.id == id }) else { return }
        let w = waiters.remove(at: i)
        w.completion(r)
    }

    private func deliver(_ r: CommandResponse) {
        if r.pending { return } // a real reply follows
        let match = waiters.firstIndex { $0.opcode == r.opcode && ($0.seq == r.requestSeq) }
            ?? waiters.firstIndex { $0.opcode == r.opcode }
        if let i = match {
            let w = waiters.remove(at: i)
            w.completion(r)
        }
    }

    // MARK: Bootstrap

    private func beginSubscriptions() {
        let order = ["cmdFrom", "memfault", "data", "events"]
        subscribeQueue = order.compactMap { chars[$0] }
        if let hr = hrMeasurement, chars["cmdTo"] == nil { subscribeQueue.append(hr) }
        guard chars["cmdTo"] != nil, chars["cmdFrom"] != nil, chars["data"] != nil else {
            // Not a WHOOP custom service we can drive: fall back to the standard HR profile.
            if let hr = hrMeasurement {
                peripheral?.setNotifyValue(true, for: hr)
                logLine("Mode fréquence cardiaque standard (service 0x180D)")
                setState(.connected)
            } else {
                fail("Service WHOOP introuvable sur cet appareil")
            }
            return
        }
        let delay: TimeInterval = generation == .gen5 ? 0.6 : 0.1
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in self?.subscribeNext() }
    }

    private func subscribeNext() {
        guard let p = peripheral, p.state == .connected else { return }
        if subscribeQueue.isEmpty {
            let delay: TimeInterval = generation == .gen5 ? 0.5 : 0.1
            queue.asyncAfter(deadline: .now() + delay) { [weak self] in self?.runHello() }
            return
        }
        let c = subscribeQueue.removeFirst()
        p.setNotifyValue(true, for: c)
    }

    private func runHello(attempt: Int = 1) {
        setState(.settingUp)
        let s = seq.nextLive()
        let frame = WhoopCommands.hello(seq: s, profile: bandProfile)
        let opcode = generation == .gen5 ? Cmd.getHello : Cmd.getHelloHarvard
        request(frame, opcode: opcode, seq: s, timeout: 5) { [weak self] r in
            guard let self else { return }
            if self.generation == .gen5 {
                guard let r, r.success, let h = r.gen5Hello else {
                    if attempt < 3 {
                        self.logLine("HELLO sans réponse (essai \(attempt)) — nouvel essai")
                        self.queue.asyncAfter(deadline: .now() + 1) { self.runHello(attempt: attempt + 1) }
                    } else {
                        self.fail("Le bracelet ne répond pas. Ferme l'app WHOOP officielle, puis tape sur le bracelet jusqu'à ce que les LED clignotent en bleu, et réessaie.")
                    }
                    return
                }
                self.absorbHello(h)
                self.clockContract(helloTs: h.timestampOrNil, subsec: h.tsSubseconds)
            } else {
                // gen4: hello body layout drifts across firmware; only the reply matters.
                self.setClockThenReady()
            }
        }
    }

    private func absorbHello(_ h: Gen5Hello) {
        hello = h
        logLine("HELLO : \(h.modelName), série \(h.serial), firmware \(h.firmware), batterie \(h.batteryPct.map { String(format: "%.0f %%", $0) } ?? "?")")
        publish {
            $0.model = h.modelName
            $0.serial = h.serial.isEmpty ? nil : h.serial
            $0.firmware = h.firmware
            if let b = h.batteryPct { $0.battery = b }
            $0.charging = h.charging
            $0.wristOn = h.wristOn
        }
    }

    private func clockContract(helloTs: Int?, subsec: Int) {
        if let ts = helloTs {
            let strapMs = Double(ts) * 1000 + Double(subsec) * 1000 / 32768
            let delta = abs(Date().timeIntervalSince1970 * 1000 - strapMs)
            if delta < 2000 {
                logLine("Horloge du bracelet synchronisée (écart \(Int(delta)) ms)")
                readNameThenReady()
                return
            }
        }
        let s = seq.nextLive()
        request(WhoopCommands.setClock(seq: s, date: Date(), profile: bandProfile), opcode: Cmd.setClock, seq: s, timeout: 5) { [weak self] r in
            guard let self else { return }
            guard r != nil else {
                self.fail("Impossible de régler l'horloge du bracelet")
                return
            }
            self.logLine("Horloge du bracelet réglée")
            self.readNameThenReady()
        }
    }

    private func setClockThenReady() {
        let s = seq.nextLive()
        request(WhoopCommands.setClock(seq: s, date: Date(), profile: bandProfile), opcode: Cmd.setClock, seq: s, timeout: 3) { [weak self] _ in
            self?.ready()
        }
    }

    private func readNameThenReady() {
        let s = seq.nextLive()
        request(WhoopCommands.getAdvertisingName(seq: s, profile: bandProfile), opcode: Cmd.getCustomAdvertisingName, seq: s, timeout: 3) { [weak self] r in
            guard let self else { return }
            if let name = r?.advertisingName {
                UserDefaults.standard.set(name, forKey: Keys.name)
                self.publish { $0.strapName = name }
            }
            self.ready()
        }
    }

    private func ready() {
        guard let p = peripheral else { return }
        bootstrapped = true
        reconnectDelay = 2
        UserDefaults.standard.set(p.identifier.uuidString, forKey: Keys.paired)
        UserDefaults.standard.set(generation.rawValue, forKey: Keys.generation)
        qPairedID = p.identifier
        publish { $0.pairedID = p.identifier; $0.lastError = nil }
        setState(.connected)
        logLine("Connecté — prêt (\(generation.label))")
        if let b = batteryChar { p.readValue(for: b) }
        pollBattery(force: true)
        if generation == .gen4 {
            for (i, pkt) in WhoopCommands.gen4InitPackets.enumerated() {
                queue.asyncAfter(deadline: .now() + 0.12 * Double(i)) { [weak self] in
                    guard let self else { return }
                    if i == 4 { self.drain.beginOwnDrain(); self.markDrainStarted() }
                    self.send(pkt)
                }
            }
        } else {
            startDrain(reason: "connexion")
        }
        reconcileLive()
    }

    private func fail(_ message: String) {
        logLine("Échec : \(message)")
        publish { $0.lastError = message }
        setState(.failed(message))
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
    }

    // MARK: History drain

    private func markDrainStarted() {
        drainStartedAt = Date()
        lastHistoryTraffic = Date()
        publish { $0.syncing = true; $0.progress.seconds = 0 }
    }

    @discardableResult
    private func startDrain(reason: String) -> Bool {
        guard bootstrapped, !drain.ownDrainActive, !drainStarting else { return false }
        // Another app on this phone (e.g. the official one) is draining: bank its bursts instead.
        guard Date().timeIntervalSince(lastForeignTraffic) > 90 else {
            logLine("Transfert déjà en cours par une autre app — données récupérées au passage")
            return false
        }
        logLine("Synchronisation de l'historique (\(reason))…")
        if generation == .gen4 {
            drain.beginOwnDrain()
            markDrainStarted()
            send(WhoopCommands.sendHistorical(seq: seq.nextLive(), profile: bandProfile))
            return true
        }
        drainStarting = true
        send(WhoopCommands.getDataRange(seq: seq.nextLive(), profile: bandProfile))
        queue.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            self.drainStarting = false
            guard self.bootstrapped else { return }
            self.drain.beginOwnDrain()
            self.markDrainStarted()
            self.send(WhoopCommands.sendHistorical(seq: self.seq.nextLive(), profile: self.bandProfile))
        }
        return true
    }

    private func failDrainWaiters() {
        let w = drainWaiters
        drainWaiters.removeAll()
        w.forEach { $0(false) }
    }

    private func maybeAutoSync(minInterval: TimeInterval) {
        guard bootstrapped, !drain.ownDrainActive else { return }
        let last = lastSyncDateOnQueue ?? .distantPast
        if Date().timeIntervalSince(last) >= minInterval { startDrain(reason: "auto") }
    }

    private var lastSyncDateOnQueue: Date?

    private func handleMarker(_ m: HistoryMarker) {
        lastHistoryTraffic = Date()
        switch drain.onMarker(m) {
        case .none:
            break
        case let .commit(samples, events, token):
            let ok = Database.shared.insertSamples(samples, source: .history)
            Database.shared.insertEvents(events)
            if !ok {
                logLine("Écriture locale impossible — lot refusé, le bracelet le renverra")
                send(WhoopCommands.historyResultFail(seq: seq.nextSync(), profile: bandProfile))
                return
            }
            if let token, let ack = WhoopCommands.historyResultOK(seq: seq.nextSync(), token: token, profile: bandProfile) {
                send(ack)
            }
            let newest = samples.map(\.ts).max()
            let total = drain.totalSamples
            publish {
                $0.progress.seconds = total
                if let n = newest { $0.progress.newest = Date(timeIntervalSince1970: TimeInterval(n)) }
            }
            onHistoryCommitted?(samples.count, newest)
        case let .refuse(shortfall):
            logLine("Lot incomplet (\(shortfall) paquet(s) manquant(s)) — demandé à nouveau")
            send(WhoopCommands.historyResultFail(seq: seq.nextSync(), profile: bandProfile))
        case .abort:
            logLine("Trop d'échecs de transfert — synchronisation interrompue")
            send(WhoopCommands.abortHistorical(seq: seq.nextLive(), profile: bandProfile))
            drain.endOwnDrain()
            failDrainWaiters()
            publish { $0.syncing = false }
        case .complete:
            let n = drain.totalSamples
            logLine("Historique synchronisé (\(n) secondes de données)")
            let now = Date()
            lastSyncDateOnQueue = now
            UserDefaults.standard.set(now, forKey: Keys.lastSync)
            publish { $0.syncing = false; $0.lastSync = now }
            onDrainComplete?()
            let waiters = drainWaiters
            drainWaiters.removeAll()
            waiters.forEach { $0(true) }
            reconcileLive()
        }
    }

    // MARK: Live HR

    private func reconcileLive() {
        guard bootstrapped, chars["cmdTo"] != nil else { return }
        let want = foreground || liveWanted || backgroundLive
        guard want != liveEnabledOnStrap else { return }
        send(WhoopCommands.toggleRealtimeHR(seq: seq.nextLive(), on: want, profile: bandProfile))
        liveEnabledOnStrap = want
        if !want { publish { $0.live.set(nil) } }
    }

    private func absorbLive(bpm: Int, rr: [Int], unix: Int?) {
        guard bpm > 0 else {
            publish { $0.live.set(nil) }
            return
        }
        let now = Date()
        publish { $0.live.set(bpm, at: now) }
        let ts = unix.flatMap { plausibleUnix($0) ? $0 : nil } ?? Int(now.timeIntervalSince1970)
        var s = HistorySample(ts: ts, hr: UInt8(clamping: bpm))
        s.setRR(rr)
        liveBuffer.append(s)
        if liveBuffer.count >= 30 || now.timeIntervalSince(lastLiveFlush) > 30 { flushLive() }
    }

    private func flushLive() {
        guard !liveBuffer.isEmpty else { return }
        Database.shared.insertSamples(liveBuffer, source: .live)
        liveBuffer.removeAll()
        lastLiveFlush = Date()
    }

    // MARK: Frames

    private func handle(_ frame: Frame) {
        guard frame.decodable else { return }
        switch frame.packetType {
        case PacketType.commandResponse:
            guard let r = CommandResponse.parse(frame.inner) else { return }
            if let b = r.batteryPct(profile: bandProfile) { publish { $0.battery = b } }
            deliver(r)
        case PacketType.realtimeData:
            if let hr = RealtimeHR.parse(frame.inner) {
                absorbLive(bpm: hr.wearing ? hr.bpm : 0, rr: hr.rr, unix: hr.unix)
            }
        case PacketType.historicalData:
            lastHistoryTraffic = Date()
            if !drain.ownDrainActive { lastForeignTraffic = Date() }
            drain.onHistoricalPacket(frame)
        case PacketType.metadata:
            if let m = HistoryMarker.parse(frame.inner) { handleMarker(m) }
        case PacketType.event:
            drain.onBurstMember(frame)
            if let e = StrapEvent.parse(frame.inner) { handleEvent(e) }
        default:
            if PacketType.isBurstCountMember(frame.packetType) {
                lastHistoryTraffic = Date()
                drain.onBurstMember(frame)
            }
        }
    }

    private func handleEvent(_ e: StrapEvent) {
        // Historical events replayed in a burst are old; only react to fresh ones.
        let fresh = abs(Double(e.unix) - Date().timeIntervalSince1970) < 120
        switch e.id {
        case EventID.batteryLevel:
            if fresh, let b = e.batteryPct {
                publish { $0.battery = b; if let c = e.batteryCharging { $0.charging = c } }
            }
        case EventID.chargingOn, EventID.chargingOff:
            if fresh { publish { $0.charging = e.id == EventID.chargingOn } }
        case EventID.wristOn, EventID.wristOff:
            if fresh { publish { $0.wristOn = e.id == EventID.wristOn } }
        case EventID.doubleTap:
            if fresh { logLine("Double tape détectée sur le bracelet") }
        case EventID.rtcLost:
            if fresh, bootstrapped {
                logLine("Horloge du bracelet perdue — réglage")
                send(WhoopCommands.setClock(seq: seq.nextLive(), date: Date(), profile: bandProfile))
            }
        default:
            break
        }
    }

    private func handleStandardHR(_ data: Data) {
        let b = [UInt8](data)
        guard b.count >= 2 else { return }
        let flags = b[0]
        var i = 1
        let bpm: Int
        if flags & 0x01 != 0, b.count >= 3 { bpm = Int(b[1]) | (Int(b[2]) << 8); i = 3 } else { bpm = Int(b[1]); i = 2 }
        if flags & 0x08 != 0 { i += 2 } // energy expended
        var rr: [Int] = []
        if flags & 0x10 != 0 {
            while i + 1 < b.count {
                let v = (Int(b[i]) | (Int(b[i + 1]) << 8)) * 1000 / 1024
                if v >= RRBounds.min && v <= RRBounds.max { rr.append(v) }
                i += 2
            }
        }
        absorbLive(bpm: bpm, rr: rr, unix: nil)
    }

    // MARK: Timers

    private func startTimer() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 5, repeating: 5)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    private func tick() {
        let now = Date()
        if now.timeIntervalSince(lastLiveFlush) > 30 { flushLive() }
        guard bootstrapped, let p = peripheral, p.state == .connected else { return }
        if drain.ownDrainActive {
            // Idle watchdog: a drain that went silent is abandoned (the strap keeps its checkpoint).
            if now.timeIntervalSince(lastHistoryTraffic) > 60 {
                logLine("Synchronisation inactive — interrompue, reprise plus tard")
                send(WhoopCommands.abortHistorical(seq: seq.nextLive(), profile: bandProfile))
                drain.endOwnDrain()
                failDrainWaiters()
                publish { $0.syncing = false }
            }
            return
        }
        let linkEvery: TimeInterval = foreground ? 10 : 60
        if now.timeIntervalSince(lastLinkValid) >= linkEvery {
            lastLinkValid = now
            send(WhoopCommands.linkValid(seq: seq.nextLive(), profile: bandProfile))
        }
        pollBattery(force: false)
        maybeAutoSync(minInterval: 15 * 60)
    }

    private func pollBattery(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastBatteryPoll) > 300 else { return }
        lastBatteryPoll = now
        send(WhoopCommands.getBattery(seq: seq.nextLive(), profile: bandProfile))
    }
}

// MARK: - CBCentralManagerDelegate

extension StrapManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if let p = peripheral, !bootstrapped {
                // Restored by iOS (or Bluetooth toggled): resume the bootstrap on this link.
                p.delegate = self
                if p.state == .connected { centralManager(central, didConnect: p) } else { attach(p) }
            } else if peripheral == nil {
                setState(.idle)
                reconnectSaved()
            }
            scanIfPossible()
        case .poweredOff:
            resetLink()
            peripheral = nil
            setState(.bluetoothOff)
        case .unauthorized:
            setState(.unauthorized)
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let ps = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral], let p = ps.first {
            peripheral = p
            p.delegate = self
            logLine("Session Bluetooth restaurée par iOS")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        let uuids = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map { $0.uuidString.uppercased() }
        var gen: BandGeneration?
        if uuids.contains(where: { $0.hasPrefix("FD4B") }) { gen = .gen5 }
        if uuids.contains(where: { $0.hasPrefix("61080001") }) { gen = .gen4 }
        guard gen != nil || name.lowercased().contains("whoop") else { return }
        addDiscovered(DiscoveredStrap(id: peripheral.identifier, name: name.isEmpty ? "WHOOP" : name,
                                      rssi: RSSI.intValue, generation: gen))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        resetLink()
        self.peripheral = peripheral
        setState(.settingUp)
        logLine("Connecté au niveau radio — découverte des services")
        peripheral.discoverServices([
            CBUUID(string: GattProfile.gen5.service), CBUUID(string: GattProfile.gen4.service),
            CBUUID(string: GattProfile.heartRateService), CBUUID(string: GattProfile.batteryService),
        ])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        logLine("Connexion échouée : \(error?.localizedDescription ?? "inconnue")")
        scheduleReconnect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        flushLive()
        let wasReady = bootstrapped
        resetLink()
        if let e = error { logLine("Déconnecté : \(e.localizedDescription)") } else { logLine("Déconnecté") }
        let failed: Bool = { if case .failed = qState { return true } else { return false } }()
        if qPairedID != nil {
            // Known strap: keep a pending connection so it comes back whenever in range.
            if !failed { setState(wasReady ? .connecting : .idle) }
            scheduleReconnect(peripheral)
        } else if userInitiatedConnect && !failed {
            setState(.connecting)
            scheduleReconnect(peripheral)
        } else {
            // First pairing failed: wait for the user to try again (no repeated pairing prompts).
            self.peripheral = nil
            userInitiatedConnect = false
            if !failed { setState(.idle) }
        }
    }

    private func scheduleReconnect(_ p: CBPeripheral) {
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, 60)
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let c = self.central, c.state == .poweredOn else { return }
            guard self.peripheral?.identifier == p.identifier || self.peripheral == nil else { return }
            self.peripheral = p
            p.delegate = self
            c.connect(p, options: nil) // pending until the strap is in range
        }
    }
}

// MARK: - CBPeripheralDelegate

extension StrapManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services, error == nil else {
            fail("Découverte des services impossible")
            return
        }
        if services.contains(where: { $0.uuid == CBUUID(string: GattProfile.gen5.service) }) { generation = .gen5 }
        else if services.contains(where: { $0.uuid == CBUUID(string: GattProfile.gen4.service) }) { generation = .gen4 }
        drain = HistoryDrain(profile: bandProfile)
        pendingServices = services.count
        for s in services { peripheral.discoverCharacteristics(nil, for: s) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let g = gatt
        for c in service.characteristics ?? [] {
            let u = c.uuid.uuidString.uppercased()
            switch u {
            case g.cmdTo: chars["cmdTo"] = c
            case g.cmdFrom: chars["cmdFrom"] = c
            case g.events: chars["events"] = c
            case g.data: chars["data"] = c
            case g.memfault: chars["memfault"] = c
            default:
                if c.uuid == CBUUID(string: GattProfile.heartRateMeasurement) { hrMeasurement = c }
                if c.uuid == CBUUID(string: GattProfile.batteryLevel) { batteryChar = c }
            }
            if c.properties.contains(.notify) || c.properties.contains(.indicate) {
                reassemblers[c.uuid] = FrameReassembler(profile: bandProfile)
            }
        }
        pendingServices -= 1
        if pendingServices <= 0 { beginSubscriptions() }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            let isMemfault = characteristic.uuid.uuidString.uppercased() == gatt.memfault
            if isMemfault {
                subscribeNext()
                return
            }
            let ns = error as NSError
            let authError = ns.domain == CBATTErrorDomain &&
                (ns.code == CBATTError.insufficientEncryption.rawValue || ns.code == CBATTError.insufficientAuthentication.rawValue)
            if authError {
                fail("Appairage refusé par le bracelet. Ferme l'app WHOOP officielle, oublie le bracelet dans Réglages › Bluetooth, mets le bracelet en mode appairage (tape dessus jusqu'aux LED bleues) puis réessaie.")
            } else {
                fail("Abonnement impossible : \(error.localizedDescription)")
            }
            return
        }
        if characteristic.uuid == CBUUID(string: GattProfile.heartRateMeasurement) && chars["cmdTo"] == nil { return }
        subscribeNext()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        if characteristic.uuid == CBUUID(string: GattProfile.heartRateMeasurement) {
            if !liveEnabledOnStrap { handleStandardHR(data) }
            return
        }
        if characteristic.uuid == CBUUID(string: GattProfile.batteryLevel), let b = data.first {
            publish { if $0.battery == nil { $0.battery = Double(b) } }
            return
        }
        guard let r = reassemblers[characteristic.uuid] else { return }
        for f in r.feed([UInt8](data)) { handle(f) }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { logLine("Écriture refusée : \(error.localizedDescription)") }
    }
}
