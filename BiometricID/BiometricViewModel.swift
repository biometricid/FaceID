import Foundation
import Combine
import UIKit
@preconcurrency import BiometricidSDK

/// Prints a message tagged with `[APP]` so the app's logs interleave with the
/// SDK's own `print()` output in Xcode's debug console.
///
/// Marked `nonisolated` because the surrounding module defaults to
/// `@MainActor` isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`), and
/// some callers (SDK completion handlers) reach the model from a background
/// thread.
///
/// - Parameter message: Human-readable payload; timestamp/thread annotations
///   should be added by the caller when useful.
nonisolated private func log(_ message: String) {
    print("[APP] \(message)")
}

/// Identifiable wrapper around ``BiometricidSDK/BiometricidUser`` so it can be
/// used as the item argument of SwiftUI's `sheet(item:)` /
/// `fullScreenCover(item:)`.
///
/// `BiometricidUser` itself is only `Codable`, not `Hashable` /
/// `Identifiable`, so wrapping is the least intrusive way to satisfy those
/// requirements.
struct AuthenticatedUser: Identifiable {
    /// The SDK-provided user payload.
    let user: BiometricidUser

    /// Uses the server-assigned `userId` as the stable identity.
    var id: String { user.userId }
}

/// View-model that bridges ``BiometricidSDK/BiometricIDSDK`` to the SwiftUI
/// layer.
///
/// Responsibilities:
///
/// - Observes the SDK's Combine publishers
///   ``BiometricidSDK/BiometricIDSDK/isCoreMLModelLoaded`` and
///   ``BiometricidSDK/BiometricIDSDK/configurationError`` and re-publishes
///   their values as ``isFrameworkReady`` and ``configurationError`` for the
///   UI to react to.
/// - Exposes ``frameworkState`` — a single derived enum the view uses to
///   pick between the loading spinner, the error overlay and the ready
///   state.
/// - Wraps the SDK's callback-based ``BiometricidSDK/BiometricIDSDK/login(completion:)``
///   and ``BiometricidSDK/BiometricIDSDK/registerUser(firstName:lastName:completion:)``
///   into `@Published` state transitions that the view observes.
///
/// The type is pinned to `@MainActor` because it is bound directly to the
/// SwiftUI view hierarchy through `@StateObject`. SDK completions may arrive
/// on a background thread; ``handleCompletion(_:source:)`` is therefore
/// `nonisolated` and hops back to the main queue before mutating any
/// `@Published` property.
@MainActor
final class BiometricViewModel: ObservableObject {

    /// Mirror of ``BiometricidSDK/BiometricIDSDK/isCoreMLModelLoaded``.
    ///
    /// `true` once the SDK finished decrypting, compiling and loading its
    /// CoreML face-embedding model. When `false` (and no
    /// ``configurationError`` is set), the UI shows the loading overlay.
    @Published var isFrameworkReady: Bool = false {
        didSet { log("📶 isFrameworkReady -> \(isFrameworkReady)") }
    }

    /// Currently authenticated / just-enrolled user.
    ///
    /// Non-nil value drives the presentation of ``UserDetailsView`` via
    /// `fullScreenCover(item:)`. Assigned by ``handleCompletion(_:source:)``
    /// on `.success`, cleared by ``dismissUser()`` (bound to the details
    /// screen's OK button).
    @Published var authenticatedUser: AuthenticatedUser? {
        didSet {
            if let u = authenticatedUser {
                log("👤 authenticatedUser SET: id=\(u.id) name=\(u.user.firstName) \(u.user.lastName)")
            } else {
                log("👤 authenticatedUser cleared")
            }
        }
    }

    /// Text of the currently displayed sign-in/registration error.
    ///
    /// Non-nil value drives an `alert` in ``ContentView``. Cleared by the
    /// alert's OK button via ``dismissError()``. This is populated **only**
    /// for per-operation failures (`login` / `registerUser`); framework-wide
    /// configuration failures use ``configurationError``.
    @Published var errorMessage: String? {
        didSet {
            if let m = errorMessage {
                log("❗️ errorMessage SET: \(m)")
            } else {
                log("❗️ errorMessage cleared")
            }
        }
    }

    /// Whether the enrollment form (``EnrollFaceView``) is currently on
    /// screen.
    ///
    /// Bound to a `sheet(isPresented:)` in ``ContentView``. Flipped to
    /// `true` by ``enrollFace()`` and back to `false` either by the sheet's
    /// Cancel button or automatically after ``register(firstName:lastName:)``
    /// dismisses it.
    @Published var isEnrollmentSheetPresented: Bool = false {
        didSet { log("📝 isEnrollmentSheetPresented -> \(isEnrollmentSheetPresented)") }
    }

    /// Mirror of ``BiometricidSDK/BiometricIDSDK/configurationError``.
    ///
    /// Represents a **framework-level** failure that prevents the SDK from
    /// serving any biometric operation (invalid API key, unreachable
    /// backend, inactive subscription, …). While non-nil, ``frameworkState``
    /// returns ``FrameworkState/failed(_:)`` and the UI blocks both buttons
    /// behind ``ConfigurationErrorOverlay``.
    @Published var configurationError: BiometricIDError? {
        didSet {
            if let e = configurationError {
                log("🛑 configurationError SET: \(e.localizedDescription)")
            } else {
                log("🛑 configurationError cleared")
            }
        }
    }

    /// Coarse-grained UI state describing whether the SDK is usable.
    ///
    /// The order of resolution in ``frameworkState`` is:
    /// error → ready → loading.
    enum FrameworkState {
        /// SDK is still initialising (decrypting/compiling the CoreML model,
        /// validating the API key, etc.).
        case loading
        /// SDK is ready to accept ``BiometricidSDK/BiometricIDSDK/login(completion:)``
        /// and ``BiometricidSDK/BiometricIDSDK/registerUser(firstName:lastName:completion:)``.
        case ready
        /// SDK reported a fatal configuration failure via
        /// ``BiometricidSDK/BiometricIDSDK/configurationError``.
        case failed(BiometricIDError)
    }

    /// Single derived value that ``ContentView`` switches on.
    ///
    /// - Returns: ``FrameworkState/failed(_:)`` if ``configurationError`` is
    ///   non-nil; otherwise ``FrameworkState/ready`` when
    ///   ``isFrameworkReady`` is `true`; otherwise
    ///   ``FrameworkState/loading``.
    var frameworkState: FrameworkState {
        if let error = configurationError { return .failed(error) }
        return isFrameworkReady ? .ready : .loading
    }

    /// Combine subscriptions to the SDK publishers; retained for the
    /// lifetime of the view-model.
    private var cancellables = Set<AnyCancellable>()

    /// Pending work item that logs when the SDK does not deliver a
    /// completion within 3 seconds. Cancelled on completion delivery.
    ///
    /// This exists to make SDK-side bugs (missing completion invocations)
    /// visible in the log stream without requiring a debugger session.
    private var completionWatchdog: DispatchWorkItem?

    /// Wires up the SDK publishers.
    ///
    /// Subscriptions live for the model's lifetime; the model itself is
    /// owned by ``ContentView`` via `@StateObject` and therefore matches the
    /// app's UI lifetime.
    init() {
        log("🧠 BiometricViewModel init")
        BiometricIDSDK.shared.$isCoreMLModelLoaded
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loaded in
                log("📶 SDK publisher fired: isCoreMLModelLoaded=\(loaded)")
                self?.isFrameworkReady = loaded
            }
            .store(in: &cancellables)

        BiometricIDSDK.shared.$configurationError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                if let error {
                    log("📶 SDK publisher fired: configurationError=\(error.localizedDescription)")
                } else {
                    log("📶 SDK publisher fired: configurationError=nil")
                }
                self?.configurationError = error
            }
            .store(in: &cancellables)
    }

    /// Invokes ``BiometricidSDK/BiometricIDSDK/login(completion:)`` and
    /// routes the result into the published state.
    ///
    /// On success — ``authenticatedUser`` is set (drives the details screen).
    /// On failure — ``errorMessage`` is set (drives the alert).
    ///
    /// A ``completionWatchdog`` is armed so that a missing SDK callback is
    /// surfaced in the log within 3 seconds.
    func signIn() {
        log("▶️ signIn() called — invoking SDK.login")
        armWatchdog(label: "login")
        BiometricIDSDK.shared.login { [weak self] result in
            self?.handleCompletion(result, source: "login")
        }
    }

    /// Presents the enrollment form (``EnrollFaceView``).
    ///
    /// The actual registration call is deferred to
    /// ``register(firstName:lastName:)``, which is invoked by the form after
    /// it is dismissed.
    func enrollFace() {
        log("▶️ enrollFace() called — presenting enrollment sheet")
        isEnrollmentSheetPresented = true
    }

    /// Invokes
    /// ``BiometricidSDK/BiometricIDSDK/registerUser(firstName:lastName:completion:)``
    /// and routes the result into the published state, identically to
    /// ``signIn()``.
    ///
    /// Both inputs are `whitespaces`-trimmed before being forwarded.
    ///
    /// - Parameters:
    ///   - firstName: Given name entered by the user.
    ///   - lastName: Family name entered by the user.
    func register(firstName: String, lastName: String) {
        let f = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let l = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        log("▶️ register(firstName:\(f), lastName:\(l)) — invoking SDK.registerUser")
        armWatchdog(label: "registerUser")
        BiometricIDSDK.shared.registerUser(firstName: f, lastName: l) { [weak self] result in
            self?.handleCompletion(result, source: "registerUser")
        }
    }

    /// Clears ``authenticatedUser``, which causes SwiftUI to dismiss
    /// ``UserDetailsView``.
    ///
    /// Bound to the OK button of the details screen.
    func dismissUser() {
        log("🚪 dismissUser() called")
        authenticatedUser = nil
    }

    /// Clears ``errorMessage``, dismissing the sign-in/registration alert.
    func dismissError() {
        log("🚪 dismissError() called")
        errorMessage = nil
    }

    /// (Re)arms ``completionWatchdog``.
    ///
    /// Cancels any previously scheduled watchdog and enqueues a new
    /// 3-second delayed log. Called at the start of each SDK operation.
    ///
    /// - Parameter label: Human-readable operation name that ends up in the
    ///   log message ("login", "registerUser", …).
    private func armWatchdog(label: String) {
        completionWatchdog?.cancel()
        let watchdog = DispatchWorkItem {
            log("⏰ WATCHDOG: no completion from SDK.\(label) within 3s (still waiting…)")
        }
        completionWatchdog = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: watchdog)
    }

    /// Normalises SDK completion results into `@Published` state changes.
    ///
    /// The method is `nonisolated` because the SDK is free to call our
    /// completion on any queue. A `.asyncAfter(deadline: .now() + 0.5)` hop
    /// is used before touching state: the SDK animates its own `UIWindow`
    /// away on success, and applying our state change while that window is
    /// still key racings with SwiftUI's presentation of
    /// `fullScreenCover(item:)`.
    ///
    /// - Parameters:
    ///   - result: The SDK's result, either a ``BiometricidSDK/BiometricidUser``
    ///     or a ``BiometricidSDK/BiometricIDError``.
    ///   - source: Operation label used purely for logging (`"login"` /
    ///     `"registerUser"`).
    private nonisolated func handleCompletion(
        _ result: Result<BiometricidUser, BiometricIDError>,
        source: String
    ) {
        let thread = Thread.isMainThread ? "main" : "bg"
        switch result {
        case .success(let user):
            log("✅ SDK.\(source) completion on \(thread): success user=\(user.userId) \(user.firstName) \(user.lastName)")
        case .failure(let err):
            log("❌ SDK.\(source) completion on \(thread): failure \(err.localizedDescription)")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else {
                log("⚠️ self is nil after delay — VM was deallocated")
                return
            }
            self.completionWatchdog?.cancel()
            switch result {
            case .success(let user):
                log("✨ Applying success from \(source) -> authenticatedUser")
                self.authenticatedUser = AuthenticatedUser(user: user)
            case .failure(let error):
                log("💥 Applying failure from \(source) -> errorMessage")
                self.errorMessage = error.errorDescription ?? String(describing: error)
            }
        }
    }
}
