import SwiftUI
@preconcurrency import BiometricidSDK

/// File-local logger that prefixes every message with `[APP]`.
///
/// `nonisolated` because the surrounding module defaults to `@MainActor`
/// isolation, and some SwiftUI-derived closures (binding getters/setters
/// used from view diffing) may be evaluated in nonisolated contexts.
///
/// - Parameter message: Free-form log payload.
nonisolated private func log(_ message: String) {
    print("[APP] \(message)")
}

/// Root screen of the app.
///
/// Renders the two primary actions ("FaceID signin" and "Enroll Face"),
/// overlays a status indicator that reflects
/// ``BiometricViewModel/frameworkState`` (loading spinner /
/// configuration-error card / hidden when ready) and hosts three modal
/// presentations that the view-model drives declaratively:
///
/// - `fullScreenCover(item:)` on ``BiometricViewModel/authenticatedUser``
///   showing ``UserDetailsView`` for a successful sign-in or registration.
/// - `sheet(isPresented:)` on
///   ``BiometricViewModel/isEnrollmentSheetPresented`` showing
///   ``EnrollFaceView``.
/// - `alert` bound to ``BiometricViewModel/errorMessage`` for
///   per-operation failures.
///
/// The view owns its ``BiometricViewModel`` via `@StateObject`, so the
/// model's lifetime matches the app's UI lifetime.
struct ContentView: View {

    /// Application state. Owned by this view for the entire process lifetime.
    @StateObject private var viewModel = BiometricViewModel()

    var body: some View {
        let _ = log("🖼 ContentView body eval. authUser=\(viewModel.authenticatedUser?.id ?? "nil") err=\(viewModel.errorMessage ?? "nil") ready=\(viewModel.isFrameworkReady) configErr=\(viewModel.configurationError?.localizedDescription ?? "nil")")

        return NavigationStack {
            ZStack {
                AnimatedBackground()

                VStack(spacing: 40) {
                    Spacer()
                    BrandHeader(scale: .compact)
                    Spacer()

                    VStack(spacing: 16) {
                        Button {
                            viewModel.signIn()
                        } label: {
                            Label("FaceID signin", systemImage: "faceid")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.white)
                        .foregroundStyle(Color(red: 0.36, green: 0.31, blue: 0.85))
                        .disabled(!viewModel.isFrameworkReady)

                        Button {
                            viewModel.enrollFace()
                        } label: {
                            Label("Enroll Face", systemImage: "person.crop.circle.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(.white)
                        .foregroundStyle(.white)
                        .disabled(!viewModel.isFrameworkReady)
                    }
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 24)

                switch viewModel.frameworkState {
                case .loading:
                    LoadingOverlay(message: "Loading BiometricID Framework")
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                case .failed(let error):
                    ConfigurationErrorOverlay(error: error)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                case .ready:
                    EmptyView()
                }
            }
            .animation(.easeInOut(duration: 0.3), value: viewModel.isFrameworkReady)
            .animation(.easeInOut(duration: 0.3), value: viewModel.configurationError?.localizedDescription)
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(item: $viewModel.authenticatedUser, onDismiss: {
            log("🧾 fullScreenCover onDismiss")
        }) { auth in
            NavigationStack {
                UserDetailsView(user: auth.user)
                    .onAppear { log("🧾 UserDetailsView.onAppear id=\(auth.id)") }
                    .onDisappear { log("🧾 UserDetailsView.onDisappear id=\(auth.id)") }
            }
        }
        .sheet(isPresented: $viewModel.isEnrollmentSheetPresented) {
            EnrollFaceView { first, last in
                viewModel.register(firstName: first, lastName: last)
            }
        }
        .alert(
            "Sign-in failed",
            isPresented: Binding(
                get: {
                    let v = viewModel.errorMessage != nil
                    if v { log("🚨 alert isPresented -> true") }
                    return v
                },
                set: { newValue in
                    log("🚨 alert isPresented set -> \(newValue)")
                    if !newValue { viewModel.dismissError() }
                }
            ),
            presenting: viewModel.errorMessage
        ) { _ in
            Button("OK", role: .cancel) { viewModel.dismissError() }
        } message: { message in
            Text(message)
        }
    }
}

/// Full-screen overlay that surfaces a **framework-level** configuration
/// failure (invalid API key, unreachable backend, inactive subscription, …).
///
/// Rendered when ``BiometricViewModel/frameworkState`` resolves to
/// ``BiometricViewModel/FrameworkState/failed(_:)``. The overlay covers the
/// action buttons; those buttons are additionally
/// `.disabled(!isFrameworkReady)` for defence in depth.
private struct ConfigurationErrorOverlay: View {

    /// Error emitted by ``BiometricidSDK/BiometricIDSDK/configurationError``.
    let error: BiometricIDError

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.yellow)
                Text("Framework unavailable")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(error.localizedDescription)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding()
        }
    }
}

/// Modal-style overlay with an animated `ProgressView` and a caption,
/// shown while the SDK is still initialising.
///
/// The progress indicator gently pulses (0.95 → 1.05 scale) to convey
/// activity — the SDK's CoreML model decompression can take several
/// seconds on cold start.
private struct LoadingOverlay: View {

    /// Caption shown under the spinner.
    let message: String

    /// Drives the infinite pulse animation on the `ProgressView`.
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .scaleEffect(pulse ? 1.05 : 0.95)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                Text(message)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .onAppear { pulse = true }
        }
    }
}

#Preview {
    ContentView()
}
