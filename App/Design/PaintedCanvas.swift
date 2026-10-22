import SwiftUI

/// Grisaille zemin: yalnızca gri tonlarla, yağlı boya fırça darbeleriyle boyanmış bir tuval (ADR-0004 kural 9).
///
/// Neden: düz zemin üstündeki `Glass.clear` kıracak bir şey bulamadığı için görünmüyordu; dokulu ama renksiz bir resim
/// cama gerçek bir kırılma yüzeyi verir ve "AI renkleri yok" kuralını bozmaz. Merkez sakin (okunurluk), hareket kenarlarda.
///
/// Performans: tuval tema başına bir kez, deterministik olarak çizilip `NSImage` olarak önbelleğe alınır; ekranda yalnızca
/// statik bir görüntü vardır, animasyon yoktur. Böylece glass her karede değişen bir zemini yeniden örneklemez.
struct PaintedCanvas: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.backgroundTop, Theme.backgroundBottom], startPoint: .top, endPoint: .bottom)
            if let image, contrast != .increased, !reduceTransparency {
                // Görüntünün kendi boyutu (1600 pt) yerleşime girmesin: alan `Color.clear` ile belirlenir, resim taşar ve kırpılır.
                Color.clear
                    .overlay {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                    }
                    .clipped()
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .task(id: colorScheme) {
            let palette = Grisaille(dark: colorScheme == .dark)
            image = PaintedCanvasCache.image(for: palette)
        }
    }
}

/// Tema başına tek görüntü; uygulama ömrü boyunca tutulur (1600×1000 pt, 2x → ~2 × 25 MB).
@MainActor
enum PaintedCanvasCache {
    private static var images: [Bool: NSImage] = [:]
    // Tipik pencere boyutunda (pt) çizilir ki fırça darbeleri ekranda tasarlandığı ölçekte kalsın.
    static let size = CGSize(width: 1600, height: 1000)

    static func image(for palette: Grisaille) -> NSImage? {
        if let cached = images[palette.dark] { return cached }
        let renderer = ImageRenderer(content: GrisaillePainting(palette: palette).frame(width: size.width, height: size.height))
        renderer.scale = 2
        renderer.isOpaque = true
        let image = renderer.nsImage
        images[palette.dark] = image
        return image
    }
}

/// Pigment değerleri: koyuda fildişi siyahı → kemik grisi, açıkta astar beyazı → sıcak gri. Doygunluk ≈ 0;
/// yalnızca çok hafif bir umbra sıcaklığı (yağlı boya hissi için) var.
struct Grisaille {
    let dark: Bool

    var ground: Color { dark ? Color(white: 0.035) : Color(red: 0.925, green: 0.918, blue: 0.905) }

    /// `value` 0…1: tonun zemin etrafındaki konumu. Koyuda yalnızca yukarı (daha açık), açıkta iki yöne.
    func paint(_ value: Double, alpha: Double) -> Color {
        if dark {
            let v = 0.035 + value * 0.13
            return Color(red: v * 1.03, green: v, blue: v * 0.96).opacity(alpha)
        }
        let v = 0.80 + value * 0.20
        return Color(red: min(1, v * 1.008), green: v, blue: v * 0.985).opacity(alpha)
    }

    /// İmpasto sırtının ışık ve gölge kenarı.
    var highlight: Color { dark ? Color(white: 0.26) : .white }
    var shadow: Color { dark ? .black : Color(white: 0.70) }
    /// Açık zeminde gölge çizgisi kurşun kalem gibi okunmasın diye çok daha hafif.
    var shadowAlpha: Double { dark ? 0.35 : 0.12 }
}

private struct GrisaillePainting: View {
    let palette: Grisaille

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            var rng = SeededRandom(seed: palette.dark ? 0xD4A1_5EED : 0x11F7_C0DE)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.ground))
            // 1) Alt boyama: geniş, sakin süpürmeler.
            for _ in 0..<42 {
                stroke(&context, size, &rng, width: 120...320, length: 600...1500, value: 0.10...0.55, alpha: 0.35...0.6,
                       bristles: 11, jitter: 0.12)
            }
            // 2) Orta katman: akış alanını izleyen fırça darbeleri; merkezde seyrelir.
            for _ in 0..<360 {
                stroke(&context, size, &rng, width: 16...60, length: 90...320, value: 0.05...0.8, alpha: 0.25...0.6,
                       bristles: 6, jitter: 0.45)
            }
            // 3) İmpasto: kalın boyanın ışığı yakalayan ince sırtları.
            for _ in 0..<260 {
                impasto(&context, size, &rng)
            }
            // 4) Tuval dokusu.
            grain(&context, size, &rng)
        }
    }

    /// Merkez sakin, kenarlar hareketli: okunurluk için boyanın yoğunluğu merkezden uzaklıkla artar.
    private func edgeWeight(_ p: CGPoint, _ size: CGSize) -> Double {
        let dx = (p.x / size.width - 0.5) / 0.5
        let dy = (p.y / size.height - 0.5) / 0.5
        return min(1, 0.15 + 0.9 * sqrt(dx * dx + dy * dy))
    }

    /// Akış alanı: hafif çapraz, dalgalı bir yön (manzara gibi yatay ritim).
    private func flowAngle(_ p: CGPoint, _ size: CGSize) -> Double {
        let x = p.x / size.width, y = p.y / size.height
        return -0.22 + 0.35 * sin(x * 5.1 + y * 2.3) + 0.18 * cos(y * 7.7 - x * 1.9)
    }

    private func stroke(_ context: inout GraphicsContext, _ size: CGSize, _ rng: inout SeededRandom,
                        width: ClosedRange<Double>, length: ClosedRange<Double>,
                        value: ClosedRange<Double>, alpha: ClosedRange<Double>, bristles: Int, jitter: Double) {
        let start = CGPoint(x: rng.next(in: -100...(size.width + 100)), y: rng.next(in: -100...(size.height + 100)))
        let weight = edgeWeight(start, size)
        guard rng.next(in: 0...1) < weight else { return }
        let angle = flowAngle(start, size) + rng.next(in: -jitter...jitter)
        let len = rng.next(in: length)
        let w = rng.next(in: width)
        let bend = rng.next(in: -0.25...0.25) * len
        let base = rng.next(in: value)
        let a = rng.next(in: alpha) * weight

        let ribbon = Self.ribbon(start: start, angle: angle, length: len, width: w, bend: bend)
        context.fill(ribbon, with: .color(palette.paint(base, alpha: a)))
        // Kıl izleri: darbe boyunca biraz açık/koyu ince çizgiler — yağlı boyayı fırça izinden tanırız.
        for i in 0..<bristles {
            let offset = (Double(i) / Double(max(1, bristles - 1)) - 0.5) * w * 0.8
            var line = Path()
            Self.centerline(start: start, angle: angle, length: len, bend: bend, offset: offset, into: &line)
            let v = min(1, max(0, base + rng.next(in: -0.18...0.18)))
            context.stroke(line, with: .color(palette.paint(v, alpha: a * 0.55)),
                           style: StrokeStyle(lineWidth: rng.next(in: 0.6...2.2), lineCap: .round))
        }
    }

    private func impasto(_ context: inout GraphicsContext, _ size: CGSize, _ rng: inout SeededRandom) {
        let start = CGPoint(x: rng.next(in: 0...size.width), y: rng.next(in: 0...size.height))
        let weight = edgeWeight(start, size)
        guard rng.next(in: 0...1) < weight * weight else { return }
        let angle = flowAngle(start, size) + rng.next(in: -0.3...0.3)
        let len = rng.next(in: 30...150)
        let bend = rng.next(in: -0.3...0.3) * len
        var ridge = Path()
        Self.centerline(start: start, angle: angle, length: len, bend: bend, offset: 0, into: &ridge)
        let lineWidth = rng.next(in: 1.2...4.5)
        context.stroke(ridge.offsetBy(dx: 1.2, dy: 1.6), with: .color(palette.shadow.opacity(palette.shadowAlpha * weight)),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        context.stroke(ridge, with: .color(palette.highlight.opacity(rng.next(in: 0.10...0.32) * weight)),
                       style: StrokeStyle(lineWidth: lineWidth * 0.6, lineCap: .round))
    }

    private func grain(_ context: inout GraphicsContext, _ size: CGSize, _ rng: inout SeededRandom) {
        // Keten dokusu: ince yatay/dikey atkı çizgileri + seyrek noktalar.
        let weave = palette.dark ? Color.white.opacity(0.012) : Color.black.opacity(0.018)
        var threads = Path()
        var y = 0.0
        while y < size.height { threads.addRect(CGRect(x: 0, y: y, width: size.width, height: 0.6)); y += 3 }
        var x = 0.0
        while x < size.width { threads.addRect(CGRect(x: x, y: 0, width: 0.6, height: size.height)); x += 3 }
        context.fill(threads, with: .color(weave))
        var specks = Path()
        for _ in 0..<14_000 {
            specks.addRect(CGRect(x: rng.next(in: 0...size.width), y: rng.next(in: 0...size.height), width: 1, height: 1))
        }
        context.fill(specks, with: .color(palette.dark ? Color.white.opacity(0.035) : Color.black.opacity(0.04)))
    }

    // MARK: - Geometri

    private static func point(start: CGPoint, angle: Double, length: Double, bend: Double, t: Double, offset: Double) -> CGPoint {
        let dir = CGVector(dx: cos(angle), dy: sin(angle))
        let normal = CGVector(dx: -dir.dy, dy: dir.dx)
        let along = length * t
        let curve = bend * 4 * t * (1 - t) + offset
        return CGPoint(x: start.x + dir.dx * along + normal.dx * curve, y: start.y + dir.dy * along + normal.dy * curve)
    }

    private static func centerline(start: CGPoint, angle: Double, length: Double, bend: Double, offset: Double, into path: inout Path) {
        let steps = 12
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let p = point(start: start, angle: angle, length: length, bend: bend, t: t, offset: offset * sin(.pi * t))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
    }

    /// Uçlara doğru incelen fırça şeridi.
    private static func ribbon(start: CGPoint, angle: Double, length: Double, width: Double, bend: Double) -> Path {
        let steps = 16
        var left: [CGPoint] = [], right: [CGPoint] = []
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let half = width / 2 * pow(sin(.pi * t), 0.45)
            left.append(point(start: start, angle: angle, length: length, bend: bend, t: t, offset: half))
            right.append(point(start: start, angle: angle, length: length, bend: bend, t: t, offset: -half))
        }
        var path = Path()
        path.addLines(left + right.reversed())
        path.closeSubpath()
        return path
    }
}

/// Deterministik üreteç (SplitMix64): tuval her açılışta aynı resimdir.
private struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func nextUInt() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        let unit = Double(nextUInt() >> 11) / Double(1 << 53)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}
