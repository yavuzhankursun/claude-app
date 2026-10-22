import AppKit
import SwiftUI

/// Monster tasarım dili — tek renkli (siyah/beyaz/gri), açık ve koyu tema, Liquid Glass, akıcılık.
///
/// KURAL (kullanıcı kararı, docs/adr/0004-design-system.md): Uygulamanın her parçası Liquid Glass'ın en şeffaf
/// varyantını (`Glass.clear`) kullanır ve bir yansıma (specular) kenarı taşır. Glass'a doğrudan `.glassEffect(...)`
/// ile değil, yalnızca `monsterGlass(...)` / `MonsterGlassButtonStyle` ile erişilir. Animasyonlar yalnızca `Motion` üzerinden.
///
/// RENK KURALI (2026-10-22): dekoratif renk yok — mor/indigo vurgu, renkli aura, gradient parıltı yok. Vurgu rengi
/// metin rengidir (koyuda beyaz, açıkta siyah). Renk yalnızca anlam taşıdığında (tehlike, uyarı, diff +/-) ve
/// düşük doygunlukta kullanılır. Tüm renkler açık/koyu temaya göre çözülür.
enum Theme {
    static let backgroundTop = Color(light: 0xFFFFFF, dark: 0x000000)
    static let backgroundBottom = Color(light: 0xF6F6F7, dark: 0x0A0A0A)
    /// Birincil eylem: koyuda beyaz, açıkta siyah. Assets'teki `AccentColor` bundan bilerek farklıdır: macOS kenar çubuğu
    /// seçimini `AccentColor` ile çizer ve üstündeki metni beyaz yapar; beyaz vurgu koyuda okunmaz bir satır veriyordu.
    static let accent = Color(light: 0x0A0A0A, dark: 0xFAFAFA)
    /// Vurgu üzerindeki metin/ikon (vurgunun tersi).
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x000000)
    static let danger = Color(light: 0xC62828, dark: 0xFF5A52)
    static let warning = Color(light: 0x9A6700, dark: 0xD9B45A)
    static let success = Color(light: 0x2E7D32, dark: 0x7BC47F)

    /// Seçili satır vurgusu gibi küçük dolgu tonları (glass'ın içinde kullanılır).
    static let surfaceStrong = Color(light: 0x000000, lightAlpha: 0.055, dark: 0xFFFFFF, darkAlpha: 0.085)
    static let hairline = Color(light: 0x000000, lightAlpha: 0.08, dark: 0xFFFFFF, darkAlpha: 0.09)

    static let corner: CGFloat = 16
    static let smallCorner: CGFloat = 12
    static let transcriptMaxWidth: CGFloat = 820

    static let diffAdded = Color(light: 0x2E7D32, dark: 0x6FBF73)
    static let diffRemoved = Color(light: 0xC62828, dark: 0xE5736C)

    /// Sözdizimi: neredeyse tek renkli. Anahtar sözcükler metin renginin en güçlü tonu, yorumlar soluk;
    /// yalnızca string ve sayı kısık bir tonla ayrılır.
    static func tokenColor(_ kind: TokenKindStyle) -> Color {
        switch kind {
        case .keyword: Color(light: 0x000000, dark: 0xFFFFFF)
        case .string: Color(light: 0x3B6E3E, dark: 0xA8C5A0)
        case .comment: Color(light: 0x8A8A8E, dark: 0x6E6E73)
        case .number: Color(light: 0x7A5C1E, dark: 0xCFB98A)
        case .type: Color(light: 0x3A3A3C, dark: 0xD6D6D6)
        case .plain: Color(light: 0x4A4A4E, dark: 0xB4B4B8)
        }
    }

    enum TokenKindStyle { case keyword, string, comment, number, type, plain }
}

/// Görünüm tercihi (Ayarlar › Genel). `system` macOS'u izler.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .system: "Sistem"
        case .light: "Açık"
        case .dark: "Koyu"
        }
    }
}

extension Color {
    /// Açık/koyu temaya göre çözülen renk (sRGB hex).
    init(light: UInt32, lightAlpha: Double = 1, dark: UInt32, darkAlpha: Double = 1) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: Double) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        shape
            .strokeBorder(
                LinearGradient(stops: stops, startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: increasedContrast ? 1.2 : 0.8
            )
            // Koyuda ışık ekler; açık zeminde `plusLighter` görünmez, normal karışım + koyu alt kenar kullanılır.
            .blendMode(colorScheme == .dark ? .plusLighter : .normal)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var stops: [Gradient.Stop] {
        if colorScheme == .dark {
            return [
                .init(color: .white.opacity(increasedContrast ? 0.75 : 0.42), location: 0),
                .init(color: .white.opacity(0.06), location: 0.45),
                .init(color: .white.opacity(increasedContrast ? 0.45 : 0.18), location: 1),
            ]
        }
        return [
            .init(color: .white.opacity(0.95), location: 0),
            .init(color: .black.opacity(increasedContrast ? 0.18 : 0.05), location: 0.5),
            .init(color: .black.opacity(increasedContrast ? 0.35 : 0.12), location: 1),
        ]
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
        monsterGlass(cornerRadius: corner, tint: strong ? Theme.surfaceStrong : nil)
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
            .foregroundStyle(prominent ? AnyShapeStyle(Theme.onAccent) : AnyShapeStyle(.primary))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(Motion.snap(reduceMotion), value: configuration.isPressed)
        // Birincil eylem: metin renginde, neredeyse dolu glass (koyuda beyaz, açıkta siyah).
        let tint: Color? = prominent ? Theme.accent.opacity(isEnabled ? 0.9 : 0.3) : nil
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

// Zemin: `PaintedCanvas` (grisaille yağlı boya tuvali), bkz. PaintedCanvas.swift.
