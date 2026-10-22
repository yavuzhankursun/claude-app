import SwiftUI

/// Monster tasarım dili — "siyah + Liquid Glass + akıcılık".
///
/// KURAL (kullanıcı kararı, docs/adr/0004-design-system.md): Uygulamanın her parçası Liquid Glass'ın en şeffaf
/// varyantını (`Glass.clear`) kullanır ve bir yansıma (specular) kenarı taşır. Mesaj balonları, kod blokları,
/// araç kartları, diff, tablolar, butonlar, seçiciler, paneller — istisna yok. Glass'a doğrudan
/// `.glassEffect(...)` ile değil, yalnızca `monsterGlass(...)` / `MonsterGlassButtonStyle` ile erişilir; böylece kural
/// tek noktadan bire bir uygulanır. Animasyonlar da yalnızca `Motion` üzerinden verilir.
enum Theme {
    static let backgroundTop = Color(red: 0, green: 0, blue: 0)
    static let backgroundBottom = Color(red: 11 / 255, green: 11 / 255, blue: 16 / 255) // #0B0B10
    static let accent = Color.accentColor
    static let danger = Color(red: 1.0, green: 0.27, blue: 0.23)

    /// Seçili satır vurgusu gibi küçük dolgu tonları (glass'ın içinde kullanılır).
    static let surfaceStrong = Color.white.opacity(0.085)
    static let hairline = Color.white.opacity(0.09)

    static let corner: CGFloat = 16
    static let smallCorner: CGFloat = 12
    static let transcriptMaxWidth: CGFloat = 820

    static let diffAdded = Color(red: 0.20, green: 0.78, blue: 0.45)
    static let diffRemoved = Color(red: 0.96, green: 0.36, blue: 0.36)

    static func tokenColor(_ kind: TokenKindStyle) -> Color {
        switch kind {
        case .keyword: Color(red: 0.99, green: 0.42, blue: 0.62)
        case .string: Color(red: 0.99, green: 0.56, blue: 0.40)
        case .comment: Color(white: 0.55)
        case .number: Color(red: 0.82, green: 0.75, blue: 0.43)
        case .type: Color(red: 0.42, green: 0.82, blue: 0.95)
        case .plain: Color(white: 0.92)
        }
    }

    enum TokenKindStyle { case keyword, string, comment, number, type, plain }
}

// MARK: - Hareket kuralı

/// Tüm modüllerde tek hareket dili. Glass morph'ları, açılıp kapanmalar, basma geri bildirimi aynı yayları kullanır.
/// Reduce Motion açıksa tümü animasyonsuzdur (`nil`).
enum Motion {
    /// Glass morph ve yerleşim değişimleri (composer genişlemesi, izin kartı, palet).
    static func glass(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .smooth(duration: 0.42, extraBounce: 0.08) }
    /// Küçük durum değişimleri (açılır kart, seçici, basma).
    static func snap(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .snappy(duration: 0.26, extraBounce: 0.04) }

    // Geriye dönük adlar (aynı yaylar).
    static func smooth(_ reduceMotion: Bool) -> Animation? { glass(reduceMotion) }
    static func snappy(_ reduceMotion: Bool) -> Animation? { snap(reduceMotion) }
}

// MARK: - Glass kuralı

/// Tek glass girişi: en şeffaf varyant + interaktif tepki + yansıma kenarı + morph geçişi.
struct MonsterGlassModifier<S: InsettableShape>: ViewModifier {
    var shape: S
    var tint: Color?
    var interactive: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .glassEffect(glass, in: shape)
            .overlay { SpecularRim(shape: shape, increasedContrast: contrast == .increased) }
            .glassEffectTransition(.matchedGeometry)
    }

    private var glass: Glass {
        var g = Glass.clear
        if let tint { g = g.tint(tint) }
        if interactive { g = g.interactive() }
        return g
    }
}

/// Yansıma kenarı: üst-sol köşeden gelen ışığı taklit eden ince, degrade bir çizgi.
/// Liquid Glass'ın kendi speküler ışığını güçlendirir; isabet testine katılmaz.
struct SpecularRim<S: InsettableShape>: View {
    var shape: S
    var increasedContrast: Bool

    var body: some View {
        shape
            .strokeBorder(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(increasedContrast ? 0.75 : 0.42), location: 0),
                        .init(color: .white.opacity(0.06), location: 0.45),
                        .init(color: .white.opacity(increasedContrast ? 0.45 : 0.18), location: 1),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                lineWidth: increasedContrast ? 1.2 : 0.8
            )
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Monster'da glass'a tek erişim yolu.
    func monsterGlass<S: InsettableShape>(in shape: S, tint: Color? = nil, interactive: Bool = true) -> some View {
        modifier(MonsterGlassModifier(shape: shape, tint: tint, interactive: interactive))
    }

    func monsterGlass(cornerRadius: CGFloat = Theme.corner, tint: Color? = nil, interactive: Bool = true) -> some View {
        monsterGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), tint: tint, interactive: interactive)
    }

    /// Eski `surface()` çağrıları da artık aynı glass kuralına bağlanır.
    func surface(strong: Bool = false, corner: CGFloat = Theme.corner) -> some View {
        monsterGlass(cornerRadius: corner, tint: strong ? Color.white.opacity(0.05) : nil)
    }
}

/// Tüm butonlar için glass stili: şeffaf glass, yansıma kenarı, ortak basma yayı.
struct MonsterGlassButtonStyle: ButtonStyle {
    enum Outline { case capsule, circle, rounded }
    var prominent = false
    var shape: Outline = .capsule
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .padding(.horizontal, shape == .circle ? 0 : 14)
            .padding(.vertical, shape == .circle ? 0 : 7)
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(Motion.snap(reduceMotion), value: configuration.isPressed)
        let tint: Color? = prominent ? Theme.accent.opacity(isEnabled ? 0.55 : 0.2) : nil
        switch shape {
        case .capsule: label.monsterGlass(in: Capsule(), tint: tint)
        case .circle: label.monsterGlass(in: Circle(), tint: tint)
        case .rounded: label.monsterGlass(in: RoundedRectangle(cornerRadius: Theme.smallCorner, style: .continuous), tint: tint)
        }
    }
}

extension ButtonStyle where Self == MonsterGlassButtonStyle {
    static var monsterGlass: MonsterGlassButtonStyle { MonsterGlassButtonStyle() }
    static var monsterGlassProminent: MonsterGlassButtonStyle { MonsterGlassButtonStyle(prominent: true) }
    static func monsterGlass(prominent: Bool = false, shape: MonsterGlassButtonStyle.Outline) -> MonsterGlassButtonStyle {
        MonsterGlassButtonStyle(prominent: prominent, shape: shape)
    }
}

// MARK: - Zemin

/// Şeffaf glass'ın "yansıtacağı" zemin: derin siyah gradient + yavaşça kayan vurgu aurası.
/// Increase Contrast / Reduce Transparency'de aura kapanır, Reduce Motion'da durur.
struct MonsterBackground: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.backgroundTop, Theme.backgroundBottom], startPoint: .top, endPoint: .bottom)
            if contrast != .increased && !reduceTransparency {
                aura
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var aura: some View {
        if reduceMotion {
            auraLayers(phase: false)
        } else {
            // Çok yavaş (24 sn) kayma: glass yüzeylerindeki yansımalar canlı kalır, dikkat dağıtmaz.
            PhaseAnimator([false, true]) { phase in
                auraLayers(phase: phase)
            } animation: { _ in
                .easeInOut(duration: 24)
            }
        }
    }

    private func auraLayers(phase: Bool) -> some View {
        ZStack {
            RadialGradient(colors: [Theme.accent.opacity(0.20), .clear],
                           center: UnitPoint(x: phase ? 0.70 : 0.88, y: phase ? 0.08 : -0.02),
                           startRadius: 0, endRadius: 560)
            RadialGradient(colors: [Color.purple.opacity(0.10), .clear],
                           center: UnitPoint(x: phase ? 0.18 : 0.06, y: phase ? 0.92 : 1.02),
                           startRadius: 0, endRadius: 480)
            RadialGradient(colors: [Color.cyan.opacity(0.05), .clear],
                           center: UnitPoint(x: 0.5, y: phase ? 0.55 : 0.45),
                           startRadius: 0, endRadius: 380)
        }
        .drawingGroup()
    }
}
