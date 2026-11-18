// Kakashi: guarda la webcam. Gesto: due pugni chiusi al centro, poi apri le due mani insieme.
// All'apertura parte lo "sbuffo" ninja: una nuvola di fumo ti copre, nel video sparisci davvero
// e subito dopo Kakashi ti butta fuori dalla call (chiude la scheda/app di Meet, Discord, Zoom, Teams…).
// Il video elaborato esce in una finestra ("Kakashi Video") che OBS cattura come OBS Virtual Camera.
import Cocoa
import AVFoundation
import Vision
import CoreImage

typealias J = VNHumanHandPoseObservation.JointName
typealias Hand = [J: CGPoint]

// MARK: - Parametri (tarabili con variabili d'ambiente KAKASHI_*)

let env = ProcessInfo.processInfo.environment
func envD(_ k: String, _ d: Double) -> Double { env[k].flatMap { Double($0) } ?? d }
let FIST_MAX = envD("KAKASHI_FIST_MAX", 1.45)     // pugno: ogni dito sotto questo rapporto dist(polso,punta)/dist(polso,nocca)
let OPEN_MIN = envD("KAKASHI_OPEN_MIN", 1.6)      // mano aperta: ogni dito sopra questo rapporto
let FIST_HOLD = envD("KAKASHI_FIST_HOLD", 0.4)    // secondi di pugni fermi per "armarsi"
let FIST_GRACE = 0.3                              // vuoti di riconoscimento tollerati mentre si armano
let WINDOW = envD("KAKASHI_WINDOW", 1.2)          // secondi concessi per aprire le mani dopo l'ultimo pugno
let CENTER = envD("KAKASHI_CENTER", 0.2)          // quanto può scostarsi dal centro dell'inquadratura (frazione di larghezza)
let APART_FIST = envD("KAKASHI_APART", 3.5)       // distanza massima tra i polsi, in palmi, a pugni chiusi
let APART_OPEN = 6.0                              // idem a mani aperte
let SMOKE_HOLD = envD("KAKASHI_SMOKE_HOLD", 0.5)   // secondi con due dita alla bocca per far partire "Real Stoner"
let SMOKE_DIST = envD("KAKASHI_SMOKE_DIST", 0.9)   // distanza massima punte delle dita-bocca, in LARGHEZZE DI BOCCA
let BROW = envD("KAKASHI_BROW", 0.88)             // sopracciglio "abbassato": altezza sotto questa frazione di quella a riposo
let TILT = envD("KAKASHI_TILT", 5.0) * .pi / 180  // testa "storta": gradi di scarto dall'inclinazione a riposo
let POSE_TOL = envD("KAKASHI_POSE_TOL", 0.10)      // quanto può cambiare la posa della testa (su/giù/di lato) rispetto al riposo, in frazione
let BROW_HOLD = envD("KAKASHI_BROW_HOLD", 0.35)   // secondi di espressione per far partire lo zoom
let ZOOM = envD("KAKASHI_ZOOM", 2.5)              // ingrandimento dello zoom sul volto
let DRINK_NEAR = envD("KAKASHI_DRINK", 1.0)           // pugno "vicino alla bocca": distanza massima, in dimensioni di viso (bevendo sta a 0.45-0.8)
let COOLDOWN = envD("KAKASHI_COOLDOWN", 8.0)      // pausa dopo uno scatto
let FLIP_TEXT = env["KAKASHI_FLIP_TEXT"] == "1"       // rovescia le scritte nel video (per leggerle dritte nella propria anteprima specchiata)
let FX = env["KAKASHI_FX"] != "0"                 // KAKASHI_FX=0: niente fumo, ti disconnette subito
let CONF = Float(envD("KAKASHI_CONF", 0.1))       // confidenza minima di ogni articolazione
let DEBUG = env["KAKASHI_DEBUG"] != nil           // stampa le misure a ogni fotogramma
let DRY = env["KAKASHI_DRY"] != nil               // non chiude niente, dice solo cosa chiuderebbe

func log(_ s: String) { print(s); fflush(stdout) }

// MARK: - Riconoscimento del gesto (puro, senza camera: provabile con "selftest")

func dist(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(Double(a.x - b.x), Double(a.y - b.y)) }

struct HandInfo { let wrist: CGPoint; let palm: Double; let minR: Double; let maxR: Double }

func handInfo(_ h: Hand) -> HandInfo? {
    guard let w = h[.wrist] else { return nil }
    let pairs: [(J, J)] = [(.indexMCP, .indexTip), (.middleMCP, .middleTip), (.ringMCP, .ringTip), (.littleMCP, .littleTip)]
    var rs: [Double] = [], mcp: [Double] = []
    for (m, t) in pairs {
        guard let mp = h[m] else { continue }
        let dm = max(dist(w, mp), 0.001)
        mcp.append(dm)
        if let tp = h[t] { rs.append(dist(w, tp) / dm) }
    }
    guard rs.count >= 3, !mcp.isEmpty else { return nil }
    let palm = mcp.reduce(0, +) / Double(mcp.count)
    guard palm > 0.001, let lo = rs.min(), let hi = rs.max() else { return nil }
    return HandInfo(wrist: w, palm: palm, minR: lo, maxR: hi)
}

enum Pose { case fists, open, none }

/// Coordinate in unità isotrope (x già moltiplicata per il rapporto d'aspetto, che serve per il centro).
func classify(_ hands: [Hand], aspect: Double) -> (pose: Pose, why: String) {
    let ms = hands.compactMap(handInfo)
    guard ms.count == 2 else { return (.none, "mani complete: \(ms.count)/2") }
    let a = ms[0], b = ms[1]
    let palm = (a.palm + b.palm) / 2
    let apart = dist(a.wrist, b.wrist) / palm
    let cx = Double(a.wrist.x + b.wrist.x) / 2 / aspect
    let off = abs(cx - 0.5)
    let info = String(format: "dita max %.2f/%.2f min %.2f/%.2f  distanza %.1f palmi  scarto dal centro %.2f", a.maxR, b.maxR, a.minR, b.minR, apart, off)
    if ms.allSatisfy({ $0.maxR <= FIST_MAX }) {
        if off > CENTER { return (.none, "pugni fuori centro  " + info) }
        if apart > APART_FIST { return (.none, "pugni troppo distanti  " + info) }
        return (.fists, "PUGNI  " + info)
    }
    if ms.allSatisfy({ $0.minR >= OPEN_MIN }) {
        if off > CENTER * 1.6 { return (.none, "mani aperte fuori centro  " + info) }
        if apart > APART_OPEN { return (.none, "mani aperte troppo distanti  " + info) }
        return (.open, "APERTE  " + info)
    }
    return (.none, "ne' pugni ne' mani aperte  " + info)
}

enum Phase { case idle, arming(Double), armed(Double) }

/// Sequenza: pugni fermi (si arma) → entro WINDOW dall'ultimo pugno le due mani si aprono insieme → scatta.
struct SeqTracker {
    var fistSince: TimeInterval?
    var lastFist: TimeInterval = -1000
    var armed = false
    var openFrames = 0
    mutating func reset() { fistSince = nil; armed = false; openFrames = 0 }
    mutating func update(_ pose: Pose, now: TimeInterval) -> (phase: Phase, fire: Bool) {
        if pose == .fists {
            if fistSince == nil { fistSince = now }
            lastFist = now; openFrames = 0
            if !armed, let s = fistSince, now - s >= FIST_HOLD { armed = true }
        } else {
            if !armed, fistSince != nil, now - lastFist > FIST_GRACE { fistSince = nil }
            if armed {
                if pose == .open {
                    openFrames += 1
                    if openFrames >= 2 { reset(); return (.idle, true) }
                } else { openFrames = 0 }
                if now - lastFist > WINDOW { reset() }
            }
        }
        if armed { return (.armed(max(0, 1 - max(0, now - lastFist) / WINDOW)), false) }
        if let s = fistSince { return (.arming(min(1, (now - s) / FIST_HOLD)), false) }
        return (.idle, false)
    }
}

// MARK: - Segnale "Real Stoner": due dita alla bocca, come per fumare

/// Posizione di occhi e bocca (coordinate normalizzate 0..1, origine in basso a sinistra; larghezze normalizzate).
struct FaceGeom {
    var eyeL: CGPoint; var eyeR: CGPoint; var mouth: CGPoint; var mouthW: Double; var faceW: Double
    var browL = CGPoint.zero, browR = CGPoint.zero      // sopracciglia (vuote se Vision non le dà)
    var center = CGPoint(x: 0.5, y: 0.5)                 // centro del volto
}

func faceGeom(_ obs: VNFaceObservation) -> FaceGeom? {
    guard let lm = obs.landmarks, let le = lm.leftEye, let re = lm.rightEye, let lips = lm.outerLips else { return nil }
    let bb = obs.boundingBox
    func toImg(_ pts: [CGPoint]) -> [CGPoint] { pts.map { CGPoint(x: bb.minX + $0.x * bb.width, y: bb.minY + $0.y * bb.height) } }
    func mean(_ p: [CGPoint]) -> CGPoint { CGPoint(x: p.map { $0.x }.reduce(0, +) / CGFloat(p.count), y: p.map { $0.y }.reduce(0, +) / CGFloat(p.count)) }
    let l = toImg(le.normalizedPoints), r = toImg(re.normalizedPoints), m = toImg(lips.normalizedPoints)
    guard !l.isEmpty, !r.isEmpty, !m.isEmpty, let lo = m.map({ $0.x }).min(), let hi = m.map({ $0.x }).max() else { return nil }
    var g = FaceGeom(eyeL: mean(l), eyeR: mean(r), mouth: mean(m), mouthW: Double(hi - lo), faceW: Double(bb.width))
    if let lb = lm.leftEyebrow, let rb = lm.rightEyebrow {
        let a = toImg(lb.normalizedPoints), b = toImg(rb.normalizedPoints)
        if !a.isEmpty, !b.isEmpty { g.browL = mean(a); g.browR = mean(b) }
    }
    g.center = CGPoint(x: bb.midX, y: bb.midY)
    return g
}

/// Indice e medio estesi e vicini, le altre dita chiuse, e le punte delle due dita VICINO ALLA BOCCA (misurate in larghezze di bocca).
/// `side`: +1 se la mano sta a destra della bocca nell'immagine, -1 se a sinistra (da lì esce il joint).
func smokeGesture(_ hands: [Hand], face: FaceGeom?, aspect: Double) -> (ok: Bool, why: String, side: Double) {
    guard let f = face else { return (false, "fumo: nessun volto", 1) }
    let mouth = CGPoint(x: f.mouth.x * CGFloat(aspect), y: f.mouth.y)
    let mouthW = max(f.mouthW * aspect, 0.001)
    var last = "fumo: nessuna mano"
    for h in hands {
        let iso = h.mapValues { CGPoint(x: $0.x * CGFloat(aspect), y: $0.y) }
        guard let w = iso[.wrist], let im = iso[.indexMCP], let it = iso[.indexTip],
              let mm = iso[.middleMCP], let mt = iso[.middleTip] else { last = "fumo: mano incompleta"; continue }
        let palm = dist(w, mm)
        guard palm > 0.001 else { continue }
        func r(_ t: J, _ m: J) -> Double { guard let tp = iso[t], let mp = iso[m] else { return 0 }; return dist(w, tp) / max(dist(w, mp), 0.001) }
        let ri = dist(w, it) / max(dist(w, im), 0.001), rm = dist(w, mt) / max(dist(w, mm), 0.001)
        let rr = r(.ringTip, .ringMCP), rl = r(.littleTip, .littleMCP)   // dato mancante = dito chiuso
        let together = dist(it, mt) / palm
        let mid = CGPoint(x: (it.x + mt.x) / 2, y: (it.y + mt.y) / 2)
        let dm = dist(mid, mouth) / mouthW
        let dMax = max(dist(it, mouth), dist(mt, mouth)) / mouthW
        let side: Double = w.x >= mouth.x ? 1 : -1
        let info = String(format: "indice %.2f medio %.2f anulare %.2f mignolo %.2f  dita unite %.2f  dalla bocca %.2f larghezze (soglia %.2f)", ri, rm, rr, rl, together, dm, SMOKE_DIST)
        if ri < 1.3 || rm < 1.3 { last = "fumo: indice e medio non estesi  " + info; continue }
        if rr > FIST_MAX || rl > FIST_MAX { last = "fumo: anulare/mignolo aperti  " + info; continue }
        if together > 1.0 { last = "fumo: dita separate  " + info; continue }
        if dm > SMOKE_DIST || dMax > SMOKE_DIST * 1.5 { last = "fumo: troppo lontano dalla bocca  " + info; continue }
        return (true, "FUMO  " + info, side)
    }
    return (false, last, 1)
}


// MARK: - Terzo segnale: sopracciglio abbassato + testa storta → zoom sul volto

/// Come sei a riposo: mediana degli ultimi ~30 s di altezza dei due sopraccigli sopra gli occhi (in distanze tra gli occhi) e di
/// inclinazione della testa. La mediana ignora il gesto (è una minoranza dei campioni) e si riallinea da sola se parte sbagliata.
struct BrowBaseline {
    var gl: [Double] = [], gr: [Double] = [], roll: [Double] = [], pitch: [Double] = [], yaw: [Double] = []
    var ready: Bool { gl.count >= 20 }
    mutating func add(_ l: Double, _ r: Double, _ rl: Double, _ p: Double, _ y: Double) {
        gl.append(l); gr.append(r); roll.append(rl); pitch.append(p); yaw.append(y)
        if gl.count > 300 { gl.removeFirst(); gr.removeFirst(); roll.removeFirst(); pitch.removeFirst(); yaw.removeFirst() }
    }
    static func median(_ a: [Double]) -> Double { a.isEmpty ? 0 : a.sorted()[a.count / 2] }
    var medL: Double { Self.median(gl) }
    var medR: Double { Self.median(gr) }
    var medRoll: Double { Self.median(roll) }
    var medPitch: Double { Self.median(pitch) }
    var medYaw: Double { Self.median(yaw) }
}

func browGesture(_ f: FaceGeom, aspect: Double, base: inout BrowBaseline) -> (ok: Bool, why: String) {
    guard f.browL != .zero, f.browR != .zero else { return (false, "zoom: sopracciglia non rilevate") }
    func iso(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * CGFloat(aspect), y: p.y) }
    var eL = iso(f.eyeL), eR = iso(f.eyeR), bL = iso(f.browL), bR = iso(f.browR)
    if eL.x > eR.x { swap(&eL, &eR) }
    if bL.x > bR.x { swap(&bL, &bR) }
    let ex = Double(eR.x - eL.x), ey = Double(eR.y - eL.y), n = hypot(ex, ey)
    guard n > 1e-4 else { return (false, "zoom: occhi non validi") }
    let ux = -ey / n, uy = ex / n                         // "su" del volto, perpendicolare alla linea degli occhi
    func gap(_ b: CGPoint, _ e: CGPoint) -> Double { (Double(b.x - e.x) * ux + Double(b.y - e.y) * uy) / n }
    let gl = gap(bL, eL), gr = gap(bR, eR), roll = atan2(ey, ex)
    // posa della testa: guardando su/giù il viso si accorcia (distanza occhi-bocca rispetto agli occhi), di lato si restringe
    // (larghezza tra gli occhi rispetto al viso). Sono proporzioni, quindi non dipendono da quanto sei vicino alla camera.
    let eyeMid = CGPoint(x: (eL.x + eR.x) / 2, y: (eL.y + eR.y) / 2)
    let pitchR = dist(eyeMid, iso(f.mouth)) / n
    let yawR = n / max(f.faceW * aspect, 1e-4)
    defer { base.add(gl, gr, roll, pitchR, yawR) }
    guard base.ready else { return (false, "zoom: sto imparando come sei a riposo (\(base.gl.count)/20)") }
    let rl = gl / max(base.medL, 1e-3), rr = gr / max(base.medR, 1e-3)
    let tilt = abs(roll - base.medRoll)
    // abbassato = uno dei due sopraccigli sotto la soglia, oppure uno nettamente più basso dell'altro (rispetto a come sei a riposo)
    let poseOff = max(abs(pitchR / max(base.medPitch, 1e-3) - 1), abs(yawR / max(base.medYaw, 1e-3) - 1))
    let lowered = min(rl, rr) <= BROW || abs(rl - rr) >= 0.13, tilted = tilt >= TILT
    let info = String(format: "sopracciglio sx %.2f dx %.2f (soglia %.2f)  testa storta %.1f° (soglia %.1f°)  posa cambiata %.0f%% (max %.0f%%)", rl, rr, BROW, tilt * 180 / .pi, TILT * 180 / .pi, poseOff * 100, POSE_TOL * 100)
    if poseOff > POSE_TOL { return (false, "zoom: stai guardando su/giù/di lato (non è l'espressione)  " + info) }
    if !lowered { return (false, "zoom: sopracciglio non abbassato  " + info) }
    if !tilted { return (false, "zoom: testa non storta  " + info) }
    return (true, "ZOOM  " + info)
}

/// Scatta UNA volta dopo `hold` secondi di gesto, ma solo se prima eri "a riposo" per quasi un secondo: uno stato
/// sbagliato e continuo (gesto sempre vero) non può né partire né ripetersi. Dopo uno scatto serve di nuovo il riposo.
struct EdgeTracker {
    var hold: Double
    var armed = false
    var calmSince: TimeInterval?
    var start: TimeInterval?
    var lastGood: TimeInterval = 0
    mutating func reset() { start = nil }
    mutating func update(ok: Bool, now: TimeInterval) -> Bool {
        if ok { calmSince = nil } else {
            if calmSince == nil { calmSince = now }
            if !armed, now - (calmSince ?? now) >= 0.8 { armed = true }
        }
        guard armed else { start = nil; return false }
        if ok { if start == nil { start = now }; lastGood = now }
        else if start != nil && now - lastGood > 0.25 { start = nil }
        guard let s = start, now - s >= hold else { return false }
        start = nil; armed = false; calmSince = nil
        return true
    }
}

// MARK: - Occhiali (trasformazione) e caffè (contatore): macchine a stati

/// Conteggio dei caffè, salvato per giorno (si azzera a mezzanotte).
enum CoffeeStore {
    static let path = NSString(string: "~/.local/state/kakashi-coffee.json").expandingTildeInPath
    static func today() -> String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date()) }
    static func load() -> Int {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              j["day"] as? String == today(), let n = j["count"] as? Int else { return 0 }
        return n
    }
    static func save(_ n: Int) {
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        if let d = try? JSONSerialization.data(withJSONObject: ["day": today(), "count": n]) { try? d.write(to: URL(fileURLWithPath: path)) }
    }
}

/// Gesti letti dalle mani rispetto al volto: entrambe le mani vicino agli occhi, e distanza del pugno più vicino dalla bocca.
struct HandHints { var bothEyes = false, fist: Double? = nil }

// MARK: - Gesti di "bere" e "occhiali": movimenti reali

/// Rapporto dist(polso,punta)/dist(polso,nocca) delle 4 dita (dato mancante = dito chiuso).
func fingerRatios(_ h: Hand) -> (i: Double, m: Double, r: Double, l: Double)? {
    guard let w = h[.wrist], let mm = h[.middleMCP], dist(w, mm) > 0.001 else { return nil }
    func r(_ t: J, _ m: J) -> Double { guard let tp = h[t], let mp = h[m] else { return 0 }; return dist(w, tp) / max(dist(w, mp), 0.001) }
    return (r(.indexTip, .indexMCP), r(.middleTip, .middleMCP), r(.ringTip, .ringMCP), r(.littleTip, .littleMCP))
}

/// Mano "a pugno" (come quando si regge una tazza): medio, anulare e mignolo chiusi, l'indice chiuso o appena disteso.
func fistLike(_ h: Hand) -> Bool {
    guard let f = fingerRatios(h) else { return false }
    return f.m <= 1.55 && f.r <= 1.55 && f.l <= 1.55 && f.i <= 2.0
}

func handCenter(_ h: Hand, aspect: Double) -> CGPoint? {
    guard !h.isEmpty else { return nil }
    let n = Double(h.count)
    return CGPoint(x: h.values.map { Double($0.x) }.reduce(0, +) / n * aspect, y: h.values.map { Double($0.y) }.reduce(0, +) / n)
}

/// Distanza dalla bocca (in dimensioni di viso) della mano a pugno più vicina; nil se non c'è nessuna mano a pugno.
func fistToMouth(_ hands: [Hand], face f: FaceGeom, aspect: Double) -> Double? {
    let mouth = CGPoint(x: f.mouth.x * CGFloat(aspect), y: f.mouth.y), fs = max(f.faceW * aspect, 0.001)
    let eyeY = Double(f.eyeL.y + f.eyeR.y) / 2
    // solo pugni sotto la linea degli occhi: fronte, capelli e testa non sono bere
    let ds = hands.filter { fistLike($0) }.compactMap { handCenter($0, aspect: aspect) }.filter { Double($0.y) < eyeY - 0.1 * f.faceW * aspect }.map { dist($0, mouth) / fs }
    return ds.min()
}

/// Entrambe le mani (a "C") vicino agli occhi, una per lato.
func bothHandsNearEyes(_ hands: [Hand], face f: FaceGeom, aspect: Double) -> Bool {
    let eyeMid = CGPoint(x: (f.eyeL.x + f.eyeR.x) / 2 * CGFloat(aspect), y: (f.eyeL.y + f.eyeR.y) / 2), fs = max(f.faceW * aspect, 0.001)
    let near = hands.compactMap { handCenter($0, aspect: aspect) }.filter { dist($0, eyeMid) <= 1.15 * fs }
    guard near.count >= 2 else { return false }
    let xs = near.map { Double($0.x) }
    return (xs.max() ?? 0) - (xs.min() ?? 0) >= 0.5 * fs        // una a sinistra e una a destra degli occhi
}

/// Bere: un pugno che SI AVVICINA alla bocca e ci resta almeno 0,35 s. Un solo scatto per sorso.
///  • "avvicinarsi" = prima dell'episodio la mano a pugno era più lontana (≥ vicino + 0,4) oppure assente per almeno 0,6 s;
///    una volta riconosciuto resta valido per tutto l'episodio (non lampeggia);
///  • l'episodio dura finché il pugno è vicino, con 0,6 s di tolleranza se la mano sparisce un attimo (la tazza la copre);
///  • una mano ferma vicino alla bocca da sempre (per esempio mentre pensi) non conta;
///  • al massimo un caffè ogni 8 s (un sorso solo, ma si può riprovare subito).
struct DrinkTracker {
    var hist: [(t: TimeInterval, d: Double?)] = []
    var nearSince: TimeInterval?
    var lastSeenNear: TimeInterval = 0
    var approach = false
    var fired = false
    var lastFire: TimeInterval = -1000
    mutating func update(d: Double?, now: TimeInterval) -> (fire: Bool, why: String) {
        hist.append((now, d)); hist.removeAll { now - $0.t > 3.0 }
        if (d ?? 9) <= DRINK_NEAR {
            if nearSince == nil {
                nearSince = now; fired = false
                let before = hist.filter { $0.t < now && now - $0.t <= 2.0 }
                let farBefore = before.contains { ($0.d ?? 0) >= DRINK_NEAR + 0.4 }
                let absent = before.filter { $0.d == nil }.count >= 6
                approach = farBefore || absent
            }
            lastSeenNear = now
        } else if nearSince != nil, now - lastSeenNear > 0.6 {
            nearSince = nil; approach = false; fired = false
        }
        let held = nearSince.map { lastSeenNear - $0 } ?? 0        // solo il tempo in cui il pugno è stato davvero vicino
        let info = d == nil ? "bere: nessun pugno" : String(format: "bere: pugno a %.2f volti dalla bocca (vicino ≤ %.2f)  tenuto %.1f s  avvicinamento: %@", d ?? 0, DRINK_NEAR, held, approach ? "sì" : "no")
        if nearSince != nil, approach, !fired, held >= 0.35, now - lastFire > 8 { fired = true; lastFire = now; return (true, info) }
        return (false, info)
    }
}

// MARK: - Autotest (nessuna camera)

func synthHand(x0: Double, fingers: Bool) -> Hand {
    var h: Hand = [.wrist: CGPoint(x: x0, y: 0)]
    func finger(_ mcp: J, _ tip: J, _ x: Double, _ y: Double) {
        h[mcp] = CGPoint(x: x, y: y)
        h[tip] = CGPoint(x: x, y: fingers ? y + 0.2 : 0.1)
    }
    finger(.indexMCP, .indexTip, x0 - 0.03, 0.18)
    finger(.middleMCP, .middleTip, x0, 0.20)
    finger(.ringMCP, .ringTip, x0 + 0.03, 0.19)
    finger(.littleMCP, .littleTip, x0 + 0.06, 0.17)
    return h
}

func selfTest() -> Int32 {
    var fails = 0
    func check(_ name: String, _ got: Bool) {
        if !got { fails += 1 }
        print("\(got ? "OK  " : "FAIL") \(name)")
    }
    func pose(_ hands: [Hand]) -> Pose { classify(hands, aspect: 1).pose }
    let fists = [synthHand(x0: 0.40, fingers: false), synthHand(x0: 0.65, fingers: false)]
    let open = [synthHand(x0: 0.40, fingers: true), synthHand(x0: 0.65, fingers: true)]
    check("due pugni al centro → pugni", pose(fists) == .fists)
    check("due mani aperte al centro → aperte", pose(open) == .open)
    check("una mano sola → niente", pose([fists[0]]) == .none)
    check("pugni troppo a sinistra → niente", pose([synthHand(x0: 0.05, fingers: false), synthHand(x0: 0.30, fingers: false)]) == .none)
    check("pugni lontani tra loro → niente", pose([synthHand(x0: 0.10, fingers: false), synthHand(x0: 0.95, fingers: false)]) == .none)
    check("un pugno e una mano aperta → niente", pose([fists[0], open[1]]) == .none)

    func run(_ steps: [(Double, Pose)]) -> Bool {   // true se almeno una volta scatta
        var t = SeqTracker(), fired = false
        for (now, p) in steps { if t.update(p, now: now).fire { fired = true } }
        return fired
    }
    let tick = stride(from: 0.0, through: 0.9, by: 0.1).map { ($0, Pose.fists) }
    check("pugni 1 s poi apri → scatta", run(tick + [(1.0, .open), (1.1, .open)]))
    check("pugni, un attimo di transizione, poi apri → scatta", run(tick + [(1.0, .none), (1.2, .none), (1.3, .open), (1.4, .open)]))
    check("apri senza pugni prima → niente", !run([(0.0, .open), (0.1, .open), (0.2, .open), (0.3, .open)]))
    check("pugni solo 0,2 s poi apri → niente", !run([(0.0, .fists), (0.1, .fists), (0.2, .fists), (0.3, .open), (0.4, .open)]))
    check("pugni poi 2 s di pausa poi apri → niente", !run(tick + [(3.0, .open), (3.1, .open)]))
    check("una sola rilevazione di mani aperte → niente", !run(tick + [(1.0, .open), (1.1, .none)]))

    // due dita alla bocca
    func smokeHand(x0: Double, tipsX: Double = 0.50, ring: Bool = false, middle: Bool = true) -> Hand {
        var h = synthHand(x0: x0, fingers: false)
        h[.indexTip] = CGPoint(x: tipsX - 0.01, y: 0.47)
        if middle { h[.middleTip] = CGPoint(x: tipsX + 0.01, y: 0.49) }
        if ring { h[.ringTip] = CGPoint(x: tipsX + 0.03, y: 0.48) }
        return h
    }
    let face = FaceGeom(eyeL: CGPoint(x: 0.43, y: 0.70), eyeR: CGPoint(x: 0.57, y: 0.70), mouth: CGPoint(x: 0.50, y: 0.50), mouthW: 0.10, faceW: 0.30)
    check("due dita alla bocca → fumo", smokeGesture([smokeHand(x0: 0.50)], face: face, aspect: 1).ok)
    check("senza volto → niente", !smokeGesture([smokeHand(x0: 0.50)], face: nil, aspect: 1).ok)
    check("solo l'indice → niente", !smokeGesture([smokeHand(x0: 0.50, middle: false)], face: face, aspect: 1).ok)
    check("tre dita estese → niente", !smokeGesture([smokeHand(x0: 0.50, ring: true)], face: face, aspect: 1).ok)
    check("dita lontane dalla bocca → niente", !smokeGesture([smokeHand(x0: 0.50)], face: FaceGeom(eyeL: face.eyeL, eyeR: face.eyeR, mouth: CGPoint(x: 0.50, y: 0.05), mouthW: 0.1, faceW: 0.30), aspect: 1).ok)
    check("dita a un viso di distanza dalla bocca → niente", !smokeGesture([smokeHand(x0: 0.50, tipsX: 0.80)], face: face, aspect: 1).ok)
    check("dita ai lati dello schermo → niente", !smokeGesture([smokeHand(x0: 0.10, tipsX: 0.10)], face: face, aspect: 1).ok)
    check("mano a destra della bocca → lato +1", smokeGesture([smokeHand(x0: 0.62, tipsX: 0.52)], face: face, aspect: 1).side == 1)
    check("mano a sinistra della bocca → lato −1", smokeGesture([smokeHand(x0: 0.38, tipsX: 0.48)], face: face, aspect: 1).side == -1)
    func edge(_ hold: Double, _ steps: [(Double, Bool)]) -> Int {   // quante volte scatta
        var t = EdgeTracker(hold: hold), n = 0
        for (now, ok) in steps { if t.update(ok: ok, now: now) { n += 1 } }
        return n
    }
    let calm = (0...10).map { (Double($0) * 0.1, false) }                       // 1 s a riposo
    func on(_ from: Double, _ to: Double) -> [(Double, Bool)] { stride(from: from, through: to, by: 0.1).map { ($0, true) } }
    check("a riposo e poi 0,5 s di gesto → scatta una volta", edge(0.5, calm + on(1.1, 1.8)) == 1)
    check("solo 0,2 s di gesto → niente", edge(0.5, calm + on(1.1, 1.3)) == 0)
    check("gesto già vero dall'inizio → niente", edge(0.5, on(0.0, 3.0)) == 0)
    check("gesto sempre vero dopo lo scatto → non ripete", edge(0.5, calm + on(1.1, 8.0)) == 1)
    check("rilassarsi e rifare il gesto → ripete", edge(0.5, calm + on(1.1, 1.8) + (19...30).map { (Double($0) * 0.1, false) } + on(3.1, 3.8)) == 2)
    // sopracciglio abbassato + testa storta
    func mkFace(gap: Double, tilt: Double, mouthY: Double = 0.40, faceW: Double = 0.3) -> FaceGeom {
        func rot(_ p: CGPoint) -> CGPoint {
            let dx = Double(p.x) - 0.5, dy = Double(p.y) - 0.6
            return CGPoint(x: 0.5 + dx * cos(tilt) - dy * sin(tilt), y: 0.6 + dx * sin(tilt) + dy * cos(tilt))
        }
        let up = 0.14 * gap
        var f = FaceGeom(eyeL: rot(CGPoint(x: 0.43, y: 0.60)), eyeR: rot(CGPoint(x: 0.57, y: 0.60)), mouth: CGPoint(x: 0.5, y: mouthY), mouthW: 0.1, faceW: faceW)
        f.browL = rot(CGPoint(x: 0.43, y: 0.60 + up)); f.browR = rot(CGPoint(x: 0.57, y: 0.60 + up))
        return f
    }
    var base = BrowBaseline()
    for _ in 0..<20 { _ = browGesture(mkFace(gap: 0.35, tilt: 0), aspect: 1, base: &base) }
    check("a riposo → niente", !browGesture(mkFace(gap: 0.35, tilt: 0), aspect: 1, base: &base).ok)
    check("sopracciglio abbassato + testa storta → zoom", browGesture(mkFace(gap: 0.25, tilt: 0.15), aspect: 1, base: &base).ok)
    check("solo sopracciglio abbassato → niente", !browGesture(mkFace(gap: 0.25, tilt: 0), aspect: 1, base: &base).ok)
    check("solo testa storta → niente", !browGesture(mkFace(gap: 0.35, tilt: 0.15), aspect: 1, base: &base).ok)
    check("guardando in alto (viso accorciato) → niente", !browGesture(mkFace(gap: 0.25, tilt: 0.15, mouthY: 0.47), aspect: 1, base: &base).ok)
    check("guardando di lato (viso più stretto) → niente", !browGesture(mkFace(gap: 0.25, tilt: 0.15, faceW: 0.42), aspect: 1, base: &base).ok)
    check("sopracciglio più basso solo da un lato → zoom", { var f = mkFace(gap: 0.35, tilt: 0.15); f.browL.y -= 0.02; return browGesture(f, aspect: 1, base: &base).ok }())
    // linea di base partita sbagliata (20 campioni "abbassati e storti"): deve riallinearsi da sola col riposo vero
    var bad = BrowBaseline()
    for _ in 0..<20 { _ = browGesture(mkFace(gap: 0.25, tilt: 0.15), aspect: 1, base: &bad) }
    check("base sbagliata: all'inizio sembra a riposo", !browGesture(mkFace(gap: 0.25, tilt: 0.15), aspect: 1, base: &bad).ok)
    for _ in 0..<60 { _ = browGesture(mkFace(gap: 0.35, tilt: 0), aspect: 1, base: &bad) }
    check("dopo un po' di riposo vero il gesto scatta", browGesture(mkFace(gap: 0.25, tilt: 0.15), aspect: 1, base: &bad).ok)
    // bere: pugno che si avvicina alla bocca
    func fistHand(cx: Double, cy: Double) -> Hand {       // mano a pugno con il centro in (cx, cy)
        var h = synthHand(x0: cx, fingers: false)
        let dy = cy - 0.1
        for (k, v) in h { h[k] = CGPoint(x: v.x, y: v.y + dy) }
        return h
    }
    let ff = FaceGeom(eyeL: CGPoint(x: 0.43, y: 0.70), eyeR: CGPoint(x: 0.57, y: 0.70), mouth: CGPoint(x: 0.50, y: 0.50), mouthW: 0.10, faceW: 0.30)
    check("pugno vicino alla bocca → distanza piccola", (fistToMouth([fistHand(cx: 0.50, cy: 0.52)], face: ff, aspect: 1) ?? 9) < 0.7)
    check("mano aperta vicino alla bocca → non è un pugno", fistToMouth([synthHand(x0: 0.50, fingers: true)], face: ff, aspect: 1) == nil)
    func drinks(_ seq: [(Double, Double?)]) -> Int {
        var d = DrinkTracker(), n = 0
        for (t, x) in seq { if d.update(d: x, now: t).fire { n += 1 } }
        return n
    }
    func series(_ from: Double, _ vals: [Double?]) -> [(Double, Double?)] { vals.enumerated().map { (from + Double($0.offset) * 0.1, $0.element) } }
    let far15 = series(0, [Double?](repeating: 1.6, count: 10))
    let closing = series(1.0, [1.4, 1.2, 1.0, 0.8, 0.6])
    let staying = series(1.5, [Double?](repeating: 0.55, count: 12))
    check("pugno che si avvicina e resta alla bocca → un caffè", drinks(far15 + closing + staying) == 1)
    check("un solo scatto per sorso, anche se resta a lungo", drinks(far15 + closing + series(1.5, [Double?](repeating: 0.55, count: 80))) == 1)
    check("distanza che oscilla 0,5-0,9 durante il sorso → un solo caffè", drinks(far15 + closing + series(1.5, [0.55, 0.9, 0.6, 0.85, 0.55, 0.8, 0.6, 0.9, 0.55, 0.7, 0.6, 0.55])) == 1)
    check("la mano sparisce un attimo (0,3 s) durante il sorso → un solo caffè", drinks(far15 + closing + series(1.5, [0.55, 0.55, nil, nil, nil, 0.55, 0.6, 0.6, 0.6, 0.6])) == 1)
    check("mano ferma vicino alla bocca da sempre (mentre pensi) → niente", drinks(series(0, [Double?](repeating: 0.5, count: 60))) == 0)
    check("mano vicino alla bocca che lampeggia (sparisce 0,2 s ogni tanto) → niente", drinks(series(0, [0.5, 0.5, 0.5, nil, nil, 0.5, 0.5, 0.5, nil, nil, 0.5, 0.5, 0.5, 0.5, 0.5, nil, nil, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5])) == 0)
    check("il pugno compare vicino alla bocca (prima non c'era) e resta → un caffè", drinks(series(0, [Double?](repeating: nil, count: 10)) + series(1.0, [Double?](repeating: 0.55, count: 12))) == 1)
    check("pugno vicino alla bocca per soli 0,2 s → niente", drinks(far15 + closing.dropLast(2) + series(1.3, [0.6, 0.6, 1.6, 1.6, 1.6])) == 0)
    check("due sorsi a 10 s di distanza → due caffè", drinks(far15 + closing + staying + series(4.0, [Double?](repeating: 1.6, count: 80)) + series(12.0, [1.4, 1.2, 1.0, 0.8, 0.6]) + series(12.5, [Double?](repeating: 0.55, count: 12))) == 2)
    check("pugno sopra la linea degli occhi (capelli, fronte) → non è bere", fistToMouth([fistHand(cx: 0.50, cy: 0.74)], face: ff, aspect: 1) == nil)
    // occhiali: entrambe le mani vicino agli occhi, una per lato
    func ch(_ cx: Double, _ cy: Double) -> Hand { fistHand(cx: cx, cy: cy) }
    check("due mani vicino agli occhi, una per lato → sì", bothHandsNearEyes([ch(0.36, 0.70), ch(0.64, 0.70)], face: ff, aspect: 1))
    check("una sola mano vicino agli occhi → no", !bothHandsNearEyes([ch(0.36, 0.70)], face: ff, aspect: 1))
    check("due mani lontane dagli occhi → no", !bothHandsNearEyes([ch(0.10, 0.20), ch(0.90, 0.20)], face: ff, aspect: 1))
    check("due mani dallo stesso lato → no", !bothHandsNearEyes([ch(0.34, 0.70), ch(0.36, 0.72)], face: ff, aspect: 1))
    print(fails == 0 ? "Tutto a posto." : "\(fails) controlli falliti.")
    return fails == 0 ? 0 : 1
}

// MARK: - Uscire dalla call

let browsers: [(id: String, name: String)] = [
    ("com.google.Chrome", "Chrome"), ("com.brave.Browser", "Brave"), ("com.microsoft.edgemac", "Edge"),
    ("company.thebrowser.Browser", "Arc"), ("com.vivaldi.Vivaldi", "Vivaldi"),
    ("com.operasoftware.Opera", "Opera"), ("com.apple.Safari", "Safari"),
]
// Schede che sono una call (regex sull'URL). Aggiungine con ~/.config/kakashi.json: {"urls": ["regex"], "apps": ["bundle.id"]}
var callPatterns: [(label: String, rx: String)] = [
    ("Meet", #"meet\.google\.com/([a-z]{3}-[a-z]{4}-[a-z]{3}|lookup/|_meet/)"#),
    ("Discord", #"discord\.com/(channels|call)/"#),
    ("Zoom", #"zoom\.us/(wc|j|s)/"#),
    ("Teams", #"teams\.(microsoft|live)\.com/"#),
    ("Whereby", #"whereby\.com/[^/?#]+"#),
    ("Jitsi", #"meet\.jit\.si/[^/?#]+"#),
    ("Webex", #"\.webex\.com/(meet|launch|wbxmjs)"#),
    ("Gather", #"gather\.town/app"#),
]
// App native che chiudiamo del tutto (chiudere la finestra non basta a lasciare la call).
var nativeApps: [(id: String, name: String)] = [
    ("us.zoom.xos", "Zoom"), ("com.hnc.Discord", "Discord"),
    ("com.microsoft.teams2", "Teams"), ("com.microsoft.teams", "Teams"), ("com.apple.FaceTime", "FaceTime"),
]

func loadExtraConfig() {
    let path = NSString(string: "~/.config/kakashi.json").expandingTildeInPath
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
    for u in (json["urls"] as? [String]) ?? [] { callPatterns.append(("Call", u)) }
    for a in (json["apps"] as? [String]) ?? [] { nativeApps.append((a, a)) }
}

func matchCall(_ url: String) -> String? {
    for (label, rx) in callPatterns {
        if url.range(of: rx, options: [.regularExpression, .caseInsensitive]) != nil { return label }
    }
    return nil
}

func runScript(_ src: String) -> (out: String, err: String?) {
    var err: NSDictionary?
    let r = NSAppleScript(source: src)?.executeAndReturnError(&err)
    if let e = err { return ("", (e[NSAppleScript.errorMessage] as? String) ?? "errore AppleScript") }
    return (r?.stringValue ?? "", nil)
}

func listTabsScript(_ id: String) -> String {
    """
    tell application id "\(id)"
      set out to ""
      set wi to 0
      repeat with w in windows
        set wi to wi + 1
        set ti to 0
        repeat with t in tabs of w
          set ti to ti + 1
          set out to out & wi & "|" & ti & "|" & (URL of t) & linefeed
        end repeat
      end repeat
      return out
    end tell
    """
}

/// Chiude solo le schede che sono una call e le app di call native. Ritorna il messaggio da mostrare.
func leaveCalls() -> String {
    var closed: [String] = [], denied = false
    for b in browsers {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: b.id).isEmpty else { continue }
        let (out, err) = runScript(listTabsScript(b.id))
        if let err = err { log("\(b.name): \(err)"); if err.contains("Not authorized") || err.contains("1743") { denied = true }; continue }
        var hits: [(w: Int, t: Int, label: String)] = []
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, let w = Int(parts[0]), let t = Int(parts[1]), let label = matchCall(String(parts[2])) else { continue }
            hits.append((w, t, label))
        }
        // dal fondo: chiudere una scheda non sposta gli indici di quelle prima
        hits.sort { ($0.w, $0.t) > ($1.w, $1.t) }
        for h in hits {
            log("\(DRY ? "[prova] chiuderei" : "chiudo") \(h.label) in \(b.name) (finestra \(h.w), scheda \(h.t))")
            if !DRY { _ = runScript("tell application id \"\(b.id)\" to close tab \(h.t) of window \(h.w)") }
            closed.append(h.label)
        }
    }
    for n in nativeApps {
        for a in NSRunningApplication.runningApplications(withBundleIdentifier: n.id) {
            log("\(DRY ? "[prova] chiuderei" : "chiudo") l'app \(n.name)")
            if !DRY { a.terminate() }
            closed.append(n.name)
        }
    }
    if closed.isEmpty { return denied ? "Consenti Automazione a Kakashi nelle impostazioni" : "Nessuna call trovata" }
    var seen = Set<String>(), uniq: [String] = []
    for c in closed where seen.insert(c).inserted { uniq.append(c) }
    return (DRY ? "[prova] " : "Uscito da: ") + uniq.joined(separator: ", ")
}

// MARK: - Effetto: sbuffo di fumo + sparizione dal video

struct LCG {
    var s: UInt64
    mutating func next() -> Double {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return Double((s >> 33) & 0xFFFFFF) / Double(0x1000000)
    }
}

func clamp(_ x: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double { min(hi, max(lo, x)) }

final class Vanish {
    static let length = 2.6     // durata totale dell'effetto

    let ctx = CIContext()
    let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    let sprite: CIImage
    struct Puff { let ang, rad, size, delay, rot, fade, tone: Double; let core: Bool }
    let puffs: [Puff]

    private let lock = NSLock()
    private var plate: CIImage?     // sfondo appreso (media dei pixel dove non c'eri)
    private var conf: CIImage?      // dove lo sfondo è stato visto davvero (0..1)
    private var mask: CIImage?      // persona 0..1, a dimensione fotogramma, ammorbidita
    private var box: CGRect?        // ingombro della persona nel fotogramma
    private var fill: CIImage?      // sfondo con cui sostituirti, costruito a inizio effetto

    init() {
        var g = LCG(s: 42)
        var ps: [Puff] = []
        // un nucleo di nuvole grandi che copre la sagoma + una corona di nuvolette più piccole e sparse (bordo frastagliato)
        for i in 0..<48 {
            let core = i < 16
            ps.append(Puff(ang: g.next() * 2 * .pi,
                           rad: core ? g.next().squareRoot() * 0.6 : 0.55 + g.next() * 0.7,
                           size: core ? 0.62 + 0.5 * g.next() : 0.18 + 0.34 * g.next(),
                           delay: g.next() * (core ? 0.12 : 0.24), rot: g.next() * 6.28, fade: g.next() * 0.5,
                           tone: g.next(), core: core))
        }
        puffs = ps
        sprite = Vanish.makeSprite()
    }

    static func makeSprite() -> CIImage {
        let n = 256
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let c = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        var g = LCG(s: 7)
        let colors = [CGColor(red: 0.97, green: 0.97, blue: 0.99, alpha: 0.95),
                      CGColor(red: 0.84, green: 0.85, blue: 0.88, alpha: 0.6),
                      CGColor(red: 0.72, green: 0.73, blue: 0.77, alpha: 0)] as CFArray
        let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 0.55, 1])!
        for i in 0..<16 {
            let a = g.next() * 2 * .pi, d = (i == 0 ? 0 : g.next().squareRoot()) * 40
            let r = 46 + g.next() * 24
            let ctr = CGPoint(x: 128 + cos(a) * d, y: 128 + sin(a) * d)
            c.drawRadialGradient(grad, startCenter: ctr, startRadius: 0, endCenter: ctr, endRadius: CGFloat(r), options: [])
        }
        return CIImage(cgImage: c.makeImage()!)
    }

    func bake(_ img: CIImage, _ ext: CGRect) -> CIImage? {
        guard let cg = ctx.createCGImage(img, from: ext, format: .RGBA8, colorSpace: srgb) else { return nil }
        return CIImage(cgImage: cg)
    }

    /// Riceve la maschera della persona (da Vision) e, a riposo, aggiorna lo sfondo appreso.
    func ingest(frame: CIImage, mask maskBuf: CVPixelBuffer, learn: Bool) {
        let ext = frame.extent
        let small = CIImage(cvPixelBuffer: maskBuf)
        let sx = ext.width / small.extent.width, sy = ext.height / small.extent.height
        let grown = small.applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 6]).cropped(to: small.extent)
        let full = grown.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        let soft = full.clampedToExtent().applyingGaussianBlur(sigma: 7).cropped(to: ext)

        // ingombro: scansione del buffer piccolo (le righe in memoria partono dall'alto)
        var newBox: CGRect?
        CVPixelBufferLockBaseAddress(maskBuf, .readOnly)
        if let base = CVPixelBufferGetBaseAddress(maskBuf) {
            let w = CVPixelBufferGetWidth(maskBuf), h = CVPixelBufferGetHeight(maskBuf), bpr = CVPixelBufferGetBytesPerRow(maskBuf)
            var minX = w, maxX = -1, minR = h, maxR = -1
            for row in stride(from: 0, to: h, by: 2) {
                let p = base.advanced(by: row * bpr).assumingMemoryBound(to: UInt8.self)
                for x in stride(from: 0, to: w, by: 2) where p[x] > 128 {
                    minX = min(minX, x); maxX = max(maxX, x); minR = min(minR, row); maxR = max(maxR, row)
                }
            }
            if maxX >= 0 {
                let r = CGRect(x: Double(minX) * sx, y: Double(h - 1 - maxR) * sy,
                               width: Double(maxX - minX + 1) * sx, height: Double(maxR - minR + 1) * sy)
                if r.width * r.height > ext.width * ext.height * 0.005 { newBox = r }
            }
        }
        CVPixelBufferUnlockBaseAddress(maskBuf, .readOnly)

        var np: CIImage?, nc: CIImage?
        if learn {
            let bg = full.applyingFilter("CIColorInvert")      // 1 dove c'è sfondo
            lock.lock(); let p0 = plate, c0 = conf; lock.unlock()
            if let p0 = p0, let c0 = c0 {
                // dove lo sfondo non era mai stato visto si sostituisce subito, altrove si media piano
                let inv = c0.applyingFilter("CIColorInvert")
                let k = inv.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 0.75, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0.75, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 0.75, w: 0), "inputBiasVector": CIVector(x: 0.25, y: 0.25, z: 0.25, w: 0)])
                let a = k.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: bg])
                np = bake(frame.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: p0, kCIInputMaskImageKey: a]), ext)
                nc = bake(bg.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: c0]), ext)
            } else {
                np = bake(frame, ext); nc = bake(bg, ext)
            }
        }
        lock.lock()
        mask = soft
        box = newBox ?? box
        if let np = np, let nc = nc { plate = np; conf = nc }
        lock.unlock()
    }

    func reset() { fill = nil }

    /// Sfondo con cui sostituirti, in ordine di preferenza:
    /// 1) lo sfondo appreso, dove lo hai visto davvero;
    /// 2) una copia NITIDA dello sfondo accanto a te (a sinistra e a destra, sfumate al centro): stessa texture, stessa luce;
    /// 3) solo in ultimo una sfocatura dei dintorni.
    private func buildFill(frame: CIImage, mask m: CIImage, box: CGRect?) -> CIImage? {
        let ext = frame.extent
        let bgMask = m.applyingFilter("CIColorInvert")
        let clear = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: ext)
        func withAlpha(_ img: CIImage, _ a: CIImage) -> CIImage {
            img.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: clear, kCIInputMaskImageKey: a])
        }
        // 3) sfocatura di ripiego (dettaglio ai bordi + colore medio all'interno)
        let pre = withAlpha(frame, bgMask)
        let e = pre.clampedToExtent()
        func blur(_ s: Double) -> CIImage { e.applyingGaussianBlur(sigma: s).cropped(to: ext) }
        let coarse = blur(200).unpremultiplyingAlpha().settingAlphaOne(in: ext)
        var f = blur(15).composited(over: blur(60).composited(over: coarse))

        // 2) copie dello sfondo vicino: il pezzo a sinistra copre la metà sinistra del buco, quello a destra la destra
        if let bx = box {
            let sh = Double(min(bx.width * 1.12 + 40, ext.width * 0.6))
            let tL = CGAffineTransform(translationX: CGFloat(sh), y: 0), tR = CGAffineTransform(translationX: CGFloat(-sh), y: 0)
            let fromL = frame.transformed(by: tL).cropped(to: ext), fromR = frame.transformed(by: tR).cropped(to: ext)
            let validL = bgMask.transformed(by: tL).cropped(to: ext), validR = bgMask.transformed(by: tR).cropped(to: ext)
            // peso della sinistra: 1 a sinistra del centro, 0 a destra, con una fascia stretta di sfumatura (niente "fantasmi")
            let wl = CIFilter(name: "CILinearGradient", parameters: [
                "inputPoint0": CIVector(x: bx.midX - bx.width * 0.12, y: 0), "inputPoint1": CIVector(x: bx.midX + bx.width * 0.12, y: 0),
                "inputColor0": CIColor(red: 1, green: 1, blue: 1), "inputColor1": CIColor(red: 0, green: 0, blue: 0)])!.outputImage!.cropped(to: ext)
            // aL = validL * max(wl, 1 - validR): la sinistra vince da sola dove la destra non è valida
            let notR = validR.applyingFilter("CIColorInvert")
            let pref = wl.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: notR])
            let aL = validL.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: pref])
            let near = withAlpha(fromL, aL).composited(over: withAlpha(fromR, validR))
            f = near.composited(over: f)
        }
        // 1) lo sfondo appreso, dove noto
        lock.lock(); let p = plate, c = conf; lock.unlock()
        if let p = p, let c = c { f = p.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: f, kCIInputMaskImageKey: c]) }
        return bake(f, ext)
    }

    /// Il fotogramma con l'effetto al tempo t (secondi dallo scatto).
    func render(_ frame: CIImage, t: Double) -> CIImage {
        let ext = frame.extent
        lock.lock(); let m = mask, b = box; lock.unlock()
        var base = frame
        if let m = m {
            // lo sfondo si costruisce un attimo dopo lo scatto, con la maschera aggiornata (a braccia aperte la sagoma è diversa da quella a riposo)
            if fill == nil, t >= 0.28 { fill = buildFill(frame: frame, mask: m, box: b) }
            // la sostituzione è graduale e avviene sotto il fumo, senza "stacco"
            let a = clamp((t - 0.40) / 0.2)
            if a > 0, let f = fill {
                let mm = a >= 1 ? m : m.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: a, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: a, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: a, w: 0)])
                base = f.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: frame, kCIInputMaskImageKey: mm])
            }
        }
        // breve lampo bianco, come nelle bombe fumogene
        let flash = clamp(1 - abs(t - 0.42) / 0.16) * 0.38
        if flash > 0.01 { base = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: CGFloat(flash))).cropped(to: ext).composited(over: base) }
        let area = b ?? CGRect(x: ext.width * 0.3, y: ext.height * 0.15, width: ext.width * 0.4, height: ext.height * 0.7)
        return smoke(over: base, t: t, area: area).cropped(to: ext)
    }

    private func smoke(over base: CIImage, t: Double, area: CGRect) -> CIImage {
        var out = base
        let dmax = Double(max(area.width, area.height))
        for p in puffs {
            let s = clamp((t - p.delay) / (p.core ? 0.32 : 0.4))
            if s <= 0 { continue }
            let e = 1 - pow(1 - s, 3)
            let fade = 1 - clamp((t - (1.1 + p.fade)) / 1.0)
            if fade <= 0 { continue }
            let size = dmax * p.size * (0.3 + 0.7 * e) * (1 + 0.3 * max(0, t - 0.6))
            let swirl = p.ang + t * (p.core ? 0.35 : 0.7) * (p.tone > 0.5 ? 1 : -1)      // la nuvola gira piano
            let x = Double(area.midX) + cos(swirl) * p.rad * Double(area.width) * 0.5
            let y = Double(area.midY) + sin(swirl) * p.rad * Double(area.height) * 0.5 + max(0, t - 0.5) * 46 * (0.4 + p.size)
            let k = size / 256
            let tf = CGAffineTransform(translationX: x, y: y).rotated(by: p.rot + t * 0.3).scaledBy(x: k, y: k).translatedBy(x: -128, y: -128)
            let alpha = e * fade * (p.core ? 0.98 : 0.86)
            let v = 0.78 + 0.22 * p.tone                                                  // qualche nuvola più grigia: dà volume
            let img = sprite.transformed(by: tf).applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: CGFloat(v), y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: CGFloat(v), z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(v), w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(alpha))])
            out = img.composited(over: out)
        }
        return out
    }
}

// MARK: - Effetto "Real Stoner": fermo immagine, grigio lento, occhiali Thug Life, joint lungo e scritta

enum Props {
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    static func makeContext(_ w: Int, _ h: Int) -> CGContext {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    /// Occhiali neri "pixel" stile Thug Life (8-bit): due lenti con gli angoli in basso tagliati a gradini, ponte e stanghette.
    static func glasses() -> CIImage {
        let cols = 40, rows = 9, px = 12
        var cell = [[Bool]](repeating: [Bool](repeating: false, count: cols), count: rows)
        func fill(_ r: Int, _ from: Int, _ to: Int) { for c in from...to { cell[r][c] = true } }
        for r in 0..<rows {
            let inset = r < 4 ? 0 : r - 3                    // dal 4° rigo le lenti si stringono a gradini
            fill(r, 3 + inset, 17 - inset)                   // lente sinistra
            fill(r, 22 + inset, 36 - inset)                  // lente destra
        }
        fill(0, 18, 21); fill(1, 18, 21)                     // ponte
        fill(0, 0, 2); fill(1, 0, 2); fill(0, 37, 39); fill(1, 37, 39)   // stanghette
        let ctx = makeContext(cols * px, rows * px)
        for r in 0..<rows { for c in 0..<cols where cell[r][c] {
            ctx.setFillColor(CGColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1))
            ctx.fill(CGRect(x: c * px, y: (rows - 1 - r) * px, width: px, height: px))
        } }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.30))     // riflesso sulle lenti
        for (r, c) in [(1, 6), (2, 7), (3, 8), (1, 25), (2, 26), (3, 27)] {
            ctx.fill(CGRect(x: c * px, y: (rows - 1 - r) * px, width: px, height: px))
        }
        return CIImage(cgImage: ctx.makeImage()!)
    }

    /// Joint lunghissimo: parte stretta (attorcigliata) in bocca, si allarga verso la punta che brucia. Ritorna anche la punta.
    static func joint() -> (img: CIImage, ember: CGPoint, base: CGPoint) {
        let W = 1100, H = 130, cy = 65.0
        let ctx = makeContext(W, H)
        let body = CGMutablePath()
        body.move(to: CGPoint(x: 26, y: cy + 11)); body.addLine(to: CGPoint(x: 990, y: cy + 33))
        body.addLine(to: CGPoint(x: 990, y: cy - 33)); body.addLine(to: CGPoint(x: 26, y: cy - 11)); body.closeSubpath()
        body.addEllipse(in: CGRect(x: 16, y: cy - 11, width: 20, height: 22))
        ctx.saveGState(); ctx.addPath(body); ctx.clip()
        let paper = CGGradient(colorsSpace: srgb, colors: [CGColor(red: 0.98, green: 0.96, blue: 0.88, alpha: 1),
                                                          CGColor(red: 0.90, green: 0.86, blue: 0.74, alpha: 1),
                                                          CGColor(red: 0.74, green: 0.69, blue: 0.56, alpha: 1)] as CFArray, locations: [0, 0.55, 1])!
        ctx.drawLinearGradient(paper, start: CGPoint(x: 0, y: cy + 36), end: CGPoint(x: 0, y: cy - 36), options: [])
        ctx.setStrokeColor(CGColor(red: 0.55, green: 0.50, blue: 0.40, alpha: 0.5)); ctx.setLineWidth(2)     // giunzione della cartina
        ctx.move(to: CGPoint(x: 30, y: cy + 3)); ctx.addLine(to: CGPoint(x: 990, y: cy + 9)); ctx.strokePath()
        ctx.setStrokeColor(CGColor(red: 0.5, green: 0.45, blue: 0.35, alpha: 0.55)); ctx.setLineWidth(3)      // pieghe dell'attorcigliatura
        for i in 0..<5 { let x = 40.0 + Double(i) * 17; ctx.move(to: CGPoint(x: x, y: cy - 12)); ctx.addLine(to: CGPoint(x: x + 9, y: cy + 12)); ctx.strokePath() }
        let burnt = CGGradient(colorsSpace: srgb, colors: [CGColor(red: 0.55, green: 0.5, blue: 0.45, alpha: 0),
                                                          CGColor(red: 0.30, green: 0.27, blue: 0.24, alpha: 0.95)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(burnt, start: CGPoint(x: 930, y: 0), end: CGPoint(x: 990, y: 0), options: [])   // bruciatura
        ctx.restoreGState()
        // punta incandescente
        ctx.setFillColor(CGColor(red: 0.16, green: 0.14, blue: 0.13, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 978, y: cy - 34, width: 26, height: 68))
        let glow = CGGradient(colorsSpace: srgb, colors: [CGColor(red: 1.0, green: 0.85, blue: 0.35, alpha: 1),
                                                         CGColor(red: 1.0, green: 0.42, blue: 0.08, alpha: 1),
                                                         CGColor(red: 0.75, green: 0.16, blue: 0.04, alpha: 1)] as CFArray, locations: [0, 0.5, 1])!
        ctx.saveGState(); ctx.addEllipse(in: CGRect(x: 984, y: cy - 25, width: 18, height: 50)); ctx.clip()
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 994, y: cy), startRadius: 0, endCenter: CGPoint(x: 994, y: cy), endRadius: 28, options: [])
        ctx.restoreGState()
        return (CIImage(cgImage: ctx.makeImage()!), CGPoint(x: 998, y: cy), CGPoint(x: 26, y: cy))
    }

    /// Alone arancione della brace (additivo).
    static func glow() -> CIImage {
        let ctx = makeContext(256, 256)
        let g = CGGradient(colorsSpace: srgb, colors: [CGColor(red: 1, green: 0.62, blue: 0.2, alpha: 0.95),
                                                      CGColor(red: 1, green: 0.38, blue: 0.08, alpha: 0.45),
                                                      CGColor(red: 1, green: 0.3, blue: 0.05, alpha: 0)] as CFArray, locations: [0, 0.35, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 128, y: 128), startRadius: 0, endCenter: CGPoint(x: 128, y: 128), endRadius: 128, options: [])
        return CIImage(cgImage: ctx.makeImage()!)
    }

    /// "REAL STONER": Impact inclinato in stile graffiti, riempimento giallo→verde, contorno nero spesso e ombra.
    static func realStoner() -> CIImage {
        let font = CTFontCreateWithName("Impact" as CFString, 200, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "REAL STONER", attributes: [.font: font, .kern: 6]))
        let path = CGMutablePath()
        for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
            let attrs = CTRunGetAttributes(run) as NSDictionary
            guard let rf = attrs[kCTFontAttributeName as String] else { continue }
            let n = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: n), pos = [CGPoint](repeating: .zero, count: n)
            CTRunGetGlyphs(run, CFRangeMake(0, n), &glyphs); CTRunGetPositions(run, CFRangeMake(0, n), &pos)
            for i in 0..<n {
                if let g = CTFontCreatePathForGlyph(rf as! CTFont, glyphs[i], nil) {
                    path.addPath(g, transform: CGAffineTransform(translationX: pos[i].x, y: pos[i].y))
                }
            }
        }
        var shear = CGAffineTransform(a: 1, b: 0, c: -0.22, d: 1, tx: 0, ty: 0)
        guard let slanted = path.copy(using: &shear) else { return CIImage.empty() }
        let b = slanted.boundingBoxOfPath, pad: CGFloat = 50
        let ctx = makeContext(Int(b.width + pad * 2), Int(b.height + pad * 2))
        ctx.translateBy(x: -b.minX + pad, y: -b.minY + pad)
        ctx.setLineJoin(.round)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 10, height: -12), blur: 12, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.65))
        ctx.addPath(slanted); ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1)); ctx.setLineWidth(34); ctx.strokePath()
        ctx.restoreGState()
        ctx.saveGState(); ctx.addPath(slanted); ctx.clip()
        let g = CGGradient(colorsSpace: srgb, colors: [CGColor(red: 1.0, green: 0.95, blue: 0.35, alpha: 1),
                                                      CGColor(red: 0.55, green: 0.88, blue: 0.27, alpha: 1),
                                                      CGColor(red: 0.08, green: 0.62, blue: 0.22, alpha: 1)] as CFArray, locations: [0, 0.5, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: b.maxY), end: CGPoint(x: 0, y: b.minY), options: [])
        ctx.restoreGState()
        ctx.addPath(slanted); ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.35)); ctx.setLineWidth(3); ctx.strokePath()
        return CIImage(cgImage: ctx.makeImage()!)
    }
}

func easeInOut(_ x: Double) -> Double { x * x * (3 - 2 * x) }
func easeOutBack(_ x: Double) -> Double { let c1 = 1.70158, c3 = c1 + 1; return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2) }
func bounceOut(_ x: Double) -> Double {
    let n = 7.5625, d = 2.75
    if x < 1 / d { return n * x * x }
    if x < 2 / d { let y = x - 1.5 / d; return n * y * y + 0.75 }
    if x < 2.5 / d { let y = x - 2.25 / d; return n * y * y + 0.9375 }
    let y = x - 2.625 / d; return n * y * y + 0.984375
}

final class Stoner {
    static let length = 4.4
    let ctx: CIContext, srgb: CGColorSpace
    let glasses = Props.glasses()
    let jointArt = Props.joint()
    let glowArt = Props.glow()
    let textArt = Props.realStoner()
    let smoke = Vanish.makeSprite()
    var frozen: CIImage?        // solo camQueue
    var face: FaceGeom?
    var side = 1.0              // +1: il joint esce a destra della bocca (mano a destra), -1: a sinistra

    init(ctx: CIContext, srgb: CGColorSpace) { self.ctx = ctx; self.srgb = srgb }

    func begin(face: FaceGeom?, side: Double = 1) { frozen = nil; self.face = face; self.side = side >= 0 ? 1 : -1 }

    private func bake(_ img: CIImage, _ ext: CGRect) -> CIImage {
        guard let cg = ctx.createCGImage(img, from: ext, format: .RGBA8, colorSpace: srgb) else { return img }
        return CIImage(cgImage: cg)
    }

    private func puff(_ out: CIImage, at p: CGPoint, size: Double, rot: Double, alpha: Double, tone: Double = 1) -> CIImage {
        guard alpha > 0.01, size > 1 else { return out }
        let k = size / 256
        let tf = CGAffineTransform(translationX: p.x, y: p.y).rotated(by: rot).scaledBy(x: k, y: k).translatedBy(x: -128, y: -128)
        let v = CGFloat(tone)
        return smoke.transformed(by: tf).applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: v, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: v, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: v, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(alpha))]).composited(over: out)
    }

    /// flipText: la finestrella è uno specchio, quindi lì la scritta va preparata già rovesciata perché si legga giusta.
    func render(_ live: CIImage, t: Double, flipText: Bool = false) -> CIImage {
        let ext = live.extent, W = Double(ext.width), H = Double(ext.height)
        if frozen == nil { frozen = bake(live, ext) }        // l'immagine si blocca qui
        var out = frozen!
        // grigio lento e leggero
        let k = easeInOut(clamp(t / 2.4))
        out = out.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1 - 0.68 * k, kCIInputBrightnessKey: -0.04 * k, kCIInputContrastKey: 1 + 0.07 * k])
        if k > 0.02 { out = out.applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: 0.8 * k, kCIInputRadiusKey: 1.9]) }

        if let f = face {
            func px(_ p: CGPoint) -> CGPoint { CGPoint(x: Double(p.x) * W, y: Double(p.y) * H) }
            var eL = px(f.eyeL), eR = px(f.eyeR)
            if eL.x > eR.x { swap(&eL, &eR) }
            let c = CGPoint(x: (eL.x + eR.x) / 2, y: (eL.y + eR.y) / 2)
            let d = max(hypot(Double(eR.x - eL.x), Double(eR.y - eL.y)), 8)
            let ang = atan2(Double(eR.y - eL.y), Double(eR.x - eL.x))
            let faceW = max(f.faceW * W, 40)

            // occhiali: cadono dall'alto sugli occhi con un rimbalzo
            let u = clamp((t - 0.5) / 0.6)
            if u > 0 {
                let gk = d * 2.6 / Double(glasses.extent.width)
                let dy = (1 - bounceOut(u)) * H * 0.5
                let tf = CGAffineTransform(translationX: c.x, y: c.y + dy).rotated(by: ang).scaledBy(x: gk, y: gk)
                    .translatedBy(x: -glasses.extent.width / 2, y: -glasses.extent.height / 2)
                out = glasses.samplingNearest().transformed(by: tf).composited(over: out)
            }

            // joint: esce dall'angolo della bocca dal lato della mano, verso l'esterno e leggermente in su
            let m = px(f.mouth), mw = f.mouthW * W
            let sd = side
            let base = CGPoint(x: Double(m.x) + cos(ang) * mw * 0.34 * sd, y: Double(m.y) + sin(ang) * mw * 0.34 * sd - mw * 0.02)
            let jAng = ang + 0.2 * sd
            let jk = faceW * 1.4 / Double(jointArt.img.extent.width)
            let ju = clamp((t - 0.95) / 0.45)
            var ember: CGPoint?
            if ju > 0 {
                let sx = max(easeOutBack(ju), 0.01)
                // a sinistra lo sprite si specchia in orizzontale (così la luce e la brace restano dal lato giusto)
                let tf = CGAffineTransform(translationX: base.x, y: base.y).rotated(by: jAng).scaledBy(x: jk * sx * sd, y: jk * 1.55)
                    .translatedBy(x: -jointArt.base.x, y: -jointArt.base.y)
                // il joint passa DAVANTI agli occhiali e alla faccia
                out = jointArt.img.transformed(by: tf).composited(over: out)
                let len = Double(jointArt.ember.x - jointArt.base.x) * jk * sx * sd
                ember = CGPoint(x: Double(base.x) + cos(jAng) * len, y: Double(base.y) + sin(jAng) * len)
            }
            if let e = ember {
                // brace che pulsa
                let pulse = 0.78 + 0.22 * sin(t * 7.0)
                let gs = faceW * 0.46 * (0.9 + 0.1 * pulse)
                let gtf = CGAffineTransform(translationX: e.x, y: e.y).scaledBy(x: gs / 256, y: gs / 256).translatedBy(x: -128, y: -128)
                out = glowArt.transformed(by: gtf).applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: out]).settingAlphaOne(in: ext)
                // fumo che sale dalla brace
                for i in 0..<26 {
                    let age = t - (1.4 + Double(i) * 0.1)
                    guard age > 0, age < 2.6 else { continue }
                    let sway = sin(Double(i) * 1.7 + age * 2.2) * 0.10 * faceW * min(age, 1.5)
                    let p = CGPoint(x: Double(e.x) + sway + age * 0.07 * faceW, y: Double(e.y) + age * 0.46 * faceW)
                    out = puff(out, at: p, size: faceW * (0.18 + 0.50 * age / 2.6), rot: Double(i) + age * 0.4,
                               alpha: clamp(age * 4) * (1 - age / 2.6) * 0.72, tone: 0.94)
                }
            }
            // sbuffata dalla bocca
            for i in 0..<10 {
                let age = t - (2.4 + Double(i) * 0.08)
                guard age > 0, age < 1.8 else { continue }
                let spread = (Double(i) - 4.5) * 0.18
                let p = CGPoint(x: Double(m.x) + (age * 0.30 + sin(spread) * age * 0.3) * faceW, y: Double(m.y) + age * 0.26 * faceW + cos(spread) * age * 0.1 * faceW)
                out = puff(out, at: p, size: faceW * (0.2 + 0.6 * age / 1.8), rot: Double(i) * 0.7 + age * 0.3,
                           alpha: clamp(age * 4) * (1 - age / 1.8) * 0.75, tone: 0.98)
            }
        }

        // scritta: entra con un rimbalzo, poi pulsa piano
        let tu = clamp((t - 1.7) / 0.45)
        if tu > 0, textArt.extent.width > 1 {
            let target = W * 0.74
            let pulse = tu >= 1 ? 1 + 0.02 * sin(t * 6.5) : easeOutBack(tu)
            let kk = target / Double(textArt.extent.width) * max(pulse, 0.01)
            let tf = CGAffineTransform(translationX: W / 2, y: H * 0.15).rotated(by: -0.05).scaledBy(x: flipText ? -kk : kk, y: kk)
                .translatedBy(x: -textArt.extent.width / 2, y: -textArt.extent.height / 2)
            out = textArt.transformed(by: tf).composited(over: out)
        }

        // dissolvenza finale verso il video dal vivo
        let fade = clamp((t - (Stoner.length - 0.4)) / 0.4)
        if fade > 0 {
            out = out.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(1 - fade))]).composited(over: live)
        }
        return out.cropped(to: ext)
    }
}

// MARK: - Effetto zoom sul volto ("eh?" dei cartoni)

final class Zoom {
    static let length = 0.7                   // dura quanto il suono
    var center = CGPoint(x: 0.5, y: 0.5)      // centro del volto, normalizzato; si aggiorna mentre l'effetto dura (solo camQueue)

    func render(_ frame: CIImage, t: Double) -> CIImage {
        let ext = frame.extent, W = Double(ext.width), H = Double(ext.height)
        // spinta veloce con un po' di rimbalzo, tenuta con un lento avvicinamento, ritorno morbido
        let push = easeOutBack(clamp(t / 0.22))
        let back = easeInOut(clamp((t - 0.42) / 0.28))
        let z = max(0, push) * (1 - back)
        let creep = 0.05 * clamp((t - 0.22) / 0.3) * (1 - back)
        let S = 1 + (ZOOM - 1) * z + creep * z
        // il volto va verso il centro, senza uscire dall'inquadratura
        var cx = Double(center.x) * W, cy = Double(center.y) * H
        cx = min(max(cx, W / (2 * S)), W - W / (2 * S)); cy = min(max(cy, H / (2 * S)), H - H / (2 * S))
        let w = clamp(z)
        let t0x = cx + w * (W / 2 - cx), t0y = cy + w * (H / 2 - cy)
        let scaled = frame.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: S, kCIInputAspectRatioKey: 1.0])
        var out = scaled.transformed(by: CGAffineTransform(translationX: t0x - S * cx, y: t0y - S * cy)).clampedToExtent().cropped(to: ext)
        if z > 0.02 { out = out.applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: 0.7 * z, kCIInputRadiusKey: 1.8]) }
        return out
    }
}

// MARK: - Suoni (sintetizzati in codice, nessun file audio)

enum Wave { case sine, tri, saw, square }

enum Synth {
    static let sr = 44100.0

    struct Noise { var s: UInt64 = 12345
        mutating func next() -> Float { s = s &* 6364136223846793005 &+ 1442695040888963407; return Float(Int64(bitPattern: s >> 11) % 2_000_001) / 1_000_000 - 1 }
    }
    static var rng = Noise()

    /// Inviluppo: attacco lineare, tenuta, caduta esponenziale, e una breve rampa finale contro i click.
    static func env(_ t: Double, _ dur: Double, attack: Double, hold: Double, decay: Double) -> Float {
        let a = min(t / max(attack, 1e-4), 1)
        let d = t < hold ? 1 : exp(-(t - hold) / max(decay, 1e-4))
        let end = min(1, (dur - t) / 0.004)
        return Float(a * d * max(end, 0))
    }

    static func osc(_ w: Wave, dur: Double, f0: Double, f1: Double? = nil, vib: (rate: Double, depth: Double)? = nil,
                    attack: Double = 0.004, hold: Double = 0, decay: Double = 0.15) -> [Float] {
        let n = Int(dur * sr); var out = [Float](repeating: 0, count: n); var ph = 0.0
        for i in 0..<n {
            let t = Double(i) / sr
            var f = f1 == nil ? f0 : f0 * pow(f1! / f0, t / dur)
            if let v = vib { f *= 1 + v.depth * sin(2 * .pi * v.rate * t) }
            ph += 2 * .pi * f / sr
            let x: Double
            switch w {
            case .sine: x = sin(ph)
            case .tri: x = 2 / .pi * asin(sin(ph))
            case .saw: let u = ph / (2 * .pi); x = 2 * (u - floor(u + 0.5))
            case .square: x = sin(ph) >= 0 ? 0.7 : -0.7
            }
            out[i] = Float(x) * env(t, dur, attack: attack, hold: hold, decay: decay)
        }
        return out
    }

    static func onePole(_ x: [Float], _ f0: Double, _ f1: Double) -> [Float] {   // passa-basso con taglio che scorre da f0 a f1
        var y: Float = 0; var out = x
        for i in 0..<x.count {
            let f = f0 * pow(f1 / f0, Double(i) / Double(max(x.count - 1, 1)))
            let a = Float(1 - exp(-2 * .pi * f / sr)); y += a * (x[i] - y); out[i] = y
        }
        return out
    }
    static func highpass(_ x: [Float], _ f: Double) -> [Float] {
        let lp = onePole(x, f, f); return zip(x, lp).map { $0 - $1 }
    }

    /// Rumore filtrato: taglio alto che scorre da lp.0 a lp.1, taglio basso fisso hp.
    static func noise(dur: Double, lp: (Double, Double), hp: Double = 0, attack: Double = 0.003, hold: Double = 0, decay: Double = 0.2) -> [Float] {
        let n = Int(dur * sr); var x = (0..<n).map { _ in rng.next() }
        x = onePole(x, lp.0, lp.1); if hp > 0 { x = highpass(x, hp) }
        for i in 0..<n { x[i] *= env(Double(i) / sr, dur, attack: attack, hold: hold, decay: decay) }
        return x
    }

    struct Track {
        var d: [Float]
        init(_ seconds: Double) { d = [Float](repeating: 0, count: Int(seconds * sr)) }
        mutating func add(_ x: [Float], at t: Double, _ gain: Float = 1) {
            let s0 = Int(t * sr); if s0 >= d.count { return }
            for i in 0..<x.count where s0 + i >= 0 && s0 + i < d.count { d[s0 + i] += x[i] * gain }
        }
    }

    static func kick() -> [Float] {
        let body = osc(.sine, dur: 0.28, f0: 150, f1: 42, attack: 0.001, decay: 0.09)
        let click = noise(dur: 0.01, lp: (6000, 6000), attack: 0.0005, decay: 0.004)
        return zip(body, click + [Float](repeating: 0, count: max(0, body.count - click.count))).map { $0 + 0.4 * $1 }
    }
    static func clap() -> [Float] {
        var t = Track(0.3)
        for k in 0..<3 { t.add(noise(dur: 0.06, lp: (4800, 3500), hp: 900, attack: 0.001, decay: 0.02), at: Double(k) * 0.011, 0.8) }
        t.add(noise(dur: 0.16, lp: (4200, 2500), hp: 900, attack: 0.001, decay: 0.07), at: 0.034)
        return t.d
    }
    static func hat() -> [Float] { noise(dur: 0.05, lp: (9000, 9000), hp: 6500, attack: 0.001, decay: 0.012) }
    static func pluck(_ f: Double, dur: Double) -> [Float] {
        onePole(osc(.saw, dur: dur, f0: f, attack: 0.003, decay: dur * 0.45), 2600, 380)
    }
    static func tick(_ amp: Float) -> [Float] {
        let a = osc(.sine, dur: 0.03, f0: 2100, attack: 0.0005, decay: 0.008), b = noise(dur: 0.02, lp: (7000, 7000), hp: 2500, decay: 0.006)
        return zip(a, b + [Float](repeating: 0, count: max(0, a.count - b.count))).map { amp * ($0 + 0.5 * $1) }
    }

    /// Pugni "armati": un breve "bip" che sale.
    static func armed() -> [Float] { osc(.tri, dur: 0.12, f0: 740, f1: 1180, attack: 0.004, decay: 0.07).map { $0 * 0.5 } }

    /// Sbuffo ninja (2,6 s, allineato all'effetto): soffio che sale, "puf" con tonfo, scintilla della sparizione, coda di fumo, "pop" quando esci.
    static func puff() -> [Float] {
        var t = Track(2.8)
        t.add(noise(dur: 0.45, lp: (500, 4200), hp: 300, attack: 0.25, hold: 0.0, decay: 0.2), at: 0.0, 0.55)           // soffio che sale
        t.add(osc(.sine, dur: 0.5, f0: 95, f1: 45, attack: 0.002, decay: 0.12), at: 0.40, 1.0)                           // tonfo
        t.add(noise(dur: 0.9, lp: (2600, 500), hp: 120, attack: 0.004, decay: 0.28), at: 0.40, 1.0)                      // "puf"
        t.add(noise(dur: 1.9, lp: (900, 350), hp: 80, attack: 0.5, hold: 0.2, decay: 0.7), at: 0.55, 0.28)               // coda di fumo
        for (i, f) in [1568.0, 1319.0, 988.0].enumerated() {                                                              // sparizione
            t.add(osc(.sine, dur: 0.09, f0: f, attack: 0.002, decay: 0.03), at: 0.56 + Double(i) * 0.055, 0.22)
        }
        t.add(osc(.sine, dur: 0.16, f0: 520, f1: 190, attack: 0.002, decay: 0.05), at: 2.3, 0.5)                          // pop di uscita
        t.add(noise(dur: 0.06, lp: (5000, 2000), hp: 600, decay: 0.02), at: 2.3, 0.4)
        return t.d
    }

    /// Real Stoner (4,4 s): rimbalzi degli occhiali, joint, sfrigolio della brace, un solo giro di "ta-ga-ta-ga-da", sbuffata.
    static func stoner() -> [Float] {
        var t = Track(4.5)
        for (i, (time, amp)) in [(0.72, 1.0), (0.94, 0.6), (1.05, 0.35), (1.12, 0.2)].enumerated() {                      // occhiali che cadono
            t.add(tick(Float(amp)), at: time, 0.9)
            if i == 0 { t.add(osc(.sine, dur: 0.25, f0: 110, f1: 55, attack: 0.002, decay: 0.07), at: time, 0.9) }
        }
        t.add(noise(dur: 0.45, lp: (700, 5000), hp: 200, attack: 0.18, decay: 0.14), at: 0.95, 0.35)                      // il joint spunta
        for k in 0..<4 { t.add(noise(dur: 0.03, lp: (6000, 3000), hp: 1500, decay: 0.008), at: 1.0 + Double(k) * 0.08, 0.3) }
        var r = Noise(s: 99)                                                                                              // brace che sfrigola
        var tc = 1.4
        while tc < 3.9 { tc += 0.03 + Double(abs(r.next())) * 0.14; t.add(noise(dur: 0.012, lp: (9000, 4000), hp: 2500, attack: 0.0005, decay: 0.004), at: tc, 0.22 + 0.2 * abs(r.next())) }
        let step = 0.12, start = 1.7                                                                                      // ritmo: 125 bpm, sedicesimi
        for i in 0..<16 {
            let tm = start + Double(i) * step
            if [0, 6, 10, 14].contains(i) { t.add(kick(), at: tm, 0.95) }
            if [4, 12].contains(i) { t.add(clap(), at: tm, 0.7) }
            if i % 2 == 0 { t.add(hat(), at: tm, 0.35) }
        }
        let E = 164.81, G = 196.0, A = 220.0, B = 246.94                                                                   // "ta ga ta ga da" ×2
        let riff: [(Int, Double, Double)] = [(0, E, 0.1), (1, E, 0.1), (2, G, 0.1), (3, E, 0.1), (4, A, 0.28),
                                             (8, E, 0.1), (9, E, 0.1), (10, G, 0.1), (11, E, 0.1), (12, B, 0.3)]
        for (i, f, d) in riff { t.add(pluck(f, dur: d + 0.12), at: start + Double(i) * step, 0.85) }
        t.add(noise(dur: 0.9, lp: (1200, 1800), hp: 350, attack: 0.25, decay: 0.28), at: 2.4, 0.45)                        // sbuffata
        let n = t.d.count, fadeFrom = Int((Stoner.length - 0.4) * sr)                                                      // dissolvenza finale
        for i in fadeFrom..<n { t.d[i] *= Float(max(0, 1 - Double(i - fadeFrom) / Double(n - fadeFrom))) }
        return t.d
    }

    /// Zoom: solo il "vwoop" d'ingresso della spinta.
    static func zoomSound() -> [Float] {
        var t = Track(0.7)
        t.add(onePole(osc(.saw, dur: 0.36, f0: 160, f1: 420, attack: 0.02, decay: 0.2), 700, 3200), at: 0.0, 0.45)
        t.add(noise(dur: 0.4, lp: (300, 3200), hp: 150, attack: 0.18, decay: 0.15), at: 0.0, 0.4)
        return t.d
    }

    /// Tasto che scatta.
    static func key() -> [Float] {
        let a = noise(dur: 0.012, lp: (7000, 3500), hp: 1800, attack: 0.0005, decay: 0.004)
        let b = osc(.sine, dur: 0.012, f0: 190, attack: 0.0005, decay: 0.004)
        return zip(a, b).map { $0 + 0.5 * $1 }
    }

    /// Trasformazione in sviluppatore (4,6 s): sweep, glitch, tastiera, accordo del titolo.
    static func dev() -> [Float] {
        var t = Track(4.7)
        t.add(onePole(osc(.saw, dur: 0.55, f0: 110, f1: 1100, attack: 0.02, decay: 0.3), 500, 6000), at: 0.0, 0.5)      // trasformazione
        t.add(noise(dur: 0.6, lp: (400, 7000), hp: 200, attack: 0.3, decay: 0.2), at: 0.0, 0.4)
        var r = Noise(s: 5)
        for k in 0..<7 { t.add(osc(.square, dur: 0.045, f0: 200 + 700 * Double(abs(r.next())), attack: 0.001, decay: 0.02), at: 0.22 + Double(k) * 0.075, 0.28) }   // glitch
        for (start, line) in zip(DEV_STARTS, DEV_LINES) {                                                                  // digitazione
            for c in 0..<line.count { t.add(key(), at: start + Double(c) / DEV_CPS, 0.35 + 0.3 * abs(Float(r.next()))) }
            t.add(key(), at: start + Double(line.count) / DEV_CPS + 0.05, 0.8)                                            // invio
        }
        t.add(osc(.sine, dur: 0.16, f0: 880, attack: 0.003, decay: 0.07), at: 2.62, 0.25)                                // "permesso concesso"
        t.add(osc(.sine, dur: 0.3, f0: 1320, attack: 0.003, decay: 0.12), at: 2.78, 0.25)
        for f in [110.0, 164.81, 220.0, 277.18] { t.add(onePole(osc(.saw, dur: 0.9, f0: f, attack: 0.01, decay: 0.35), 2600, 500), at: 3.0, 0.4) }   // titolo
        t.add(osc(.sine, dur: 0.5, f0: 85, f1: 38, attack: 0.002, decay: 0.14), at: 3.0, 0.9)
        let n = t.d.count, fadeFrom = Int((Dev.length - 0.4) * sr)
        for i in fadeFrom..<n { t.d[i] *= Float(max(0, 1 - Double(i - fadeFrom) / Double(n - fadeFrom))) }
        return t.d
    }

    /// Caffè bevuto: due sorsi e un campanello.
    static func coffee() -> [Float] {
        var t = Track(1.5)
        t.add(osc(.sine, dur: 0.14, f0: 260, f1: 120, attack: 0.005, decay: 0.05), at: 0.0, 0.5)
        t.add(osc(.sine, dur: 0.12, f0: 230, f1: 110, attack: 0.005, decay: 0.05), at: 0.16, 0.45)
        for (f, a) in [(1568.0, 1.0), (2349.0, 0.5), (3136.0, 0.25)] { t.add(osc(.sine, dur: 1.0, f0: f, attack: 0.002, decay: 0.28), at: 0.36, Float(a * 0.5)) }
        return t.d
    }

    /// Normalizza il picco e smorza i picchi eccessivi.
    static func finish(_ x: [Float]) -> [Float] {
        let peak = max(x.map { abs($0) }.max() ?? 1, 0.001)
        return x.map { tanhf($0 / peak * 1.4) * 0.62 }
    }
}

final class Sfx {
    private let engine = AVAudioEngine()
    private var nodes: [String: AVAudioPlayerNode] = [:]
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var ok = false

    init() {
        guard env["KAKASHI_SOUND"] != "0" else { return }
        let fmt = AVAudioFormat(standardFormatWithSampleRate: Synth.sr, channels: 1)!
        let sounds: [(String, [Float])] = [("armed", Synth.armed()), ("puff", Synth.puff()), ("stoner", Synth.stoner()), ("zoom", Synth.zoomSound()), ("dev", Synth.dev()), ("coffee", Synth.coffee())]
        for (name, raw) in sounds {
            let data = Synth.finish(raw)
            guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(data.count)) else { continue }
            buf.frameLength = AVAudioFrameCount(data.count)
            data.withUnsafeBufferPointer { buf.floatChannelData![0].update(from: $0.baseAddress!, count: data.count) }
            let node = AVAudioPlayerNode()
            engine.attach(node); engine.connect(node, to: engine.mainMixerNode, format: fmt)
            nodes[name] = node; buffers[name] = buf
        }
        do { try engine.start(); ok = true } catch { log("Audio non disponibile: \(error.localizedDescription)") }
    }

    func play(_ name: String) {
        guard ok, let n = nodes[name], let b = buffers[name] else { return }
        if !engine.isRunning { try? engine.start() }
        n.stop(); n.scheduleBuffer(b, at: nil, options: .interrupts); n.play()
    }

    /// Per la prova: scrive i suoni in file WAV.
    static func writeWavs(to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let fmt = AVAudioFormat(standardFormatWithSampleRate: Synth.sr, channels: 1)!
        for (name, raw) in [("armed", Synth.armed()), ("puff", Synth.puff()), ("stoner", Synth.stoner()), ("zoom", Synth.zoomSound()), ("dev", Synth.dev()), ("coffee", Synth.coffee())] {
            let data = Synth.finish(raw)
            guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(data.count)),
                  let file = try? AVAudioFile(forWriting: URL(fileURLWithPath: "\(dir)/\(name).wav"), settings: fmt.settings) else { continue }
            buf.frameLength = AVAudioFrameCount(data.count)
            data.withUnsafeBufferPointer { buf.floatChannelData![0].update(from: $0.baseAddress!, count: data.count) }
            try? file.write(from: buf)
        }
    }
}

// MARK: - Effetto "Developer": ti metti gli occhiali → trasformazione

let DEV_LINES = ["$ whoami", "> utente", "$ sudo become developer", "[sudo] password: ********", "> permesso concesso", "> benvenuto, sviluppatore"]
let DEV_STARTS = [0.9, 1.3, 1.7, 2.2, 2.7, 3.1]     // quando inizia a digitare ogni riga
let DEV_CPS = 34.0                                  // caratteri al secondo

extension Props {
    /// Testo in un'immagine con colore, ombra/alone opzionali. Ritorna anche le dimensioni del testo.
    static func text(_ str: String, font: NSFont, color: NSColor, glow: NSColor? = nil, pad: CGFloat = 24) -> (img: CIImage, w: Double, h: Double) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (str as NSString).size(withAttributes: attrs)
        let ctx = makeContext(Int(size.width + pad * 2), Int(size.height + pad * 2))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        if let g = glow {
            ctx.setShadow(offset: .zero, blur: 22, color: g.cgColor)
            (str as NSString).draw(at: NSPoint(x: pad, y: pad), withAttributes: attrs)
            ctx.setShadow(offset: .zero, blur: 8, color: g.cgColor)
        }
        (str as NSString).draw(at: NSPoint(x: pad, y: pad), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
        return (CIImage(cgImage: ctx.makeImage()!), Double(size.width), Double(size.height))
    }

    /// Colonna della pioggia di codice: testa chiara in basso, coda che sfuma verso l'alto.
    static func rainStrip(seed: UInt64) -> CIImage {
        let cells = 64, cell = 24, w = 30, h = cells * cell
        var g = LCG(s: seed)
        let chars = Array("01{}<>/=;$#()[]+*&|ｱｲｳｴｵｶｷｸｹｺｻｼｽ")
        let ctx = makeContext(w, h)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let font = NSFont(name: "Menlo-Bold", size: 20) ?? NSFont.monospacedSystemFont(ofSize: 20, weight: .bold)
        for i in 0..<cells {
            let p = Double(i) / Double(cells - 1)
            let color = i == cells - 1 ? NSColor(red: 0.85, green: 1, blue: 0.9, alpha: 1)
                                       : NSColor(red: 0.2, green: 1.0, blue: 0.45, alpha: CGFloat(0.06 + 0.94 * pow(p, 2.2)))
            let ch = String(chars[min(Int(g.next() * Double(chars.count)), chars.count - 1)])
            (ch as NSString).draw(at: NSPoint(x: 3, y: Double(h - (i + 1) * cell) + 2), withAttributes: [.font: font, .foregroundColor: color])
        }
        NSGraphicsContext.restoreGraphicsState()
        return CIImage(cgImage: ctx.makeImage()!)
    }

    /// Linee di scansione orizzontali (effetto monitor).
    static func scanlines() -> CIImage {
        let ctx = makeContext(1280, 720)
        ctx.setFillColor(CGColor(red: 0, green: 0.05, blue: 0.02, alpha: 0.18))
        for y in stride(from: 0, to: 720, by: 4) { ctx.fill(CGRect(x: 0, y: y, width: 1280, height: 2)) }
        return CIImage(cgImage: ctx.makeImage()!)
    }

    /// Pillola scura con bordo e testo: usata dal contatore dei caffè.
    static func pill(_ str: String, width: Int, height: Int, fontSize: CGFloat) -> CIImage {
        let ctx = makeContext(width, height)
        let r = CGRect(x: 4, y: 4, width: width - 8, height: height - 8)
        let path = CGPath(roundedRect: r, cornerWidth: r.height / 2, cornerHeight: r.height / 2, transform: nil)
        ctx.addPath(path); ctx.setFillColor(CGColor(red: 0.14, green: 0.09, blue: 0.06, alpha: 0.86)); ctx.fillPath()
        ctx.addPath(path); ctx.setStrokeColor(CGColor(red: 0.88, green: 0.64, blue: 0.36, alpha: 1)); ctx.setLineWidth(5); ctx.strokePath()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
                                                    .foregroundColor: NSColor(red: 1, green: 0.95, blue: 0.85, alpha: 1)]
        let sz = (str as NSString).size(withAttributes: attrs)
        (str as NSString).draw(at: NSPoint(x: (CGFloat(width) - sz.width) / 2, y: (CGFloat(height) - sz.height) / 2), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
        return CIImage(cgImage: ctx.makeImage()!)
    }
}

extension Props {
    /// Contorno di un testo come percorso (CoreText), per riempirlo con gradienti e alone.
    static func textPath(_ str: String, fontName: String, size: CGFloat, kern: CGFloat = 0) -> CGPath {
        let font = CTFontCreateWithName(fontName as CFString, size, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: str, attributes: [.font: font, .kern: kern]))
        let path = CGMutablePath()
        for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
            let attrs = CTRunGetAttributes(run) as NSDictionary
            guard let rf = attrs[kCTFontAttributeName as String] else { continue }
            let n = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: n), pos = [CGPoint](repeating: .zero, count: n)
            CTRunGetGlyphs(run, CFRangeMake(0, n), &glyphs); CTRunGetPositions(run, CFRangeMake(0, n), &pos)
            for i in 0..<n { if let g = CTFontCreatePathForGlyph(rf as! CTFont, glyphs[i], nil) { path.addPath(g, transform: CGAffineTransform(translationX: pos[i].x, y: pos[i].y)) } }
        }
        return path
    }

    /// Testo al neon: riempimento a gradiente (alto→basso), contorno scuro e alone colorato.
    static func neonText(_ str: String, fontName: String, size: CGFloat, top: CGColor, bottom: CGColor, glow: CGColor, kern: CGFloat = 8) -> (img: CIImage, w: Double, h: Double) {
        let path = textPath(str, fontName: fontName, size: size, kern: kern)
        let b = path.boundingBoxOfPath, pad: CGFloat = 60
        let ctx = makeContext(Int(b.width + pad * 2), Int(b.height + pad * 2))
        ctx.translateBy(x: -b.minX + pad, y: -b.minY + pad)
        ctx.setLineJoin(.round)
        ctx.saveGState(); ctx.setShadow(offset: .zero, blur: 40, color: glow)
        ctx.addPath(path); ctx.setStrokeColor(glow); ctx.setLineWidth(10); ctx.strokePath(); ctx.restoreGState()
        ctx.saveGState(); ctx.setShadow(offset: .zero, blur: 16, color: glow)
        ctx.addPath(path); ctx.setStrokeColor(CGColor(red: 0.02, green: 0.04, blue: 0.08, alpha: 1)); ctx.setLineWidth(12); ctx.strokePath(); ctx.restoreGState()
        ctx.saveGState(); ctx.addPath(path); ctx.clip()
        let g = CGGradient(colorsSpace: srgb, colors: [top, bottom] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: b.maxY), end: CGPoint(x: 0, y: b.minY), options: [])
        ctx.restoreGState()
        ctx.addPath(path); ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.7)); ctx.setLineWidth(2); ctx.strokePath()
        return (CIImage(cgImage: ctx.makeImage()!), Double(b.width + pad * 2), Double(b.height + pad * 2))
    }

    /// Finestra stile editor: barra del titolo con tre pallini e righe di testo colorato (token). Dimensioni in pixel.
    static func window(width: Int, title: String, lines: [[(String, NSColor)]], fontSize: CGFloat = 26) -> CIImage {
        let font = NSFont(name: "Menlo-Regular", size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let lineH = fontSize * 1.5, head: CGFloat = 48, pad: CGFloat = 24
        let h = Int(head + pad + CGFloat(lines.count) * lineH + pad * 0.6)
        let ctx = makeContext(width, h)
        let r = CGRect(x: 3, y: 3, width: width - 6, height: h - 6)
        let path = CGPath(roundedRect: r, cornerWidth: 20, cornerHeight: 20, transform: nil)
        ctx.addPath(path); ctx.setFillColor(CGColor(red: 0.04, green: 0.06, blue: 0.10, alpha: 0.88)); ctx.fillPath()
        ctx.saveGState(); ctx.addPath(path); ctx.clip()
        ctx.setFillColor(CGColor(red: 0.10, green: 0.14, blue: 0.21, alpha: 0.97))
        ctx.fill(CGRect(x: 0, y: CGFloat(h) - head - 3, width: CGFloat(width), height: head + 3))
        ctx.restoreGState()
        ctx.addPath(path); ctx.setStrokeColor(CGColor(red: 0.30, green: 0.90, blue: 0.95, alpha: 0.75)); ctx.setLineWidth(3); ctx.strokePath()
        for (i, c) in [(1.0, 0.37, 0.34), (1.0, 0.74, 0.18), (0.16, 0.8, 0.25)].enumerated() {
            ctx.setFillColor(CGColor(red: c.0, green: c.1, blue: c.2, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: 24 + CGFloat(i) * 28, y: CGFloat(h) - head / 2 - 10 - 3, width: 20, height: 20))
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let tattr: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize * 0.72, weight: .medium), .foregroundColor: NSColor(white: 0.75, alpha: 1)]
        let tw = (title as NSString).size(withAttributes: tattr).width
        (title as NSString).draw(at: NSPoint(x: (CGFloat(width) - tw) / 2 + 20, y: CGFloat(h) - head / 2 - 12 - 3), withAttributes: tattr)
        for (i, line) in lines.enumerated() {
            var x = pad, y = CGFloat(h) - head - pad - lineH * CGFloat(i + 1) + 8
            if y < 4 { y = 4 }
            for (seg, color) in line {
                (seg as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: font, .foregroundColor: color])
                x += (seg as NSString).size(withAttributes: [.font: font]).width
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return CIImage(cgImage: ctx.makeImage()!)
    }

    /// Mirino olografico: quattro angoli.
    static func brackets() -> CIImage {
        let n = 512, ctx = makeContext(n, n), m: CGFloat = 40, l: CGFloat = 110
        let c = CGColor(red: 0.35, green: 0.95, blue: 1.0, alpha: 1)
        ctx.setShadow(offset: .zero, blur: 14, color: c)
        ctx.setStrokeColor(c); ctx.setLineWidth(10); ctx.setLineCap(.square)
        let N = CGFloat(n)
        for (cx, cy, dx, dy) in [(m, m, 1.0, 1.0), (N - m, m, -1.0, 1.0), (m, N - m, 1.0, -1.0), (N - m, N - m, -1.0, -1.0)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
            ctx.move(to: CGPoint(x: cx + dx * l, y: cy)); ctx.addLine(to: CGPoint(x: cx, y: cy)); ctx.addLine(to: CGPoint(x: cx, y: cy + dy * l)); ctx.strokePath()
        }
        return CIImage(cgImage: ctx.makeImage()!)
    }

    /// Anello tratteggiato con tacche (gira piano attorno al volto).
    static func ring() -> CIImage {
        let n = 512, ctx = makeContext(n, n)
        let c = CGColor(red: 0.95, green: 0.35, blue: 0.85, alpha: 0.9)
        ctx.setShadow(offset: .zero, blur: 12, color: c)
        ctx.setStrokeColor(c); ctx.setLineWidth(5); ctx.setLineDash(phase: 0, lengths: [26, 18])
        ctx.addEllipse(in: CGRect(x: 40, y: 40, width: n - 80, height: n - 80)); ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: []); ctx.setLineWidth(4)
        for i in 0..<36 {
            let a = Double(i) / 36 * 2 * .pi, r0 = 226.0, r1 = i % 3 == 0 ? 246.0 : 238.0
            ctx.move(to: CGPoint(x: 256 + cos(a) * r0, y: 256 + sin(a) * r0)); ctx.addLine(to: CGPoint(x: 256 + cos(a) * r1, y: 256 + sin(a) * r1)); ctx.strokePath()
        }
        return CIImage(cgImage: ctx.makeImage()!)
    }

    /// Cerchio d'urto (onda che parte dal volto).
    static func shockRing() -> CIImage {
        let n = 512, ctx = makeContext(n, n)
        let c = CGColor(red: 0.5, green: 1, blue: 0.95, alpha: 1)
        ctx.setShadow(offset: .zero, blur: 18, color: c)
        ctx.setStrokeColor(c); ctx.setLineWidth(14)
        ctx.addEllipse(in: CGRect(x: 30, y: 30, width: n - 60, height: n - 60)); ctx.strokePath()
        return CIImage(cgImage: ctx.makeImage()!)
    }
}

final class Dev {
    static let length = 4.6
    let ctx: CIContext, srgb: CGColorSpace
    var face: FaceGeom?                               // solo camQueue
    let rain: [CIImage]
    let rainSpeed: [Double], rainPhase: [Double]
    let scan = Props.scanlines()
    let lines: [(img: CIImage, w: Double, h: Double)]
    let title: (img: CIImage, w: Double, h: Double)
    let subtitle: (img: CIImage, w: Double, h: Double)
    let label: (img: CIImage, w: Double, h: Double)
    let codeA: CIImage, codeB: CIImage
    let brackets = Props.brackets(), ring = Props.ring(), shock = Props.shockRing()
    private var chromeCache: [Int: CIImage] = [:]
    let ncols = 34

    init(ctx: CIContext, srgb: CGColorSpace) {
        self.ctx = ctx; self.srgb = srgb
        var g = LCG(s: 2024)
        rain = (0..<34).map { _ in Props.rainStrip(seed: UInt64(g.next() * 1e9) + 1) }
        rainSpeed = (0..<34).map { _ in 380 + g.next() * 520 }
        rainPhase = (0..<34).map { _ in g.next() * 2200 }
        let mono = NSFont(name: "Menlo-Bold", size: 34) ?? NSFont.monospacedSystemFont(ofSize: 34, weight: .bold)
        lines = DEV_LINES.map { Props.text($0, font: mono, color: NSColor(red: 0.55, green: 1, blue: 0.85, alpha: 1)) }
        title = Props.neonText("DEVELOPER", fontName: "Menlo-Bold", size: 150,
                               top: CGColor(red: 0.55, green: 1, blue: 0.98, alpha: 1), bottom: CGColor(red: 1, green: 0.4, blue: 0.9, alpha: 1),
                               glow: CGColor(red: 0.25, green: 0.9, blue: 1, alpha: 1))
        subtitle = Props.text("mode: ON   ·   funziona sulla mia macchina", font: NSFont(name: "Menlo-Regular", size: 38) ?? mono,
                              color: NSColor(red: 0.8, green: 0.95, blue: 1, alpha: 1), glow: NSColor(red: 0.25, green: 0.9, blue: 1, alpha: 1))
        label = Props.text("build developer.exe", font: NSFont(name: "Menlo-Bold", size: 30) ?? mono, color: NSColor(red: 0.5, green: 1, blue: 0.95, alpha: 1))
        let kw = NSColor(red: 1, green: 0.42, blue: 0.76, alpha: 1), fn = NSColor(red: 0.40, green: 0.85, blue: 0.95, alpha: 1)
        let str = NSColor(red: 0.65, green: 0.90, blue: 0.30, alpha: 1), cm = NSColor(red: 0.45, green: 0.52, blue: 0.62, alpha: 1)
        let tx = NSColor(red: 0.90, green: 0.93, blue: 0.97, alpha: 1), num = NSColor(red: 1, green: 0.65, blue: 0.30, alpha: 1)
        codeA = Props.window(width: 640, title: "devstack.ts", lines: [
            [("// da utente a sviluppatore", cm)],
            [("const ", kw), ("tu", tx), (" = ", tx), ("new ", kw), ("Sviluppatore", fn), ("();", tx)],
            [("tu", tx), (".caffe", fn), (" += ", tx), ("1", num), (";", tx)],
            [("while", kw), (" (!", tx), ("pausa", tx), (") ", tx), ("lavora", fn), ("();", tx)],
            [("tu", tx), (".compila", fn), ("(); ", tx), ("// ok", cm)],
        ])
        codeB = Props.window(width: 560, title: "terminal — git", lines: [
            [("$ ", str), ("git log --oneline", tx)],
            [("a3f9c1e ", NSColor(red: 1, green: 0.85, blue: 0.35, alpha: 1)), ("fix: fix del fix", tx)],
            [("7be21d0 ", NSColor(red: 1, green: 0.85, blue: 0.35, alpha: 1)), ("feat: caffè", tx)],
            [("c0ffee0 ", NSColor(red: 1, green: 0.85, blue: 0.35, alpha: 1)), ("wip: non toccare il main", tx)],
        ])
    }

    func begin(face: FaceGeom?) { self.face = face }

    /// Finestra scura del terminale, della dimensione esatta richiesta (si ricalcola solo se cambia la risoluzione).
    private func chrome(_ w: Int, _ h: Int) -> CIImage {
        let key = w * 10000 + h
        if let c = chromeCache[key] { return c }
        let ctx = Props.makeContext(w, h)
        let r = CGRect(x: 3, y: 3, width: w - 6, height: h - 6)
        let path = CGPath(roundedRect: r, cornerWidth: 16, cornerHeight: 16, transform: nil)
        ctx.addPath(path); ctx.setFillColor(CGColor(red: 0.02, green: 0.05, blue: 0.08, alpha: 0.82)); ctx.fillPath()
        ctx.saveGState(); ctx.addPath(path); ctx.clip()
        ctx.setFillColor(CGColor(red: 0.10, green: 0.14, blue: 0.21, alpha: 0.97)); ctx.fill(CGRect(x: 0, y: h - 40, width: w, height: 40))
        ctx.restoreGState()
        ctx.addPath(path); ctx.setStrokeColor(CGColor(red: 0.30, green: 0.90, blue: 0.95, alpha: 0.75)); ctx.setLineWidth(3); ctx.strokePath()
        for (i, c) in [(1.0, 0.37, 0.34), (1.0, 0.74, 0.18), (0.16, 0.8, 0.25)].enumerated() {
            ctx.setFillColor(CGColor(red: c.0, green: c.1, blue: c.2, alpha: 1)); ctx.fillEllipse(in: CGRect(x: 18 + CGFloat(i) * 24, y: CGFloat(h) - 28, width: 16, height: 16))
        }
        let img = CIImage(cgImage: ctx.makeImage()!)
        chromeCache[key] = img
        return img
    }

    /// Separazione dei canali RGB e fette orizzontali spostate: il "glitch" della trasformazione.
    private func glitch(_ img: CIImage, strength g: Double, t: Double, ext: CGRect) -> CIImage {
        func chan(_ r: CGFloat, _ gg: CGFloat, _ b: CGFloat, dx: Double) -> CIImage {
            img.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: r, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: gg, z: 0, w: 0),
                                                              "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0)])
                .transformed(by: CGAffineTransform(translationX: dx, y: 0))
        }
        let d = 26 * g * Double(ext.width) / 1280
        let split = chan(1, 0, 0, dx: d).applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: chan(0, 1, 0, dx: 0)])
            .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: chan(0, 0, 1, dx: -d)]).settingAlphaOne(in: ext)
        var out = split.clampedToExtent().cropped(to: ext)
        var r = LCG(s: UInt64(Int(t * 24) + 7))
        for _ in 0..<5 {
            let y = r.next() * Double(ext.height), hh = (0.02 + r.next() * 0.08) * Double(ext.height), dx = (r.next() - 0.5) * 140 * g * Double(ext.width) / 1280
            let band = CGRect(x: 0, y: y, width: Double(ext.width), height: hh)
            out = out.cropped(to: band).transformed(by: CGAffineTransform(translationX: dx, y: 0)).composited(over: out)
        }
        return out.cropped(to: ext)
    }

    func render(_ live: CIImage, t: Double, flipText: Bool = false) -> CIImage {
        let ext = live.extent, W = Double(ext.width), H = Double(ext.height), sc = W / 1280
        func alpha(_ img: CIImage, _ a: Double) -> CIImage { a >= 0.999 ? img : img.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(max(0, a)))]) }

        // ── 1) video "da sviluppatore": toni ciano/magenta, rivelati da una linea di scansione dall'alto verso il basso ──
        var graded = live
        let gl = clamp(1 - abs(t - 0.45) / 0.4)
        if gl > 0.02 { graded = glitch(live, strength: gl, t: t, ext: ext) }
        graded = graded.applyingFilter("CIColorMonochrome", parameters: [kCIInputColorKey: CIColor(red: 0.35, green: 0.9, blue: 0.9), kCIInputIntensityKey: 0.5])
            .applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.06, kCIInputContrastKey: 1.22, kCIInputSaturationKey: 1.1])
        let tone = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: H), "inputPoint1": CIVector(x: W, y: 0),
            "inputColor0": CIColor(red: 0.0, green: 0.85, blue: 1.0), "inputColor1": CIColor(red: 1.0, green: 0.15, blue: 0.75)])!.outputImage!.cropped(to: ext)
        graded = alpha(tone, 0.34).applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: graded]).settingAlphaOne(in: ext)
            .applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: 0.85, kCIInputRadiusKey: 1.6])
        let wp = clamp((t - 0.3) / 0.8)
        var out = graded
        if wp < 1 {
            let yw = H * (1 - easeInOut(wp))
            let mask = CIFilter(name: "CILinearGradient", parameters: [
                "inputPoint0": CIVector(x: 0, y: yw + 6), "inputPoint1": CIVector(x: 0, y: yw - 6),
                "inputColor0": CIColor(red: 1, green: 1, blue: 1), "inputColor1": CIColor(red: 0, green: 0, blue: 0)])!.outputImage!.cropped(to: ext)
            out = graded.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: live, kCIInputMaskImageKey: mask])
            if wp > 0 {   // la linea luminosa che scansiona
                let line = CIImage(color: CIColor(red: 0.6, green: 1, blue: 1, alpha: 1)).cropped(to: CGRect(x: 0, y: yw - 2 * sc, width: W, height: 4 * sc))
                let glow = alpha(CIImage(color: CIColor(red: 0.2, green: 0.9, blue: 1, alpha: 1)).cropped(to: CGRect(x: 0, y: yw - 30 * sc, width: W, height: 60 * sc))
                    .clampedToExtent().applyingGaussianBlur(sigma: 14 * sc).cropped(to: ext), 0.5)
                out = line.composited(over: glow.composited(over: out))
            }
        }
        // pioggia di codice, più discreta
        let ra = clamp((t - 0.9) / 0.6) * 0.5
        if ra > 0.02 {
            let hs = 64.0 * 24 * sc
            for i in 0..<ncols {
                let x = (Double(i) + 0.5) / Double(ncols) * W - 15 * sc
                let y = H - (t * rainSpeed[i] * sc + rainPhase[i] * sc).truncatingRemainder(dividingBy: H + hs)
                out = alpha(rain[i].transformed(by: CGAffineTransform(translationX: x, y: y).scaledBy(x: sc, y: sc)), ra).composited(over: out)
            }
        }
        out = scan.transformed(by: CGAffineTransform(scaleX: sc, y: sc)).composited(over: out)

        // ── 2) grafica (testi e mirino) su un livello trasparente: nella finestrella (specchio) si rovescia in blocco ──
        var gfx = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: ext)
        func put(_ img: CIImage, _ tf: CGAffineTransform) { gfx = img.transformed(by: tf).composited(over: gfx) }

        // onda d'urto dal volto
        let fcx = Double(face?.center.x ?? 0.5) * W, fcy = Double(face?.center.y ?? 0.5) * H, fw = max(Double(face?.faceW ?? 0.22) * W, 90 * sc)
        let sw = clamp((t - 0.05) / 0.85)
        if sw > 0 && sw < 1 {
            let size = fw * (1 + 7 * easeInOut(sw))
            put(alpha(shock, (1 - sw) * 0.9), CGAffineTransform(translationX: fcx, y: fcy).scaledBy(x: size / 512, y: size / 512).translatedBy(x: -256, y: -256))
        }
        // mirino olografico attorno al volto, con anello che gira e barra di caricamento
        let hu = clamp((t - 0.9) / 0.4)
        if hu > 0, face != nil {
            let bs = fw * 2.05 * max(easeOutBack(hu), 0.01)
            put(brackets, CGAffineTransform(translationX: fcx, y: fcy).scaledBy(x: bs / 512, y: bs / 512).translatedBy(x: -256, y: -256))
            let rs = fw * 2.6
            put(alpha(ring, 0.55 * hu), CGAffineTransform(translationX: fcx, y: fcy).rotated(by: -t * 0.6).scaledBy(x: rs / 512, y: rs / 512).translatedBy(x: -256, y: -256))
            let lk = fw * 1.7 / label.w
            let lx = fcx - label.w * lk / 2, ly = fcy - fw * 1.18 - label.h * lk
            put(alpha(label.img, hu), CGAffineTransform(translationX: lx, y: ly).scaledBy(x: lk, y: lk))
            let bw = fw * 1.7, by = ly - 20 * sc, pr = clamp((t - 1.2) / 1.8)
            gfx = CIImage(color: CIColor(red: 0.1, green: 0.2, blue: 0.25, alpha: 0.7 * hu)).cropped(to: CGRect(x: fcx - bw / 2, y: by, width: bw, height: 9 * sc)).composited(over: gfx)
            gfx = CIImage(color: CIColor(red: 0.4, green: 1, blue: 0.9, alpha: hu)).cropped(to: CGRect(x: fcx - bw / 2, y: by, width: bw * pr, height: 9 * sc)).composited(over: gfx)
        }
        // finestre da editor che scivolano dentro
        let wa = clamp((t - 1.2) / 0.5), wb = clamp((t - 1.5) / 0.5)
        if wa > 0 {
            let k = (W * 0.30) / codeA.extent.width, x = W * 0.03 - (1 - easeOutBack(wa)) * W * 0.2
            put(alpha(codeA, wa), CGAffineTransform(translationX: x, y: H * 0.74 - codeA.extent.height * k).scaledBy(x: k, y: k))
        }
        if wb > 0 {
            let k = (W * 0.26) / codeB.extent.width, x = W * 0.97 - codeB.extent.width * k + (1 - easeOutBack(wb)) * W * 0.2
            put(alpha(codeB, wb), CGAffineTransform(translationX: x, y: H * 0.74 - codeB.extent.height * k).scaledBy(x: k, y: k))
        }
        // terminale che digita, in una finestra
        let maxW = lines.map { $0.w }.max() ?? 1
        let tk = (W * 0.40) / maxW, lineH = (lines.first?.h ?? 40) * tk * 1.18
        let x0 = W * 0.04, top = H * 0.30
        let panelH = lineH * Double(lines.count) + lineH * 1.5 + 14 * sc
        let panel = CGRect(x: x0 - 18 * sc, y: top - lineH * Double(lines.count - 1) - lineH * 0.55, width: maxW * tk + 40 * sc, height: panelH)
        if t > 0.8 { gfx = alpha(chrome(Int(panel.width), Int(panel.height)), clamp((t - 0.8) / 0.3)).transformed(by: CGAffineTransform(translationX: panel.minX, y: panel.minY)).composited(over: gfx) }
        for (i, ln) in lines.enumerated() {
            let n = Int(max(0, t - DEV_STARTS[i]) * DEV_CPS)
            if n <= 0 { continue }
            let len = DEV_LINES[i].count, typed = min(n, len)
            let frac = Double(typed) / Double(len)
            let y = top - Double(i) * lineH
            put(ln.img.cropped(to: CGRect(x: 0, y: 0, width: 24 + ln.w * frac, height: ln.img.extent.height)), CGAffineTransform(translationX: x0 - 24 * tk, y: y).scaledBy(x: tk, y: tk))
            if typed < len || i == lines.count - 1, Int(t * 3) % 2 == 0 {
                let cw = ln.w / Double(len) * tk, cx = x0 + ln.w * frac * tk
                gfx = CIImage(color: CIColor(red: 0.5, green: 1, blue: 0.9, alpha: 0.95)).cropped(to: CGRect(x: cx, y: y + 6 * tk, width: cw, height: ln.h * tk * 0.78)).composited(over: gfx)
            }
        }
        // titolo al neon con scintille
        let tu = clamp((t - 3.0) / 0.4)
        if tu > 0 {
            let kk = (W * 0.62) / title.w * max(easeOutBack(tu), 0.01)
            let flick = t < 3.7 ? 0.82 + 0.18 * sin(t * 47) : 1.0
            put(alpha(title.img, flick), CGAffineTransform(translationX: W / 2, y: H * 0.905).scaledBy(x: kk, y: kk).translatedBy(x: -title.img.extent.width / 2, y: -title.img.extent.height / 2))
            let su = clamp((t - 3.35) / 0.4)
            if su > 0 {
                let sk = (W * 0.44) / subtitle.w
                put(alpha(subtitle.img, su), CGAffineTransform(translationX: W / 2, y: H * 0.815).scaledBy(x: sk, y: sk).translatedBy(x: -subtitle.img.extent.width / 2, y: -subtitle.img.extent.height / 2))
            }
            var r = LCG(s: 31)
            let pal: [CIColor] = [CIColor(red: 0.4, green: 1, blue: 0.95, alpha: 1), CIColor(red: 1, green: 0.4, blue: 0.9, alpha: 1), CIColor(red: 0.6, green: 1, blue: 0.4, alpha: 1), CIColor(red: 1, green: 1, blue: 1, alpha: 1)]
            for i in 0..<44 {
                let age = t - 3.0 - r.next() * 0.1, ang = r.next() * 2 * .pi, spd = (140 + r.next() * 420) * sc, size = (5 + r.next() * 9) * sc
                guard age > 0, age < 1.1 else { continue }
                let px = W / 2 + cos(ang) * spd * age * 1.4, py = H * 0.905 + sin(ang) * spd * age * 0.7 - 120 * sc * age * age
                let a = (1 - age / 1.1)
                gfx = CIImage(color: CIColor(red: pal[i % 4].red, green: pal[i % 4].green, blue: pal[i % 4].blue, alpha: CGFloat(a))).cropped(to: CGRect(x: px, y: py, width: size, height: size)).composited(over: gfx)
            }
        }
        if flipText { gfx = gfx.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: W, ty: 0)) }
        out = gfx.composited(over: out)

        // ── 3) lampo d'inizio e dissolvenza finale verso il video dal vivo ──
        let fl = clamp(1 - t / 0.2) * 0.9
        if fl > 0.02 { out = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: CGFloat(fl))).cropped(to: ext).composited(over: out) }
        let fade = clamp((t - (Dev.length - 0.4)) / 0.4)
        if fade > 0 { out = alpha(out, 1 - fade).composited(over: live) }
        return out.cropped(to: ext)
    }
}

// MARK: - Contatore dei caffè (in alto a destra, nel video)

final class CoffeeOverlay {
    var count = 0                       // solo camQueue
    var eventAt: TimeInterval?          // solo camQueue: istante dell'ultimo caffè
    static let length = 3.4
    private var cache: [Int: CIImage] = [:]
    private func pill(_ n: Int) -> CIImage {
        if let b = cache[n] { return b }
        let b = Props.pill("☕ Caffè bevuto!  ·  n. \(n)", width: n >= 10 ? 980 : 940, height: 120, fontSize: 62); cache[n] = b; return b
    }
    /// Compare SOLO quando si beve un altro caffè (entra da destra, resta, esce): non resta sempre in vista.
    func visible(now: TimeInterval) -> Bool { eventAt.map { now - $0 < CoffeeOverlay.length } ?? false }

    func apply(_ img: CIImage, now: TimeInterval, flip: Bool = false) -> CIImage {
        guard visible(now: now), let d = eventAt.map({ now - $0 }) else { return img }
        let ext = img.extent, W = Double(ext.width), H = Double(ext.height)
        let p = pill(max(count, 1))
        let ph = H * 0.075, margin = W * 0.022
        let k = ph / Double(p.extent.height), pw = Double(p.extent.width) * k
        let pin = easeOutBack(clamp(d / 0.35)), pout = clamp((d - (CoffeeOverlay.length - 0.5)) / 0.5)
        let pulse = d < 0.5 ? 1 + 0.12 * (1 - d / 0.5) : 1.0                            // piccolo impulso all'arrivo
        let slide = (1 - pin + pout) * (pw + margin * 2)
        let x0 = W - margin - pw + slide
        let tf = flip ? CGAffineTransform(translationX: x0 + pw, y: H - margin - ph * pulse).scaledBy(x: -k * pulse, y: k * pulse)
                      : CGAffineTransform(translationX: x0, y: H - margin - ph * pulse).scaledBy(x: k * pulse, y: k * pulse)
        let img2 = p.transformed(by: tf).applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(1 - pout))])
        return img2.composited(over: img).cropped(to: ext)
    }
}

// MARK: - Prova dell'effetto senza camera: kakashi demo <cartella>

func runDemo(_ dir: String) {
    let W = 1280, H = 720
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    func person(_ px: Double) -> (ellipse: CGRect, head: CGRect) {
        (CGRect(x: px - 150, y: 30, width: 300, height: 560), CGRect(x: px - 80, y: 540, width: 160, height: 160))
    }
    func scene(_ px: Double) -> CIImage {
        let c = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        if env["KAKASHI_SCENE"] == "stanza" {   // parete morbida, mensole, quadri: più vicina a una stanza vera
            let g2 = CGGradient(colorsSpace: cs, colors: [CGColor(red: 0.63, green: 0.58, blue: 0.52, alpha: 1), CGColor(red: 0.72, green: 0.67, blue: 0.60, alpha: 1)] as CFArray, locations: [0, 1])!
            c.drawLinearGradient(g2, start: CGPoint(x: 0, y: CGFloat(H)), end: CGPoint(x: CGFloat(W), y: 0), options: [])
            c.setFillColor(CGColor(red: 0.30, green: 0.22, blue: 0.16, alpha: 1))
            for y in [190, 380] { c.fill(CGRect(x: 0, y: y, width: W, height: 16)) }
            for (x, y, col) in [(150, 420, (0.2, 0.35, 0.5)), (980, 420, (0.55, 0.25, 0.2)), (330, 215, (0.25, 0.45, 0.3)), (880, 215, (0.6, 0.5, 0.2))] {
                c.setFillColor(CGColor(red: col.0, green: col.1, blue: col.2, alpha: 1)); c.fill(CGRect(x: x, y: y, width: 150, height: 120))
            }
        } else {
        let grad = CGGradient(colorsSpace: cs, colors: [CGColor(red: 0.25, green: 0.45, blue: 0.7, alpha: 1), CGColor(red: 0.85, green: 0.8, blue: 0.6, alpha: 1)] as CFArray, locations: [0, 1])!
        c.drawLinearGradient(grad, start: CGPoint(x: 0, y: CGFloat(H)), end: CGPoint(x: CGFloat(W), y: 0), options: [])
        c.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.5)); c.setLineWidth(3)
        for x in stride(from: 0, to: W, by: 80) { c.move(to: CGPoint(x: x, y: 0)); c.addLine(to: CGPoint(x: x, y: H)) }
        for y in stride(from: 0, to: H, by: 80) { c.move(to: CGPoint(x: 0, y: y)); c.addLine(to: CGPoint(x: W, y: y)) }
        c.strokePath()
        }
        c.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1)); c.fillEllipse(in: CGRect(x: 560, y: 360, width: 160, height: 160))
        c.setFillColor(CGColor(red: 0.95, green: 0.55, blue: 0.1, alpha: 1))
        let p = person(px); c.fillEllipse(in: p.ellipse); c.fillEllipse(in: p.head)
        return CIImage(cgImage: c.makeImage()!)
    }
    func maskBuf(_ px: Double) -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, 320, 180, kCVPixelFormatType_OneComponent8, nil, &pb)
        let b = pb!
        CVPixelBufferLockBaseAddress(b, [])
        let base = CVPixelBufferGetBaseAddress(b)!, bpr = CVPixelBufferGetBytesPerRow(b)
        let p = person(px)
        for j in 0..<180 { for i in 0..<320 {
            let x = (Double(i) + 0.5) * 4, y = (180 - Double(j) - 0.5) * 4
            func inside(_ r: CGRect) -> Bool { let dx = (x - Double(r.midX)) / Double(r.width / 2), dy = (y - Double(r.midY)) / Double(r.height / 2); return dx * dx + dy * dy <= 1 }
            base.advanced(by: j * bpr).assumingMemoryBound(to: UInt8.self)[i] = (inside(p.ellipse) || inside(p.head)) ? 255 : 0
        } }
        CVPixelBufferUnlockBaseAddress(b, [])
        return b
    }
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for (name, learnFrom) in [("plate", [300.0, 980.0, 640.0]), ("inpaint", [640.0])] {
        let v = Vanish()
        var last = scene(640)
        for px in learnFrom { last = scene(px); v.ingest(frame: last, mask: maskBuf(px), learn: true) }
        for (i, t) in [0.0, 0.2, 0.4, 0.6, 0.9, 1.4, 2.0, 2.5, 3.2].enumerated() {
            let out = v.render(last, t: t)
            try? v.ctx.writePNGRepresentation(of: out, to: URL(fileURLWithPath: "\(dir)/\(name)-\(i).png"), format: .RGBA8, colorSpace: cs)
        }
    }
    // "Real Stoner" su un volto finto (la testa della scena di prova)
    let base = Vanish(), st = Stoner(ctx: base.ctx, srgb: base.srgb)
    let fw = 1280.0, fh = 720.0
    st.begin(face: FaceGeom(eyeL: CGPoint(x: 606 / fw, y: 640 / fh), eyeR: CGPoint(x: 674 / fw, y: 640 / fh), mouth: CGPoint(x: 640 / fw, y: 585 / fh), mouthW: 60 / fw, faceW: 160 / fw))
    let still = scene(640)
    for (i, t) in [0.3, 1.0, 1.4, 1.9, 2.6, 3.2, 4.0, 4.8, 5.4, 5.7].enumerated() {
        try? st.ctx.writePNGRepresentation(of: st.render(still, t: t), to: URL(fileURLWithPath: "\(dir)/stoner-\(i).png"), format: .RGBA8, colorSpace: cs)
    }
    let stL = Stoner(ctx: base.ctx, srgb: base.srgb)   // joint dal lato sinistro (mano a sinistra)
    stL.begin(face: FaceGeom(eyeL: CGPoint(x: 606 / fw, y: 640 / fh), eyeR: CGPoint(x: 674 / fw, y: 640 / fh), mouth: CGPoint(x: 640 / fw, y: 585 / fh), mouthW: 60 / fw, faceW: 160 / fw), side: -1)
    for (i, t) in [2.6, 4.0].enumerated() {
        try? stL.ctx.writePNGRepresentation(of: stL.render(still, t: t), to: URL(fileURLWithPath: "\(dir)/stonerL-\(i).png"), format: .RGBA8, colorSpace: cs)
    }
    let zm = Zoom(); zm.center = CGPoint(x: 640 / fw, y: 620 / fh)
    for (i, t) in [0.1, 0.3, 1.0, 1.9, 2.3].enumerated() {
        try? base.ctx.writePNGRepresentation(of: zm.render(still, t: t), to: URL(fileURLWithPath: "\(dir)/zoom-\(i).png"), format: .RGBA8, colorSpace: cs)
    }
    let dv = Dev(ctx: base.ctx, srgb: base.srgb)
    dv.begin(face: FaceGeom(eyeL: CGPoint(x: 606 / fw, y: 640 / fh), eyeR: CGPoint(x: 674 / fw, y: 640 / fh), mouth: CGPoint(x: 640 / fw, y: 585 / fh), mouthW: 60 / fw, faceW: 160 / fw, center: CGPoint(x: 640 / fw, y: 620 / fh)))
    for (i, t) in [0.15, 0.55, 0.9, 1.6, 2.4, 3.3, 3.9, 4.45].enumerated() {
        try? dv.ctx.writePNGRepresentation(of: dv.render(still, t: t), to: URL(fileURLWithPath: "\(dir)/dev-\(i).png"), format: .RGBA8, colorSpace: cs)
    }
    let cf = CoffeeOverlay(); cf.count = 3; cf.eventAt = 10
    for (i, t) in [10.1, 10.8, 12.0, 13.6].enumerated() {
        try? base.ctx.writePNGRepresentation(of: cf.apply(still, now: t), to: URL(fileURLWithPath: "\(dir)/coffee-\(i).png"), format: .RGBA8, colorSpace: cs)
    }
    Sfx.writeWavs(to: dir)
    print("Fotogrammi e suoni scritti in \(dir)")
}

// MARK: - Finestrella sempre in primo piano (specchio con le mani)

final class Overlay {
    let panel: NSPanel
    let video = CALayer()
    let dots = CAShapeLayer()
    let bar = CALayer()
    let label = CATextLayer()
    let coffeeLabel = CATextLayer()
    let size = NSSize(width: 256, height: 144)
    var resetText: DispatchWorkItem?
    var lastText = ""
    static let idleText = "✊✊ → ✋✋   pugni al centro, poi apri"

    init() {
        let scr = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let m: CGFloat = 16
        let pos = env["KAKASHI_POS"] ?? "br"
        let x = pos.hasSuffix("l") ? scr.minX + m : scr.maxX - size.width - m
        let y = pos.hasPrefix("t") ? scr.maxY - size.height - m : scr.minY + m
        panel = NSPanel(contentRect: NSRect(origin: NSPoint(x: x, y: y), size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .screenSaver                       // sopra tutto, anche le app a schermo intero
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true                  // non intralcia i click
        panel.sharingType = .none

        let view = NSView(frame: NSRect(origin: .zero, size: size))
        view.wantsLayer = true
        let root = view.layer!
        root.cornerRadius = 12
        root.masksToBounds = true
        root.backgroundColor = NSColor.black.cgColor
        root.borderWidth = 2
        root.borderColor = NSColor(white: 1, alpha: 0.35).cgColor

        video.frame = view.bounds
        video.contentsGravity = .resizeAspectFill
        video.transform = CATransform3DMakeScale(-1, 1, 1)   // specchio, come una selfie-cam
        root.addSublayer(video)

        dots.frame = view.bounds
        dots.fillColor = NSColor.white.cgColor
        root.addSublayer(dots)

        let shade = CALayer()
        shade.frame = NSRect(x: 0, y: 0, width: size.width, height: 28)
        shade.backgroundColor = NSColor(white: 0, alpha: 0.6).cgColor
        root.addSublayer(shade)

        bar.backgroundColor = NSColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1).cgColor
        bar.frame = NSRect(x: 0, y: 0, width: 0, height: 3)
        root.addSublayer(bar)

        label.frame = NSRect(x: 4, y: 6, width: size.width - 8, height: 16)
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.fontSize = 11
        label.alignmentMode = .center
        label.foregroundColor = NSColor.white.cgColor
        label.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        root.addSublayer(label)
        coffeeLabel.frame = NSRect(x: size.width - 74, y: size.height - 26, width: 68, height: 20)
        coffeeLabel.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        coffeeLabel.fontSize = 13
        coffeeLabel.alignmentMode = .center
        coffeeLabel.foregroundColor = NSColor(red: 1, green: 0.95, blue: 0.85, alpha: 1).cgColor
        coffeeLabel.backgroundColor = NSColor(red: 0.14, green: 0.09, blue: 0.06, alpha: 0.85).cgColor
        coffeeLabel.cornerRadius = 10
        coffeeLabel.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        coffeeLabel.isHidden = true
        root.addSublayer(coffeeLabel)
        setText(Overlay.idleText)

        panel.contentView = view
        panel.orderFrontRegardless()
    }

    func setText(_ s: String) { if s != lastText { lastText = s; label.string = s } }

    var coffeeHide: DispatchWorkItem?
    /// Il contatore compare solo per qualche secondo a ogni nuovo caffè (poi sparisce).
    func showCoffee(_ n: Int) {
        coffeeLabel.string = "☕ n. \(n)"; coffeeLabel.isHidden = false
        coffeeHide?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.coffeeLabel.isHidden = true }
        coffeeHide = w
        DispatchQueue.main.asyncAfter(deadline: .now() + CoffeeOverlay.length, execute: w)
    }

    func show(_ img: CGImage) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        video.contents = img
        CATransaction.commit()
    }

    func flash(_ text: String) {
        setText(text)
        resetText?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.setText(Overlay.idleText) }
        resetText = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: w)
    }

    func update(hands: [Hand], aspect: Double, pose: Pose, phase: Phase, showingResult: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let path = CGMutablePath()
        // Il video riempie la finestrella (aspect-fill) ed è specchiato; Vision ha l'origine in basso a sinistra.
        let w = Double(size.width), hgt = Double(size.height)
        let scale = max(w / aspect, hgt)
        let dispW = scale * aspect, dispH = scale
        for h in hands {
            for (_, p) in h {
                let x = (1 - Double(p.x)) * dispW - (dispW - w) / 2
                let y = Double(p.y) * dispH - (dispH - hgt) / 2
                path.addEllipse(in: CGRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5))
            }
        }
        dots.path = path
        dots.fillColor = (pose == .none ? NSColor.white : NSColor.systemGreen).cgColor
        var frac = 0.0, border = NSColor(white: 1, alpha: 0.35), text: String?
        switch phase {
        case .idle: break
        case .arming(let p): frac = p * 0.5; border = NSColor.systemYellow; text = "✊✊ …"
        case .armed(let left): frac = left; border = NSColor(red: 0.9, green: 0.15, blue: 0.15, alpha: 1); text = "✊✊ pronto: apri le mani!"
        }
        bar.frame = NSRect(x: 0, y: 0, width: size.width * CGFloat(frac), height: 3)
        panel.contentView?.layer?.borderColor = border.cgColor
        if !showingResult { setText(text ?? Overlay.idleText) }
        CATransaction.commit()
    }
}

/// Finestra col video elaborato (quello che vede la call): OBS la cattura come sorgente "Cattura finestra".
final class VideoWindow {
    let win: NSWindow
    let layer = CALayer()
    init() {
        let scr = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        win = NSWindow(contentRect: NSRect(x: scr.minX + 24, y: scr.minY + 24, width: 960, height: 540),
                       styleMask: [.borderless], backing: .buffered, defer: false)
        win.backgroundColor = .black
        win.hasShadow = false
        win.title = "Kakashi Video"
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        win.ignoresMouseEvents = true
        win.canHide = false
        // OBS elenca solo le finestre a livello normale e le cattura in modo affidabile se stanno sullo schermo: quindi livello normale,
        // sullo schermo, ma dietro a tutte le altre finestre (si vede solo con la scrivania libera).
        // KAKASHI_VIDEO=front la porta davanti; KAKASHI_VIDEO=hide la sposta fuori schermo (la cattura può non funzionare).
        win.level = .normal
        let frames = NSScreen.screens.map { $0.frame }
        let all = frames.dropFirst().reduce(frames.first ?? scr) { $0.union($1) }
        win.setFrameOrigin(env["KAKASHI_VIDEO"] == "hide" ? NSPoint(x: all.minX - 960 + 3, y: all.minY - 540 + 3)
                                                          : NSPoint(x: scr.minX + 24, y: scr.minY + 24))
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 960, height: 540))
        v.wantsLayer = true
        v.layer!.backgroundColor = NSColor.black.cgColor
        layer.frame = v.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer.contentsGravity = .resizeAspect
        v.layer!.addSublayer(layer)
        win.contentView = v
        if env["KAKASHI_VIDEO"] != "0" { win.orderFrontRegardless(); if env["KAKASHI_VIDEO"] != "front" { win.orderBack(nil) } }
    }
    func show(_ img: CGImage) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.contents = img
        CATransaction.commit()
    }
}

// MARK: - Controller: camera → (mani, persona) → gesto → effetto → uscita

final class Flag {
    private var v = false
    private let l = NSLock()
    func tryAcquire() -> Bool { l.lock(); defer { l.unlock() }; if v { return false }; v = true; return true }
    func release() { l.lock(); v = false; l.unlock() }
}

final class Controller: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    let handReq = VNDetectHumanHandPoseRequest()
    let segReq = VNGeneratePersonSegmentationRequest()
    let faceReq = VNDetectFaceLandmarksRequest()
    let camQueue = DispatchQueue(label: "kakashi.cam")
    let handQueue = DispatchQueue(label: "kakashi.hand")
    let segQueue = DispatchQueue(label: "kakashi.seg")
    let handFlag = Flag(), segFlag = Flag()
    let vanish = Vanish()
    lazy var stoner = Stoner(ctx: vanish.ctx, srgb: vanish.srgb)
    var overlay: Overlay!
    var videoWin: VideoWindow!
    var seq = SeqTracker()                       // solo main
    var smokeTracker = EdgeTracker(hold: SMOKE_HOLD)   // solo main
    var browTracker = EdgeTracker(hold: BROW_HOLD)     // solo main
    var browBase = BrowBaseline()                // solo main
    var zoomUntil: TimeInterval = 0              // solo main
    var zoomStart: TimeInterval?                 // solo camQueue
    let zoom = Zoom()
    lazy var dev = Dev(ctx: vanish.ctx, srgb: vanish.srgb)
    let coffeeOverlay = CoffeeOverlay()
    lazy var sfx = Sfx()
    var devStart: TimeInterval?                   // solo camQueue
    var eyesTracker = EdgeTracker(hold: 0.5)      // solo main: due mani vicino agli occhi
    var drinkTracker = DrinkTracker()             // solo main
    var lastCoffeeAt: TimeInterval = -1000        // solo main
    var lastFaceH: (g: FaceGeom, t: TimeInterval)?   // solo handQueue
    var coffeeCount = 0                           // solo main
    var coffeeDay = CoffeeStore.today()           // solo main
    var wasArmed = false                          // solo main
    var smokeSide = 1.0                           // solo main: lato della mano rispetto alla bocca
    var lastFace: (geom: FaceGeom, at: TimeInterval)?   // solo main
    var stonerStart: TimeInterval?               // solo camQueue
    var cooldownUntil: TimeInterval = 0          // solo main
    var resultUntil: TimeInterval = 0            // solo main
    var effectStart: TimeInterval?               // solo camQueue
    var lastHand = 0.0, lastSeg = 0.0            // solo camQueue

    func pickCamera() -> AVCaptureDevice? {
        let all = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                                   mediaType: .video, position: .unspecified).devices
        log("Camere: " + all.map { $0.localizedName }.joined(separator: " | "))
        if let want = env["KAKASHI_CAMERA"]?.lowercased(),
           let d = all.first(where: { $0.localizedName.lowercased().contains(want) }) { return d }
        // Prima l'iPhone (Continuity), poi le camere esterne, poi la webcam integrata.
        if let d = all.first(where: { $0.deviceType == .continuityCamera || $0.localizedName.contains("iPhone") }) { return d }
        if let d = all.first(where: { $0.deviceType == .external }) { return d }
        if let d = all.first(where: { $0.deviceType == .builtInWideAngleCamera }) { return d }
        return all.first ?? AVCaptureDevice.default(for: .video)
    }

    func start() {
        guard let cam = pickCamera(), let input = try? AVCaptureDeviceInput(device: cam) else {
            log("Nessuna webcam trovata."); exit(1)
        }
        session.beginConfiguration()
        session.sessionPreset = session.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .vga640x480
        if session.canAddInput(input) { session.addInput(input) }
        let out = AVCaptureVideoDataOutput()
        out.alwaysDiscardsLateVideoFrames = true
        out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        out.setSampleBufferDelegate(self, queue: camQueue)
        if session.canAddOutput(out) { session.addOutput(out) }
        session.commitConfiguration()
        handReq.maximumHandCount = 2
        segReq.qualityLevel = .balanced
        segReq.outputPixelFormat = kCVPixelFormatType_OneComponent8
        overlay = Overlay()
        videoWin = VideoWindow()
        coffeeCount = CoffeeStore.load()
        let c0 = coffeeCount
        camQueue.async { self.coffeeOverlay.count = c0 }
        log("Finestra video: \(videoWin.win.windowNumber)")   // il launcher la passa a OBS
        session.startRunning()
        log("Kakashi attivo sulla camera «\(cam.localizedName)»\(DRY ? " (modalità prova: non chiude niente)" : "")\(FX ? "" : " (senza effetto fumo)").")
    }

    func denied() {
        log("Accesso alla camera negato: consentilo a Kakashi in Impostazioni di Sistema > Privacy e sicurezza > Fotocamera.")
        exit(1)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sb: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        let t = ProcessInfo.processInfo.systemUptime
        let aspect = Double(CVPixelBufferGetWidth(pb)) / Double(CVPixelBufferGetHeight(pb))
        let frame = CIImage(cvPixelBuffer: pb)

        var et: Double?
        if let s = effectStart {
            let e = t - s
            if e < Vanish.length { et = e } else { effectStart = nil; vanish.reset() }
        }
        // mani: ~10 analisi al secondo
        if t - lastHand >= 0.09, handFlag.tryAcquire() {
            lastHand = t
            handQueue.async { self.analyzeHands(pb, aspect: aspect, t: t); self.handFlag.release() }
        }
        // persona: 2 al secondo a riposo (serve a imparare lo sfondo), a ogni occasione durante l'effetto
        if FX, t - lastSeg >= (et != nil ? 0 : 0.5), segFlag.tryAcquire() {
            lastSeg = t
            let learn = et == nil
            segQueue.async { self.segment(frame, pb, learn: learn); self.segFlag.release() }
        }
        var zt: Double?
        if let s = zoomStart {
            let e = t - s
            if e < Zoom.length { zt = e } else { zoomStart = nil }
        }
        var dt: Double?
        if let s = devStart {
            let e = t - s
            if e < Dev.length { dt = e } else { devStart = nil }
        }
        var st: Double?
        if let s = stonerStart {
            let e = t - s
            if e < Stoner.length { st = e } else { stonerStart = nil }
        }
        let fx: CIImage = st != nil ? stoner.render(frame, t: st!, flipText: FLIP_TEXT)
            : (dt != nil ? dev.render(frame, t: dt!, flipText: FLIP_TEXT)
            : (zt != nil ? zoom.render(frame, t: zt!)
            : (et != nil ? vanish.render(frame, t: et!) : frame)))
        let callImg = coffeeOverlay.apply(fx, now: t, flip: FLIP_TEXT)                  // contatore dei caffè in alto a destra, nel video
        guard let cg = vanish.ctx.createCGImage(callImg, from: frame.extent, format: .RGBA8, colorSpace: vanish.srgb) else { return }
        // la finestrella è uno specchio: i testi degli effetti si preparano rovesciati, e il contatore ha il suo (in CALayer)
        var panelImg: CIImage?
        if let st = st { panelImg = stoner.render(frame, t: st, flipText: true) }
        else if let dt = dt { panelImg = dev.render(frame, t: dt, flipText: true) }
        else if coffeeOverlay.visible(now: t) { panelImg = fx }
        var cgPanel = cg
        if let pi = panelImg, let p = vanish.ctx.createCGImage(pi, from: frame.extent, format: .RGBA8, colorSpace: vanish.srgb) { cgPanel = p }
        DispatchQueue.main.async { self.overlay.show(cgPanel); self.videoWin.show(cg) }
    }

    func segment(_ frame: CIImage, _ pb: CVPixelBuffer, learn: Bool) {
        try? VNImageRequestHandler(cvPixelBuffer: pb, orientation: .up).perform([segReq])
        guard let m = segReq.results?.first?.pixelBuffer else { return }
        vanish.ingest(frame: frame, mask: m, learn: learn)
    }

    /// Dove sono le mani rispetto al volto, per i gesti di occhiali (due mani vicino agli occhi) e bere (pugno vicino alla bocca).
    /// Con la mano davanti alla faccia il volto può sparire un attimo: si usa l'ultimo visto (1,2 s).
    func handHints(face seen: FaceGeom?, hands: [Hand], aspect: Double, t: TimeInterval) -> HandHints {
        if let f = seen { lastFaceH = (f, t) }
        guard let f = seen ?? lastFaceH.flatMap({ t - $0.t < 1.2 ? $0.g : nil }) else { return HandHints() }
        return HandHints(bothEyes: bothHandsNearEyes(hands, face: f, aspect: aspect), fist: fistToMouth(hands, face: f, aspect: aspect))
    }

    func analyzeHands(_ pb: CVPixelBuffer, aspect: Double, t: TimeInterval) {
        try? VNImageRequestHandler(cvPixelBuffer: pb, orientation: .up).perform([handReq, faceReq])
        var face: FaceGeom?
        if let o = (faceReq.results ?? []).max(by: { $0.boundingBox.width < $1.boundingBox.width }) { face = faceGeom(o) }
        var hands: [Hand] = []
        for obs in handReq.results ?? [] {
            guard let pts = try? obs.recognizedPoints(.all) else { continue }
            var h = Hand()
            for (k, v) in pts where v.confidence > CONF { h[k] = v.location }
            hands.append(h)
        }
        let hints = handHints(face: face, hands: hands, aspect: aspect, t: t)
        DispatchQueue.main.async { self.handle(hands, face: face, hints: hints, aspect: aspect, now: t) }
    }

    func startDev(now: TimeInterval) {
        guard now >= cooldownUntil else { return }
        cooldownUntil = now + Dev.length + 3
        resultUntil = now + 3
        seq.reset(); smokeTracker.reset(); browTracker.reset()
        log("🤓 developer")
        overlay.flash("🤓 developer")
        sfx.play("dev")
        let fg = lastFace?.geom
        camQueue.async { self.dev.begin(face: fg); self.devStart = ProcessInfo.processInfo.systemUptime }
    }

    func registerCoffee(now: TimeInterval) {
        guard now - lastCoffeeAt > 8 else { return }           // un caffè ogni 8 s al massimo
        lastCoffeeAt = now
        if coffeeDay != CoffeeStore.today() { coffeeDay = CoffeeStore.today(); coffeeCount = 0 }   // a mezzanotte si riparte da zero
        coffeeCount += 1
        CoffeeStore.save(coffeeCount)
        log("☕ caffè n. \(coffeeCount)")
        overlay.showCoffee(coffeeCount)
        sfx.play("coffee")
        let c = coffeeCount
        camQueue.async { self.coffeeOverlay.count = c; self.coffeeOverlay.eventAt = ProcessInfo.processInfo.systemUptime }
    }

    func handle(_ raw: [Hand], face seen: FaceGeom?, hints: HandHints, aspect: Double, now: TimeInterval) {
        // occhiali: entrambe le mani (a "C") vicino agli occhi, una per lato, per mezzo secondo
        if eyesTracker.update(ok: hints.bothEyes, now: now) { startDev(now: now) }
        // bere: un pugno che si avvicina alla bocca
        let drink = drinkTracker.update(d: hints.fist, now: now)
        if DEBUG, hints.fist != nil || hints.bothEyes { log("   " + drink.why + (hints.bothEyes ? "  |  occhi: due mani vicino agli occhi" : "")) }
        if drink.fire { registerCoffee(now: now) }
        let iso = raw.map { h in h.mapValues { CGPoint(x: $0.x * CGFloat(aspect), y: $0.y) } }
        let (pose, why) = classify(iso, aspect: aspect)
        var step = seq.update(pose, now: now)
        if now < cooldownUntil { seq.reset(); step = (.idle, false) }
        if DEBUG { log(String(format: "mani:%d  %@", raw.count, why)) }
        overlay.update(hands: raw, aspect: aspect, pose: pose, phase: step.phase, showingResult: now < resultUntil)
        // due dita alla bocca → "Real Stoner". Con la mano davanti alla faccia il volto può sparire un attimo: si usa l'ultimo visto.
        if let f = seen { lastFace = (f, now) }
        let face = seen ?? (lastFace.flatMap { now - $0.at < 1.2 ? $0.geom : nil })
        let smoke = smokeGesture(raw, face: face, aspect: aspect)
        if smoke.ok { smokeSide = smoke.side }
        if DEBUG, face != nil { log("   " + smoke.why) }
        let smokeFire = smokeTracker.update(ok: smoke.ok, now: now)
        if smokeFire, !step.fire, now >= cooldownUntil, let f = face {
            cooldownUntil = now + Stoner.length + 3
            resultUntil = now + 4
            seq.reset()
            log("🚬 real stoner")
            overlay.flash("🚬 real stoner")
            sfx.play("stoner")
            let sd = smokeSide
            camQueue.async { self.stoner.begin(face: f, side: sd); self.stonerStart = ProcessInfo.processInfo.systemUptime }
            return
        }
        // sopracciglio abbassato + testa storta → zoom sul volto (con la linea di base appresa a riposo)
        if let f = seen {
            let brow = browGesture(f, aspect: aspect, base: &browBase)
            if DEBUG { log("   " + brow.why) }
            if now < zoomUntil { let c = f.center; camQueue.async { self.zoom.center = c } }   // il volto si segue mentre si muove
            let browFire = browTracker.update(ok: brow.ok, now: now)
            if browFire, !step.fire, now >= cooldownUntil {
                cooldownUntil = now + Zoom.length + 2.5
                zoomUntil = now + Zoom.length
                resultUntil = now + 3
                seq.reset(); smokeTracker.reset()
                log("🤨 zoom")
                overlay.flash("🤨 zoom")
                sfx.play("zoom")
                let c = f.center
                camQueue.async { self.zoom.center = c; self.zoomStart = ProcessInfo.processInfo.systemUptime }
                return
            }
        }
        guard step.fire else { return }
        cooldownUntil = now + COOLDOWN + Vanish.length
        resultUntil = now + 4
        log("✊✊ → ✋✋  sbuffo!")
        if FX {
            overlay.flash("💨 sbuffo!")
            sfx.play("puff")
            camQueue.async { self.vanish.reset(); self.effectStart = ProcessInfo.processInfo.systemUptime }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) { self.overlay.flash("💨 " + leaveCalls()) }
        } else {
            overlay.flash("💨 " + leaveCalls())
        }
    }
}

// MARK: - Avvio

let args = CommandLine.arguments
if args.contains("selftest") { exit(selfTest()) }
if let i = args.firstIndex(of: "demo") { runDemo(i + 1 < args.count ? args[i + 1] : "/tmp/kakashi-demo"); exit(0) }
loadExtraConfig()
signal(SIGTERM) { _ in exit(0) }
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = Controller()
AVCaptureDevice.requestAccess(for: .video) { granted in
    DispatchQueue.main.async { granted ? controller.start() : controller.denied() }
}
app.run()
