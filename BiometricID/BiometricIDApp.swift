import SwiftUI
@preconcurrency import BiometricidSDK

/// Application entry point.
///
/// Owns the single `WindowGroup` and kicks off `BiometricIDSDK` configuration
/// as soon as the app process is created. All UI is hosted under
/// ``ContentView``.
///
/// ## Startup lifecycle
///
/// 1. `init()` fires an unstructured `Task` that awaits
///    ``BiometricidSDK/BiometricIDSDK/config(with:)`` with the client's API
///    key. This is intentionally fire-and-forget: the SDK reports its
///    progress through the Combine publishers
///    ``BiometricidSDK/BiometricIDSDK/isCoreMLModelLoaded`` and
///    ``BiometricidSDK/BiometricIDSDK/configurationError``, which the view
///    layer observes via ``BiometricViewModel``.
/// 2. `ContentView` mounts and reflects the current SDK state
///    (loading / ready / failed).
///
/// The API key is hard-coded here for a demo target; in a production app it
/// should come from a secure configuration source (Keychain, remote config,
/// build settings baked at CI time, etc.).
@main
struct BiometricIDApp: App {

    /// Type-scoped literals used at app bootstrap.
    private enum Constants {
        /// API key passed to ``BiometricidSDK/BiometricIDSDK/config(with:)``.
        static let sdkApiKey = "" // Your BiometricID API key goes here
        // please visit https://biometricid.eu.com for register your new key
    }

    /// Bootstraps the SDK once per process launch.
    ///
    /// The result of `config(with:)` is intentionally discarded — the ready
    /// state and any configuration failure are delivered asynchronously
    /// through the SDK's Combine publishers, not via the return value.
    init() {
        Task {
            try await BiometricIDSDK.shared.config(with: Constants.sdkApiKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
