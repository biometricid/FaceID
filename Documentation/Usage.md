# Usage Guide

End-to-end integration recipe for `BiometricidSDK`. All snippets are
verbatim from the code in this repository; file paths link to the actual
source.

---

## 1. Obtain a free API key

Register at **https://biometricid.eu.com** and generate an API key. It's
free for evaluation. Store it outside of source control in real apps
(Keychain / remote config / build settings baked at CI time).

For contact: **support@biometricid.eu.com**

## 2. Link the framework

The xcframework ships at the repo root:

```
BiometricidSDK.xcframework/
├── ios-arm64/
└── ios-arm64_x86_64-simulator/
```

In your Xcode target:

1. **General → Frameworks, Libraries, and Embedded Content →** add
   `BiometricidSDK.xcframework` and set it to **Embed & Sign**.
2. **Build Settings → Framework Search Paths →** include the directory
   containing the xcframework (in this repo — `$(PROJECT_DIR)`).

## 3. Declare Info.plist keys

The SDK opens the camera the first time you call `login` or `registerUser`.
iOS terminates any app that touches privacy-sensitive APIs without a
usage description in `Info.plist`.

If you use auto-generated Info.plist (`GENERATE_INFOPLIST_FILE = YES`),
add the following to your target's build settings:

```
INFOPLIST_KEY_NSCameraUsageDescription = "This app uses the front camera to capture your face for biometric sign-in and enrollment."
INFOPLIST_KEY_NSFaceIDUsageDescription = "This app uses Face ID to authenticate you."
```

## 4. Bootstrap the SDK

Do this once, as early as possible.
See [`BiometricIDApp.swift`](../BiometricID/BiometricIDApp.swift):

```swift
import SwiftUI
@preconcurrency import BiometricidSDK

@main
struct BiometricIDApp: App {
    private enum Constants {
        static let sdkApiKey = "<YOUR_API_KEY>"
    }

    init() {
        Task {
            try await BiometricIDSDK.shared.config(with: Constants.sdkApiKey)
        }
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

`config(with:)` validates the key with the backend, then decrypts and
compiles the on-device CoreML model. The completion is observable — not
returned — so we ignore the `try await` result and subscribe to the
publishers instead.

## 5. Observe framework state

The SDK exposes two `@Published` properties. Collapse them into a single
UI-facing state.
See [`BiometricViewModel.swift`](../BiometricID/BiometricViewModel.swift):

```swift
@MainActor
final class BiometricViewModel: ObservableObject {
    @Published var isFrameworkReady: Bool = false
    @Published var configurationError: BiometricIDError?

    enum FrameworkState {
        case loading
        case ready
        case failed(BiometricIDError)
    }

    var frameworkState: FrameworkState {
        if let error = configurationError { return .failed(error) }
        return isFrameworkReady ? .ready : .loading
    }

    private var cancellables = Set<AnyCancellable>()

    init() {
        BiometricIDSDK.shared.$isCoreMLModelLoaded
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.isFrameworkReady = $0 }
            .store(in: &cancellables)

        BiometricIDSDK.shared.$configurationError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.configurationError = $0 }
            .store(in: &cancellables)
    }
}
```

Then let the view switch on it:

```swift
switch viewModel.frameworkState {
case .loading:       LoadingOverlay(message: "Loading BiometricID Framework")
case .failed(let e): ConfigurationErrorOverlay(error: e)
case .ready:         EmptyView()   // buttons visible/enabled
}
```

## 6. Sign a user in

```swift
func signIn() {
    BiometricIDSDK.shared.login { [weak self] result in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            switch result {
            case .success(let user):
                self?.authenticatedUser = AuthenticatedUser(user: user)
            case .failure(let error):
                self?.errorMessage = error.errorDescription
                    ?? String(describing: error)
            }
        }
    }
}
```

Two things to notice:

1. **Wrap `BiometricidUser` in an `Identifiable` shim** so it can drive
   SwiftUI's `fullScreenCover(item:)` / `sheet(item:)`:

   ```swift
   struct AuthenticatedUser: Identifiable {
       let user: BiometricidUser
       var id: String { user.userId }
   }
   ```

2. **Delay the state change by 0.5 s.** On success the SDK animates
   its own `UIWindow` away; presenting a SwiftUI full-screen cover while
   that window is still key produces a race where the cover never shows.
   A short main-queue hop after the callback fires solves it cleanly.

Present the result:

```swift
.fullScreenCover(item: $viewModel.authenticatedUser) { auth in
    NavigationStack {
        UserDetailsView(user: auth.user)
    }
}
```

## 7. Enroll a new face

The pattern is a mirror of sign-in. Present an input form, collect first
and last name, and hand them to
`BiometricIDSDK.shared.registerUser(firstName:lastName:completion:)`.

See [`EnrollFaceView.swift`](../BiometricID/EnrollFaceView.swift) for the
form. Validation is simple:

```swift
private var isRegisterEnabled: Bool {
    !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
    !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}
```

The **Register** button is `.disabled(!isRegisterEnabled)`. On tap the
sheet dismisses first, then — after a 0.35 s delay to let SwiftUI finish
tearing the sheet down — the caller's handler fires:

```swift
private func submit() {
    let f = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    let l = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
    dismiss()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
        onRegister(f, l)
    }
}
```

The view-model handles the completion identically to `login`:

```swift
func register(firstName: String, lastName: String) {
    BiometricIDSDK.shared.registerUser(firstName: firstName, lastName: lastName) {
        [weak self] result in
        // same 0.5 s hop + switch on Result as in signIn()
    }
}
```

## 8. Present errors

The framework surfaces per-operation failures through the completion's
`.failure(BiometricIDError)`. Use `error.localizedDescription` for
user-facing text; keep the raw enum around for programmatic decisions.

```swift
.alert(
    "Sign-in failed",
    isPresented: Binding(
        get: { viewModel.errorMessage != nil },
        set: { if !$0 { viewModel.dismissError() } }
    ),
    presenting: viewModel.errorMessage
) { _ in
    Button("OK", role: .cancel) { viewModel.dismissError() }
} message: { Text($0) }
```

Framework-wide configuration failures (`configurationError`) are shown as
a persistent overlay via `FrameworkState.failed(_:)`, not an alert — they
prevent the user from doing anything meaningful anyway.

---

## Concurrency & Swift 6 notes

- The framework does not annotate its types as `Sendable`. Import it with
  `@preconcurrency` in every file that references SDK types:

  ```swift
  @preconcurrency import BiometricidSDK
  ```

  This preserves strict concurrency checking in your own code while
  silencing warnings from the framework's boundary.

- SDK completion callbacks are not guaranteed to arrive on the main
  queue. Mark your handler `nonisolated`, or hop to `DispatchQueue.main`
  before touching UI state.

- Keep the completion → state-change transition wrapped in a small
  `asyncAfter(deadline: .now() + 0.5)`. This gives the SDK's own `UIWindow`
  time to animate away before SwiftUI stacks its next presentation.

## Diagnostic logging (recommended)

While integrating, log every publisher event, button tap, callback and
state transition through a single `[APP] ...` prefix. The framework
itself uses `print` for its diagnostics, so a matching prefix from your
code lets you read the two streams together in Xcode's debug console.

Arm a watchdog around each SDK call — if a completion does not arrive
within a couple of seconds, that in itself is diagnostic:

```swift
private func armWatchdog(label: String) {
    completionWatchdog?.cancel()
    let w = DispatchWorkItem {
        print("[APP] ⏰ WATCHDOG: no completion from SDK.\(label) within 3s")
    }
    completionWatchdog = w
    DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: w)
}
```

## Related documents

- [Architecture](Architecture.md) — component and sequence diagrams for
  this app.
- [Framework overview](Framework.md) — full description of `BiometricidSDK`
  itself.
