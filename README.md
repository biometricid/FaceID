# BiometricID Sample App

A minimal SwiftUI application demonstrating how to integrate the
**BiometricidSDK** for on-device face-based sign-in and enrollment on iOS.

The app shows the smallest end-to-end flow around the SDK:

1. Configure the SDK on launch with an API key.
2. Wait for the on-device CoreML model to be ready.
3. Let the user sign in with their face (`login`) or enroll a new face
   (`registerUser`).
4. Show the returned `BiometricidUser` on a details screen.

---

## Download latest BiometricSDK 

You can download latest version of SDK here: https://biometricid.eu.com/download
Unzip Framework and add this Framework to XCode project

## Get an API key (free)

To try the SDK you need a personal API key. Register and generate one for free
at **https://biometricid.eu.com** — no payment required for evaluation.

Paste the key into `BiometricID/BiometricIDApp.swift`:

```swift
private enum Constants {
    static let sdkApiKey = "<YOUR_API_KEY>"
}
```

For any production use, move the key out of source — Keychain, remote config,
or a CI-time build setting.

---

## Requirements

- Xcode 26.6 or newer
- iOS 26.5 or newer target device (Face ID / TrueDepth camera required for the
  real biometric flow; the simulator can only exercise the UI paths)
- The bundled `BiometricidSDK.xcframework` at the repo root

## Build and run

```bash
xcodebuild -project BiometricID.xcodeproj \
           -scheme BiometricID \
           -destination 'platform=iOS Simulator,name=iPhone 16' \
           build
```

Or open `BiometricID.xcodeproj` in Xcode and press ⌘R.

---

## Documentation

Full documentation lives under [`Documentation/`](Documentation/):

- **[Architecture](Documentation/Architecture.md)** — module layout, data
  flow, and the sequence of state transitions across the SDK and the UI.
- **[Framework overview](Documentation/Framework.md)** — description of
  `BiometricidSDK`, its public surface (`config`, `login`, `registerUser`,
  the `isCoreMLModelLoaded` / `configurationError` publishers) and the
  `BiometricIDError` taxonomy.
- **[Usage guide](Documentation/Usage.md)** — step-by-step integration:
  linking the xcframework, Info.plist keys, bootstrapping, subscribing to
  publishers, invoking `login` / `registerUser`, and presenting results.

## Support

Questions, bug reports and feature requests: **support@biometricid.eu.com**
