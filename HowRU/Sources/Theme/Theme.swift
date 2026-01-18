import SwiftUI
import UIKit

// MARK: - Animation Tokens

extension Animation {
    /// Snappy interaction spring - buttons, toggles, taps (120-180ms feel)
    static let howruSnappy = Animation.spring(response: 0.35, dampingFraction: 0.7)

    /// Smooth transition spring - screen changes, expansions (250-350ms feel)
    static let howruSmooth = Animation.spring(response: 0.5, dampingFraction: 0.8)

    /// Bouncy spring - success states, celebrations
    static let howruBouncy = Animation.spring(response: 0.4, dampingFraction: 0.6)

    /// Interactive spring - drag gestures, sliders
    static let howruInteractive = Animation.interactiveSpring(response: 0.3, dampingFraction: 0.7)

    /// Numeric text transitions
    static let howruNumeric = Animation.easeInOut(duration: 0.25)
}

// MARK: - Transition Helpers

extension AnyTransition {
    /// Fade for onboarding steps
    @MainActor static var howruFade: AnyTransition {
        .opacity
    }

    /// Slide from trailing with fade for list inserts
    @MainActor static var howruSlideIn: AnyTransition {
        .move(edge: .trailing).combined(with: .opacity)
    }

    /// Scale up with fade for success states
    @MainActor static var howruScaleUp: AnyTransition {
        .scale(scale: 0.8).combined(with: .opacity)
    }

    /// Push transition for navigation-like changes
    @MainActor static var howruPush: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }
}

// MARK: - Haptics

@MainActor
struct HowRUHaptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func heavy() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

// MARK: - Adaptive Color System

/// Provides colors that automatically adapt to light/dark mode
struct HowRUColors {

    // MARK: - Backgrounds

    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "1C1917") : Color(hex: "F7F3EE")
    }

    static func backgroundWarm(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "231F1C") : Color(hex: "FDF9F5")
    }

    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "2A2523") : Color.white
    }

    static func surfaceWarm(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "322D2A") : Color(hex: "FFFCF9")
    }

    static func surfaceElevated(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "3D3835") : Color.white
    }

    // MARK: - Text

    static func textPrimary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "F5F2EE") : Color(hex: "2D2A26")
    }

    static func textSecondary(_ scheme: ColorScheme) -> Color {
        // Lighter in dark mode for better contrast
        scheme == .dark ? Color(hex: "B5ADA3") : Color(hex: "9D958A")
    }

    static func textInverse(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "2D2A26") : Color(hex: "F5F2EE")
    }

    // MARK: - Brand Colors (consistent in both modes for brand identity)

    static let coral = Color(hex: "E85A3C")
    static let coralLight = Color(hex: "F4A68E")

    static func coralGlow(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "3D2822") : Color(hex: "FFEEE8")
    }

    // MARK: - Semantic Colors

    static func success(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "34C759") : Color(hex: "4CD964")
    }

    static func warning(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "FF9F0A") : Color(hex: "F5A623")
    }

    static func error(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "FF453A") : Color(hex: "FF3B30")
    }

    static func info(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "7B6BA8") : Color(hex: "5D4E8C")
    }

    // MARK: - Mood Category Colors

    static func moodMental(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "8B7BB8") : Color(hex: "5D4E8C")
    }

    static func moodBody(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "34C759") : Color(hex: "4CD964")
    }

    static func moodEmotional(_ scheme: ColorScheme) -> Color {
        coral // Brand coral for emotional - consistent
    }

    // MARK: - UI Elements

    static func divider(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "3D3835") : Color(hex: "E8E2DA")
    }

    static func buttonBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "F5F2EE") : Color(hex: "1C1917")
    }

    static func buttonForeground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "1C1917") : Color(hex: "F5F2EE")
    }

    static func shadow(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.black.opacity(0.3)
            : Color(hex: "2D2A26").opacity(0.06)
    }

    static func shadowWarm(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.black.opacity(0.4)
            : Color(hex: "8B7355").opacity(0.08)
    }

    // MARK: - Avatar Colors (softer, work in both modes)

    static let avatarBlue = Color(hex: "A8B5DC")
    static let avatarRose = Color(hex: "E8B5BF")
    static let avatarGreen = Color(hex: "A8D9A8")
    static let avatarPink = Color(hex: "F5C5D0")
    static let avatarPeach = Color(hex: "F5D0B8")

    static let avatarColors: [Color] = [avatarBlue, avatarRose, avatarGreen, avatarPink, avatarPeach]

    static func avatarColor(for name: String) -> Color {
        let hash = abs(name.hashValue)
        return avatarColors[hash % avatarColors.count]
    }
}

// MARK: - Legacy Static Colors (for backward compatibility)

extension Color {
    // Backgrounds - use HowRUColors for adaptive versions
    static let howruBackground = Color(hex: "F7F3EE")
    static let howruBackgroundWarm = Color(hex: "FDF9F5")
    static let howruSurface = Color.white
    static let howruSurfaceWarm = Color(hex: "FFFCF9")

    // Text
    static let howruTextPrimary = Color(hex: "2D2A26")
    static let howruTextSecondary = Color(hex: "9D958A")

    // Brand - warm coral palette
    static let howruCoral = Color(hex: "E85A3C")
    static let howruCoralLight = Color(hex: "F4A68E")
    static let howruCoralGlow = Color(hex: "FFEEE8")

    // Accents
    static let howruProgressActive = Color(hex: "F5A623")
    static let howruToggleGreen = Color(hex: "4CD964")
    static let howruIconPurple = Color(hex: "5D4E8C")

    // Avatar Colors
    static let howruAvatarBlue = Color(hex: "A8B5DC")
    static let howruAvatarRose = Color(hex: "E8B5BF")
    static let howruAvatarGreen = Color(hex: "A8D9A8")
    static let howruAvatarPink = Color(hex: "F5C5D0")
    static let howruAvatarPeach = Color(hex: "F5D0B8")

    // Button
    static let howruButtonBackground = Color(hex: "1C1917")

    // Borders & Dividers
    static let howruDivider = Color(hex: "E8E2DA")

    // Shadows
    static let howruShadow = Color(hex: "2D2A26").opacity(0.06)
    static let howruShadowWarm = Color(hex: "8B7355").opacity(0.08)

    // Hex initializer
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Adaptive Gradients

struct HowRUGradients {

    static func background(_ scheme: ColorScheme) -> LinearGradient {
        scheme == .dark
            ? LinearGradient(
                colors: [Color(hex: "231F1C"), Color(hex: "1C1917")],
                startPoint: .top,
                endPoint: .bottom
            )
            : LinearGradient(
                colors: [Color(hex: "FFFCF9"), Color(hex: "F7F3EE")],
                startPoint: .top,
                endPoint: .bottom
            )
    }

    static func card(_ scheme: ColorScheme) -> LinearGradient {
        scheme == .dark
            ? LinearGradient(
                colors: [Color(hex: "2A2523"), Color(hex: "322D2A")],
                startPoint: .top,
                endPoint: .bottom
            )
            : LinearGradient(
                colors: [Color.white, Color(hex: "FFFAF6")],
                startPoint: .top,
                endPoint: .bottom
            )
    }

    // Brand gradients stay consistent
    static let coral = LinearGradient(
        colors: [Color(hex: "E85A3C"), Color(hex: "F4A68E")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let accent = LinearGradient(
        colors: [Color(hex: "F5A623"), Color(hex: "E85A3C")],
        startPoint: .leading,
        endPoint: .trailing
    )

    static func warmGlow(_ scheme: ColorScheme) -> RadialGradient {
        let opacity = scheme == .dark ? 0.15 : 0.6
        return RadialGradient(
            colors: [HowRUColors.coralGlow(scheme).opacity(opacity), Color.clear],
            center: .center,
            startRadius: 0,
            endRadius: 300
        )
    }

    static func logoGlow(_ scheme: ColorScheme) -> RadialGradient {
        let opacity = scheme == .dark ? 0.15 : 0.3
        return RadialGradient(
            colors: [Color(hex: "F4A68E").opacity(opacity), Color.clear],
            center: .center,
            startRadius: 20,
            endRadius: 120
        )
    }
}

// MARK: - Legacy Static Gradients (for backward compatibility)

extension LinearGradient {
    static let howruBackgroundGradient = LinearGradient(
        colors: [Color(hex: "FFFCF9"), Color(hex: "F7F3EE")],
        startPoint: .top,
        endPoint: .bottom
    )

    static let howruCardGradient = LinearGradient(
        colors: [Color.white, Color(hex: "FFFAF6")],
        startPoint: .top,
        endPoint: .bottom
    )

    static let howruAccentGradient = LinearGradient(
        colors: [Color(hex: "F5A623"), Color(hex: "E85A3C")],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let howruCoralGradient = LinearGradient(
        colors: [Color(hex: "E85A3C"), Color(hex: "F4A68E")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension RadialGradient {
    static let howruWarmGlow = RadialGradient(
        colors: [Color(hex: "FFEEE8").opacity(0.6), Color.clear],
        center: .center,
        startRadius: 0,
        endRadius: 300
    )

    static let howruLogoGlow = RadialGradient(
        colors: [Color(hex: "F4A68E").opacity(0.3), Color.clear],
        center: .center,
        startRadius: 20,
        endRadius: 120
    )
}

// MARK: - Typography

struct HowRUFont {
    // Font names - PostScript names from the font files
    static let recoletaLight = "Recoleta-Light"
    static let recoletaRegular = "Recoleta-Regular"
    static let recoletaMedium = "Recoleta-Medium"
    static let recoletaSemiBold = "Recoleta-SemiBold"

    // Geist font names
    static let geistRegular = "Geist-Regular"
    static let geistMedium = "Geist-Medium"
    static let geistSemiBold = "Geist-SemiBold"

    // Headline styles (Recoleta - serif)
    static func headline1(_ size: CGFloat = 32) -> Font {
        .custom(recoletaRegular, size: size)
    }

    static func headline2(_ size: CGFloat = 24) -> Font {
        .custom(recoletaMedium, size: size)
    }

    static func headline3(_ size: CGFloat = 20) -> Font {
        .custom(recoletaLight, size: size)
    }

    static func headlineBold(_ size: CGFloat = 32) -> Font {
        .custom(recoletaSemiBold, size: size)
    }

    // Body & Subtext styles (Geist - sans-serif)
    static func body(_ size: CGFloat = 16) -> Font {
        .custom(geistRegular, size: size)
    }

    static func bodyMedium(_ size: CGFloat = 16) -> Font {
        .custom(geistMedium, size: size)
    }

    static func caption(_ size: CGFloat = 14) -> Font {
        .custom(geistRegular, size: size)
    }

    static func subtext(_ size: CGFloat = 16) -> Font {
        .custom(geistRegular, size: size)
    }

    // Button style (Geist - sans-serif)
    static func button(_ size: CGFloat = 18) -> Font {
        .custom(geistMedium, size: size)
    }
}

// MARK: - Typography Tracking

struct HowRUTracking {
    static let tight: CGFloat = -0.5      // For Recoleta headlines
    static let normal: CGFloat = 0        // Default
    static let wide: CGFloat = 0.5        // For small caps / labels
}

// MARK: - Spacing

struct HowRUSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
    static let screenEdge: CGFloat = 24   // Generous screen margins
}

// MARK: - Corner Radius

struct HowRURadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 20
    static let xl: CGFloat = 28
    static let full: CGFloat = 9999
}

// MARK: - Shadows

struct HowRUShadow {
    // Soft card shadow
    static let card = (color: Color.howruShadowWarm, radius: CGFloat(16), x: CGFloat(0), y: CGFloat(4))
    // Subtle input shadow
    static let input = (color: Color.howruShadow, radius: CGFloat(8), x: CGFloat(0), y: CGFloat(2))
    // Button shadow
    static let button = (color: Color.howruCoral.opacity(0.3), radius: CGFloat(12), x: CGFloat(0), y: CGFloat(4))

    // Adaptive shadows
    static func cardShadow(_ scheme: ColorScheme) -> (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        (color: HowRUColors.shadowWarm(scheme), radius: 16, x: 0, y: 4)
    }

    static func inputShadow(_ scheme: ColorScheme) -> (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        (color: HowRUColors.shadow(scheme), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Avatar Colors

struct AvatarColor {
    static let colors: [Color] = [
        .howruAvatarBlue,
        .howruAvatarRose,
        .howruAvatarGreen,
        .howruAvatarPink,
        .howruAvatarPeach
    ]

    static func forName(_ name: String) -> Color {
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
    }
}

// MARK: - Adaptive Background Views

struct WarmBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var showGlow: Bool = true

    var body: some View {
        ZStack {
            HowRUGradients.background(colorScheme)
                .ignoresSafeArea()

            if showGlow {
                HowRUGradients.warmGlow(colorScheme)
                    .ignoresSafeArea()
            }
        }
    }
}

/// Static gradient background for reduced motion accessibility
struct StaticGradientBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            // Base
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(colorScheme == .dark ? Color(hex: "231F1C") : Color(hex: "FDF9F5"))
            )

            // Static blob positions
            let blob1X = size.width * 0.7
            let blob1Y = size.height * 0.2

            let blob2X = size.width * 0.3
            let blob2Y = size.height * 0.7

            let blob3X = size.width * 0.5
            let blob3Y = size.height * 0.5

            // Blob 1 - Coral top right
            let blob1 = Path(ellipseIn: CGRect(
                x: blob1X - 200,
                y: blob1Y - 200,
                width: 400,
                height: 400
            ))
            context.fill(
                blob1,
                with: .radialGradient(
                    Gradient(colors: [
                        HowRUColors.coralLight.opacity(colorScheme == .dark ? 0.15 : 0.35),
                        Color.clear
                    ]),
                    center: CGPoint(x: blob1X, y: blob1Y),
                    startRadius: 0,
                    endRadius: 200
                )
            )

            // Blob 2 - Peach bottom left
            let blob2 = Path(ellipseIn: CGRect(
                x: blob2X - 250,
                y: blob2Y - 250,
                width: 500,
                height: 500
            ))
            context.fill(
                blob2,
                with: .radialGradient(
                    Gradient(colors: [
                        HowRUColors.coralGlow(colorScheme).opacity(colorScheme == .dark ? 0.2 : 0.5),
                        Color.clear
                    ]),
                    center: CGPoint(x: blob2X, y: blob2Y),
                    startRadius: 0,
                    endRadius: 250
                )
            )

            // Blob 3 - Subtle warm center
            let blob3 = Path(ellipseIn: CGRect(
                x: blob3X - 300,
                y: blob3Y - 300,
                width: 600,
                height: 600
            ))
            context.fill(
                blob3,
                with: .radialGradient(
                    Gradient(colors: [
                        Color(hex: "F5A623").opacity(colorScheme == .dark ? 0.06 : 0.12),
                        Color.clear
                    ]),
                    center: CGPoint(x: blob3X, y: blob3Y),
                    startRadius: 0,
                    endRadius: 300
                )
            )
        }
        .blur(radius: 60)
        .ignoresSafeArea()
    }
}

/// Animated liquid gradient background - respects accessibilityReduceMotion
struct AnimatedGradientBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            StaticGradientBackground()
        } else {
            AnimatedGradientBackgroundContent()
        }
    }
}

/// Internal animated content (separated for reduce motion check)
private struct AnimatedGradientBackgroundContent: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1/60)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate

                // Organic motion using sine waves
                let blob1X = size.width * 0.7 + sin(time * 0.5) * 40
                let blob1Y = size.height * 0.2 + cos(time * 0.3) * 30

                let blob2X = size.width * 0.3 + sin(time * 0.4 + 1) * 50
                let blob2Y = size.height * 0.7 + cos(time * 0.35 + 2) * 40

                let blob3X = size.width * 0.5 + sin(time * 0.25 + 3) * 60
                let blob3Y = size.height * 0.5 + cos(time * 0.3 + 1) * 50

                // Base
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .color(colorScheme == .dark ? Color(hex: "231F1C") : Color(hex: "FDF9F5"))
                )

                // Blob 1 - Coral top right
                let blob1 = Path(ellipseIn: CGRect(
                    x: blob1X - 200,
                    y: blob1Y - 200,
                    width: 400,
                    height: 400
                ))
                context.fill(
                    blob1,
                    with: .radialGradient(
                        Gradient(colors: [
                            HowRUColors.coralLight.opacity(colorScheme == .dark ? 0.15 : 0.35),
                            Color.clear
                        ]),
                        center: CGPoint(x: blob1X, y: blob1Y),
                        startRadius: 0,
                        endRadius: 200
                    )
                )

                // Blob 2 - Peach bottom left
                let blob2 = Path(ellipseIn: CGRect(
                    x: blob2X - 250,
                    y: blob2Y - 250,
                    width: 500,
                    height: 500
                ))
                context.fill(
                    blob2,
                    with: .radialGradient(
                        Gradient(colors: [
                            HowRUColors.coralGlow(colorScheme).opacity(colorScheme == .dark ? 0.2 : 0.5),
                            Color.clear
                        ]),
                        center: CGPoint(x: blob2X, y: blob2Y),
                        startRadius: 0,
                        endRadius: 250
                    )
                )

                // Blob 3 - Subtle warm center
                let blob3 = Path(ellipseIn: CGRect(
                    x: blob3X - 300,
                    y: blob3Y - 300,
                    width: 600,
                    height: 600
                ))
                context.fill(
                    blob3,
                    with: .radialGradient(
                        Gradient(colors: [
                            Color(hex: "F5A623").opacity(colorScheme == .dark ? 0.06 : 0.12),
                            Color.clear
                        ]),
                        center: CGPoint(x: blob3X, y: blob3Y),
                        startRadius: 0,
                        endRadius: 300
                    )
                )
            }
            .blur(radius: 60)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Button Styles

/// Primary button - dark bg in light mode, light bg in dark mode
struct HowRUPrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    var isFullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        let horizontalPadding = isFullWidth ? 0 : HowRUSpacing.lg
        let maxWidth: CGFloat? = isFullWidth ? .infinity : nil

        configuration.label
            .font(HowRUFont.button())
            .foregroundColor(HowRUColors.buttonForeground(colorScheme))
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: maxWidth)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: HowRURadius.lg)
                    .fill(HowRUColors.buttonBackground(colorScheme))
            )
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.howruSnappy, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed { HowRUHaptics.light() }
            }
    }
}

/// Alias for HowRUPrimaryButtonStyle
typealias HowRUFullWidthButtonStyle = HowRUPrimaryButtonStyle

/// Coral gradient button - prominent CTA
struct HowRUCoralButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(HowRUFont.button())
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: HowRURadius.lg)
                    .fill(HowRUGradients.coral)
            )
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.howruSnappy, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed { HowRUHaptics.light() }
            }
    }
}

/// Secondary button - outlined
struct HowRUSecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(HowRUFont.bodyMedium())
            .foregroundColor(HowRUColors.textPrimary(colorScheme))
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: HowRURadius.lg)
                    .fill(HowRUColors.surface(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: HowRURadius.lg)
                    .stroke(HowRUColors.divider(colorScheme), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.howruSnappy, value: configuration.isPressed)
    }
}

/// Ghost button - text only
struct HowRUGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(HowRUFont.bodyMedium())
            .foregroundColor(HowRUColors.coral)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(.howruSnappy, value: configuration.isPressed)
    }
}

// MARK: - Icon Button Style
struct HowRUIconButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    var size: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.4, weight: .medium))
            .foregroundColor(HowRUColors.textPrimary(colorScheme))
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(HowRUColors.surfaceWarm(colorScheme))
                    .shadow(
                        color: HowRUColors.shadow(colorScheme),
                        radius: configuration.isPressed ? 2 : 6,
                        x: 0,
                        y: configuration.isPressed ? 1 : 2
                    )
            )
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Adaptive Text Field Style

struct HowRUTextFieldStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var isFocused: Bool = false

    func body(content: Content) -> some View {
        content
            .font(HowRUFont.body())
            .foregroundColor(HowRUColors.textPrimary(colorScheme))
            .tint(HowRUColors.coral)
            .padding(.horizontal, HowRUSpacing.md)
            .padding(.vertical, HowRUSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: HowRURadius.lg)
                    .fill(HowRUColors.surfaceWarm(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: HowRURadius.lg)
                    .stroke(
                        isFocused ? HowRUColors.coral.opacity(0.5) : HowRUColors.divider(colorScheme).opacity(0.5),
                        lineWidth: isFocused ? 2 : 1
                    )
            )
            .shadow(
                color: isFocused ? HowRUColors.coral.opacity(0.1) : HowRUColors.shadow(colorScheme),
                radius: isFocused ? 8 : 4,
                x: 0,
                y: 2
            )
    }
}

extension View {
    func howruTextFieldStyle(isFocused: Bool = false) -> some View {
        modifier(HowRUTextFieldStyle(isFocused: isFocused))
    }
}

// MARK: - Adaptive Card Style

struct HowRUCardStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shadow = HowRUShadow.cardShadow(colorScheme)

        content
            .background(
                RoundedRectangle(cornerRadius: HowRURadius.lg)
                    .fill(HowRUColors.surface(colorScheme))
                    .shadow(
                        color: shadow.color,
                        radius: shadow.radius,
                        x: shadow.x,
                        y: shadow.y
                    )
            )
    }
}

extension View {
    func howruCardStyle() -> some View {
        modifier(HowRUCardStyle())
    }
}

// MARK: - Reusable Components

/// Avatar circle with initial letter
struct HowRUAvatar: View {
    let name: String
    var size: CGFloat = 44
    var useGradient: Bool = true

    private var initial: String {
        String(name.prefix(1)).uppercased()
    }

    var body: some View {
        Circle()
            .fill(
                useGradient
                    ? AnyShapeStyle(HowRUGradients.coral)
                    : AnyShapeStyle(AvatarColor.forName(name))
            )
            .frame(width: size, height: size)
            .overlay(
                Text(initial)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundColor(.white)
            )
            .accessibilityLabel("\(name)'s avatar")
            .accessibilityHidden(false)
    }
}

/// Status badge pill (e.g., "Pending")
struct HowRUStatusBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    var style: BadgeStyle = .warning

    enum BadgeStyle {
        case warning, success, error, info

        var accessibilityDescription: String {
            switch self {
            case .warning: return "warning"
            case .success: return "success"
            case .error: return "error"
            case .info: return "information"
            }
        }
    }

    private var color: Color {
        switch style {
        case .warning: return HowRUColors.warning(colorScheme)
        case .success: return HowRUColors.success(colorScheme)
        case .error: return HowRUColors.error(colorScheme)
        case .info: return HowRUColors.info(colorScheme)
        }
    }

    var body: some View {
        Text(text)
            .font(HowRUFont.caption())
            .foregroundStyle(color)
            .padding(.horizontal, HowRUSpacing.sm)
            .padding(.vertical, HowRUSpacing.xs)
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
            )
            .accessibilityLabel("\(text), \(style.accessibilityDescription) status")
    }
}

/// Summary card for stats display
struct HowRUSummaryCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String
    let value: String
    let title: String
    var color: Color? = nil

    var body: some View {
        VStack(spacing: HowRUSpacing.sm) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color ?? HowRUColors.coral)
                .accessibilityHidden(true)

            Text(value)
                .font(HowRUFont.headline2())
                .foregroundColor(HowRUColors.textPrimary(colorScheme))

            Text(title)
                .font(HowRUFont.caption())
                .foregroundColor(HowRUColors.textSecondary(colorScheme))
        }
        .frame(maxWidth: .infinity)
        .padding(HowRUSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: HowRURadius.md)
                .fill(HowRUColors.surface(colorScheme))
                .shadow(color: HowRUColors.shadow(colorScheme), radius: 8, y: 2)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

/// Score badge for mood scores
struct HowRUScoreBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    let emoji: String
    let score: Int
    var color: Color? = nil
    var accessibilityCategory: String = "Score"

    var body: some View {
        HStack(spacing: 4) {
            Text(emoji)
                .font(.caption)
            Text("\(score)")
                .font(HowRUFont.caption())
                .fontWeight(.medium)
                .foregroundColor(HowRUColors.textPrimary(colorScheme))
        }
        .padding(.horizontal, HowRUSpacing.sm)
        .padding(.vertical, HowRUSpacing.xs)
        .background(
            Capsule()
                .fill((color ?? HowRUColors.coral).opacity(0.15))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(accessibilityCategory): \(score) out of 5")
    }
}

/// Legend item for charts
struct HowRULegendItem: View {
    @Environment(\.colorScheme) private var colorScheme
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: HowRUSpacing.xs) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(HowRUFont.caption())
                .foregroundColor(HowRUColors.textSecondary(colorScheme))
        }
    }
}

/// Mood slider component
struct HowRUMoodSlider: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: String
    let leftEmoji: String
    let rightEmoji: String
    @Binding var value: Double
    var moodType: MoodType = .emotional
    var range: ClosedRange<Double> = 1...5
    var step: Double = 1
    var showScoreLabel: Bool = true

    enum MoodType {
        case mental, body, emotional

        var accessibilityName: String {
            switch self {
            case .mental: return "mental wellness"
            case .body: return "physical wellness"
            case .emotional: return "emotional wellness"
            }
        }
    }

    private var color: Color {
        switch moodType {
        case .mental: return HowRUColors.moodMental(colorScheme)
        case .body: return HowRUColors.moodBody(colorScheme)
        case .emotional: return HowRUColors.moodEmotional(colorScheme)
        }
    }

    private var scoreLabel: String {
        switch Int(value) {
        case 1: return "Not great"
        case 2: return "Could be better"
        case 3: return "Okay"
        case 4: return "Good"
        case 5: return "Great!"
        default: return ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HowRUSpacing.sm) {
            HStack {
                Text(label)
                    .font(HowRUFont.bodyMedium())
                    .foregroundColor(HowRUColors.textPrimary(colorScheme))
                Spacer()
                if showScoreLabel {
                    Text(scoreLabel)
                        .font(HowRUFont.caption())
                        .foregroundStyle(HowRUColors.textSecondary(colorScheme))
                }
            }
            .accessibilityHidden(true)

            HStack(spacing: 12) {
                Text(leftEmoji)
                    .font(.title2)
                    .accessibilityHidden(true)

                Slider(value: $value, in: range, step: step)
                    .tint(color)
                    .accessibilityLabel("\(label) slider")
                    .accessibilityValue("\(Int(value)) out of 5, \(scoreLabel)")
                    .accessibilityHint("Adjust to rate your \(moodType.accessibilityName)")

                Text(rightEmoji)
                    .font(.title2)
                    .accessibilityHidden(true)
            }
        }
        .padding(HowRUSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: HowRURadius.md)
                .fill(color.opacity(0.1))
        )
        .onChange(of: value) { _, _ in
            HowRUHaptics.selection()
        }
    }
}

// MARK: - Headline Text with Tracking

struct HeadlineText: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    var style: HeadlineStyle = .primary
    var size: CGFloat? = nil

    enum HeadlineStyle {
        case primary    // "Loved Ones" - larger, darker
        case secondary  // "Checking Up" - smaller, lighter
        case title      // Form titles
    }

    var body: some View {
        switch style {
        case .primary:
            Text(text)
                .font(HowRUFont.headline1(size ?? 36))
                .tracking(HowRUTracking.tight)
                .foregroundColor(HowRUColors.textPrimary(colorScheme))

        case .secondary:
            Text(text)
                .font(HowRUFont.headline2(size ?? 28))
                .tracking(HowRUTracking.tight)
                .foregroundColor(HowRUColors.textSecondary(colorScheme))

        case .title:
            Text(text)
                .font(HowRUFont.headline1(size ?? 28))
                .tracking(HowRUTracking.tight)
                .foregroundColor(HowRUColors.textPrimary(colorScheme))
        }
    }
}

// MARK: - Progress Indicator

struct HowRUProgressIndicator: View {
    @Environment(\.colorScheme) private var colorScheme
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: HowRUSpacing.xs) {
            // Filled segment
            RoundedRectangle(cornerRadius: 2)
                .fill(HowRUColors.warning(colorScheme))
                .frame(width: 24, height: 4)

            // Dashed remaining segments
            ForEach(1..<total, id: \.self) { index in
                if index < current {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(HowRUColors.warning(colorScheme))
                        .frame(width: 24, height: 4)
                } else {
                    DashedLine()
                        .stroke(HowRUColors.divider(colorScheme), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                        .frame(width: 24, height: 4)
                }
            }

            Text("\(current)/\(total)")
                .font(HowRUFont.caption())
                .foregroundColor(HowRUColors.textSecondary(colorScheme))
                .padding(.leading, HowRUSpacing.xs)
        }
    }
}

struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        return path
    }
}

// MARK: - Logo with Glow

struct LogoWithGlow: View {
    @Environment(\.colorScheme) private var colorScheme
    var size: CGFloat = 120

    var body: some View {
        ZStack {
            // Soft glow behind logo
            Circle()
                .fill(HowRUGradients.logoGlow(colorScheme))
                .frame(width: size * 2, height: size * 2)

            // Logo
            if let _ = UIImage(named: "Logo") {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: size * 0.4)
            } else {
                Text("HOWRU")
                    .font(.system(size: size * 0.2, weight: .black, design: .rounded))
                    .foregroundStyle(HowRUGradients.coral)
            }
        }
    }
}

// MARK: - Glowing Avatar

/// Avatar with status-colored radial glow effect (like the reference UI)
struct GlowingAvatar: View {
    var image: UIImage? = nil
    var name: String
    var size: CGFloat = 120
    var glowColor: Color = .green
    var showGlow: Bool = true
    var statusDescription: String = "active"

    @Environment(\.colorScheme) private var colorScheme

    private var initial: String {
        String(name.prefix(1)).uppercased()
    }

    var body: some View {
        ZStack {
            // Outer glow layers
            if showGlow {
                // Outermost glow - very faint
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [glowColor.opacity(0.15), glowColor.opacity(0)],
                            center: .center,
                            startRadius: size * 0.4,
                            endRadius: size * 0.65
                        )
                    )
                    .frame(width: size * 1.3, height: size * 1.3)

                // Middle glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [glowColor.opacity(0.25), glowColor.opacity(0.05)],
                            center: .center,
                            startRadius: size * 0.45,
                            endRadius: size * 0.55
                        )
                    )
                    .frame(width: size * 1.15, height: size * 1.15)
            }

            // Main avatar circle with gradient border
            ZStack {
                // Border gradient
                Circle()
                    .fill(
                        LinearGradient(
                            colors: showGlow
                                ? [glowColor.opacity(0.4), glowColor.opacity(0.1)]
                                : [HowRUColors.divider(colorScheme), HowRUColors.divider(colorScheme).opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size + 6, height: size + 6)

                // Inner content circle
                Group {
                    if let uiImage = image {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        // Fallback to initials with gradient
                        Circle()
                            .fill(HowRUGradients.coral)
                            .overlay(
                                Text(initial)
                                    .font(.system(size: size * 0.35, weight: .semibold))
                                    .foregroundColor(.white)
                            )
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            }
        }
        .frame(width: size * 1.3, height: size * 1.3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name)'s profile picture, status: \(statusDescription)")
    }
}

// MARK: - Status Info Card

/// Card displaying status with icon, title and subtitle (like "Your connection is secure")
struct StatusInfoCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    var subtitle: String? = nil
    var subtitleDotColor: Color? = nil

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: HowRUSpacing.md) {
            // Icon in colored circle
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(iconColor)
            }

            // Text content
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(HowRUFont.bodyMedium())
                    .foregroundColor(HowRUColors.textPrimary(colorScheme))

                if let subtitle = subtitle {
                    HStack(spacing: HowRUSpacing.xs) {
                        if let dotColor = subtitleDotColor {
                            Circle()
                                .fill(dotColor)
                                .frame(width: 6, height: 6)
                        }
                        Text(subtitle)
                            .font(HowRUFont.caption())
                            .foregroundColor(HowRUColors.textSecondary(colorScheme))
                    }
                }
            }

            Spacer()
        }
        .padding(HowRUSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: HowRURadius.lg)
                .fill(iconColor.opacity(0.08))
        )
    }
}

// MARK: - Pill Picker

/// Segmented control with pill-style selection
struct PillPicker<T: Hashable>: View {
    @Binding var selection: T
    let options: [T]
    let label: (T) -> String

    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var animation

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let isSelected = selection == option

                Button {
                    withAnimation(.howruSnappy) {
                        selection = option
                    }
                    HowRUHaptics.selection()
                } label: {
                    Text(label(option))
                        .font(HowRUFont.caption())
                        .fontWeight(isSelected ? .medium : .regular)
                        .foregroundColor(
                            isSelected
                                ? HowRUColors.textPrimary(colorScheme)
                                : HowRUColors.textSecondary(colorScheme)
                        )
                        .padding(.horizontal, HowRUSpacing.md)
                        .padding(.vertical, HowRUSpacing.sm)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: HowRURadius.sm)
                                    .fill(HowRUColors.surface(colorScheme))
                                    .shadow(color: HowRUColors.shadow(colorScheme), radius: 4, x: 0, y: 1)
                                    .matchedGeometryEffect(id: "pill", in: animation)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: HowRURadius.md)
                .fill(HowRUColors.divider(colorScheme).opacity(0.5))
        )
    }
}

// MARK: - Setting Row

/// Clean setting row with title, subtitle, and trailing content
struct SettingRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let trailing: () -> Trailing

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(HowRUFont.bodyMedium())
                    .foregroundColor(HowRUColors.textPrimary(colorScheme))

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(HowRUFont.caption())
                        .foregroundColor(HowRUColors.textSecondary(colorScheme))
                }
            }

            Spacer()

            trailing()
        }
        .padding(.vertical, HowRUSpacing.sm)
    }
}

// MARK: - Compact Action Button

/// Compact icon button for action rows
struct CompactActionButton: View {
    let icon: String
    let label: String
    var color: Color = .howruCoral
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: {
            HowRUHaptics.light()
            action()
        }) {
            VStack(spacing: HowRUSpacing.xs) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.12))
                        .frame(width: 52, height: 52)

                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(color)
                }

                Text(label)
                    .font(HowRUFont.caption())
                    .foregroundColor(HowRUColors.textSecondary(colorScheme))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint("Double tap to \(label.lowercased())")
    }
}

// MARK: - Breathing Card Modifier

/// Subtle breathing animation for cards - respects accessibilityReduceMotion
struct BreathingCardModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    var intensity: CGFloat = 0.02  // Scale amount (0.02 = 2%)
    var duration: Double = 4.0     // Full breath cycle

    func body(content: Content) -> some View {
        content
            .scaleEffect(reduceMotion ? 1.0 : (isBreathing ? 1 + intensity : 1.0))
            .animation(
                reduceMotion ? nil : .easeInOut(duration: duration).repeatForever(autoreverses: true),
                value: isBreathing
            )
            .onAppear {
                if !reduceMotion {
                    isBreathing = true
                }
            }
    }
}

extension View {
    /// Apply a subtle breathing animation to a card
    func breathingCard(intensity: CGFloat = 0.02, duration: Double = 4.0) -> some View {
        modifier(BreathingCardModifier(intensity: intensity, duration: duration))
    }
}

// MARK: - Sensory Feedback Extension

extension View {
    /// Add sensory feedback when a value changes
    func sensoryFeedback<T: Equatable>(
        _ style: SensoryFeedbackStyle,
        trigger: T
    ) -> some View {
        self.onChange(of: trigger) { _, _ in
            switch style {
            case .success:
                HowRUHaptics.success()
            case .warning:
                HowRUHaptics.warning()
            case .error:
                HowRUHaptics.error()
            case .selection:
                HowRUHaptics.selection()
            case .impact(let intensity):
                switch intensity {
                case .light:
                    HowRUHaptics.light()
                case .medium:
                    HowRUHaptics.medium()
                case .heavy:
                    HowRUHaptics.heavy()
                }
            }
        }
    }
}

enum SensoryFeedbackStyle {
    case success
    case warning
    case error
    case selection
    case impact(ImpactIntensity)

    enum ImpactIntensity {
        case light, medium, heavy
    }
}

// MARK: - Numeric Text Transition

extension View {
    /// Apply numeric text content transition for animated number changes
    func numericTransition() -> some View {
        self.contentTransition(.numericText())
    }
}

// MARK: - Preview

#Preview("Light Mode") {
    ZStack {
        WarmBackground()

        VStack(spacing: 24) {
            LogoWithGlow()

            VStack(spacing: HowRUSpacing.sm) {
                HeadlineText(text: "Checking Up", style: .secondary)
                HeadlineText(text: "Loved Ones", style: .primary)
            }

            HStack(spacing: HowRUSpacing.md) {
                HowRUAvatar(name: "John")
                HowRUAvatar(name: "Sarah", useGradient: false)
                HowRUStatusBadge(text: "Pending", style: .warning)
            }

            HStack(spacing: HowRUSpacing.sm) {
                HowRUScoreBadge(emoji: "🧠", score: 75, color: .howruIconPurple)
                HowRUScoreBadge(emoji: "💪", score: 80, color: .howruToggleGreen)
                HowRUScoreBadge(emoji: "❤️", score: 65)
            }

            VStack(spacing: 12) {
                TextField("Full Name", text: .constant(""))
                    .howruTextFieldStyle()

                TextField("Email", text: .constant(""))
                    .howruTextFieldStyle(isFocused: true)
            }
            .padding(.horizontal, HowRUSpacing.screenEdge)

            Button("Get Started") {}
                .buttonStyle(HowRUPrimaryButtonStyle())
                .padding(.horizontal, HowRUSpacing.screenEdge)

            HowRUProgressIndicator(current: 2, total: 5)
        }
        .padding()
    }
}

#Preview("Button Styles") {
    ZStack {
        WarmBackground()

        VStack(spacing: 16) {
            Text("Button Styles")
                .font(HowRUFont.headline2())

            Button("Primary Button") {}
                .buttonStyle(HowRUPrimaryButtonStyle())

            Button("Coral Button") {}
                .buttonStyle(HowRUCoralButtonStyle())

            Button("Secondary Button") {}
                .buttonStyle(HowRUSecondaryButtonStyle())

            HStack(spacing: 16) {
                Button("Ghost") {}
                    .buttonStyle(HowRUGhostButtonStyle())

                Button {} label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(HowRUIconButtonStyle())

                Button {} label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(HowRUIconButtonStyle())
            }
        }
        .padding(.horizontal, HowRUSpacing.screenEdge)
    }
}
