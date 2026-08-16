import SwiftUI

/// Animated in-app splash overlay.
///
/// Rendered by ``BiometricIDApp`` above ``ContentView`` for a short
/// minimum duration on cold launch. Provides visual continuity between
/// the system launch screen and the app's live UI.
///
/// Uses the shared ``AnimatedBackground`` and ``BrandHeader`` so its
/// look matches the main screen. Adds two splash-only touches:
///
/// - The logo scales up from 0.6 → 1.0 and the whole header fades in.
/// - A soft "breathing" ring pulses around the logo while the SDK
///   bootstraps under the hood.
///
/// The view itself does not decide when to dismiss — a parent
/// `isVisible` binding controls that. See ``RootView`` for the timing
/// policy (minimum on-screen duration + fade-out).
struct SplashView: View {

    /// Drives the logo scale-up animation.
    @State private var logoScale: CGFloat = 0.6

    /// Drives the header fade-in.
    @State private var headerOpacity: Double = 0

    /// Drives the perpetual breathing ring around the logo.
    @State private var ringScale: CGFloat = 1.0
    @State private var ringOpacity: Double = 0.6

    var body: some View {
        ZStack {
            AnimatedBackground()

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.35), lineWidth: 2)
                    .frame(width: 200, height: 200)
                    .scaleEffect(ringScale)
                    .opacity(ringOpacity)
                    .offset(y: -60)

                BrandHeader(scale: .splash)
                    .scaleEffect(logoScale)
                    .opacity(headerOpacity)
            }
        }
        .onAppear(perform: startAnimations)
    }

    private func startAnimations() {
        withAnimation(.easeOut(duration: 0.7)) {
            logoScale = 1.0
            headerOpacity = 1.0
        }
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            ringScale = 1.15
            ringOpacity = 0.1
        }
    }
}

/// Top-level composition that overlays ``SplashView`` on top of
/// ``ContentView`` for the first moments of the app's lifetime.
///
/// Dismissal policy: the splash stays visible for at least
/// ``minimumDuration`` and fades out afterwards. It does not wait for
/// the SDK to finish loading — ``ContentView`` already renders its own
/// `LoadingOverlay` while the SDK is initialising, so the transition is
/// seamless.
struct RootView: View {

    /// Minimum time the splash overlay is guaranteed to stay on screen.
    private let minimumDuration: TimeInterval = 1.4

    /// Whether the splash is currently rendered.
    @State private var showSplash: Bool = true

    var body: some View {
        ZStack {
            ContentView()

            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: UInt64(minimumDuration * 1_000_000_000))
            withAnimation(.easeInOut(duration: 0.5)) {
                showSplash = false
            }
        }
    }
}

#Preview("Splash") {
    SplashView()
}

#Preview("Root") {
    RootView()
}
