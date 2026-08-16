import SwiftUI

/// Full-screen animated angular gradient used as the shared brand
/// background across ``SplashView`` and ``ContentView``.
///
/// The gradient sweeps between two anchor purples and rotates
/// perpetually (8 s / turn, linear). A vertical overlay adds subtle
/// depth so text and controls read cleanly on top.
struct AnimatedBackground: View {

    /// Drives the perpetual rotation.
    @State private var gradientAngle: Angle = .degrees(0)

    var body: some View {
        AngularGradient(
            gradient: Gradient(colors: [
                Color(red: 0.36, green: 0.31, blue: 0.85),
                Color(red: 0.55, green: 0.35, blue: 0.95),
                Color(red: 0.36, green: 0.31, blue: 0.85)
            ]),
            center: .center,
            angle: gradientAngle
        )
        .ignoresSafeArea()
        .overlay(
            LinearGradient(
                colors: [.black.opacity(0.15), .clear, .black.opacity(0.25)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .onAppear {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                gradientAngle = .degrees(360)
            }
        }
    }
}

/// Logo + wordmark + tagline block.
///
/// Two size presets are supported through ``Scale``:
///
/// - ``Scale/splash`` — large hero variant used on ``SplashView``.
/// - ``Scale/compact`` — smaller variant used on the main
///   ``ContentView`` above the action buttons.
struct BrandHeader: View {

    /// Preset size configuration.
    enum Scale {
        /// Splash variant (160 pt logo, 32 pt title).
        case splash
        /// Main-screen variant (100 pt logo, 24 pt title).
        case compact

        var logoSize: CGFloat {
            switch self {
            case .splash:  return 160
            case .compact: return 100
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .splash:  return 36
            case .compact: return 22
            }
        }

        var titleFont: Font {
            switch self {
            case .splash:  return .system(size: 32, weight: .semibold, design: .rounded)
            case .compact: return .system(size: 24, weight: .semibold, design: .rounded)
            }
        }

        var subtitleFont: Font {
            switch self {
            case .splash:  return .system(size: 15, weight: .regular, design: .rounded)
            case .compact: return .system(size: 13, weight: .regular, design: .rounded)
            }
        }

        var spacing: CGFloat {
            switch self {
            case .splash:  return 24
            case .compact: return 16
            }
        }
    }

    /// Selected preset.
    let scale: Scale

    var body: some View {
        VStack(spacing: scale.spacing) {
            Image("LaunchLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: scale.logoSize, height: scale.logoSize)
                .clipShape(RoundedRectangle(cornerRadius: scale.cornerRadius, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 12)

            VStack(spacing: 6) {
                Text("BiometricID")
                    .font(scale.titleFont)
                    .foregroundStyle(.white)
                Text("Secure face authentication")
                    .font(scale.subtitleFont)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}
