import SwiftUI

/// Modal enrollment form presented when the user taps **Enroll Face** on
/// ``ContentView``.
///
/// Collects a first and last name, validates them, and — on confirmation —
/// dismisses itself and hands the trimmed values back to the caller via the
/// ``onRegister`` closure. The parent (``ContentView``) forwards those
/// values to ``BiometricViewModel/register(firstName:lastName:)``, which in
/// turn calls
/// ``BiometricidSDK/BiometricIDSDK/registerUser(firstName:lastName:completion:)``.
///
/// ## Validation rules
///
/// - Both fields are required; ``isRegisterEnabled`` returns `true` only
///   when their `whitespaces`-trimmed values are non-empty.
/// - Register button reflects that predicate via `.disabled(!isRegisterEnabled)`,
///   so it flips off the moment either field becomes empty (including all
///   characters deleted or reduced to whitespace).
///
/// ## Interaction details
///
/// - First name gets focus on appear; keyboard's *Next* moves focus to the
///   last-name field; *Done* on the last-name field triggers ``submit()``
///   when the form is valid.
/// - Swipe-to-dismiss is blocked while the user has typed anything, to
///   protect from accidental data loss.
/// - Actual invocation of the caller's `onRegister` is delayed 0.35 s after
///   `dismiss()` so the sheet is fully off screen before the SDK presents
///   its own `UIWindow` for camera capture.
struct EnrollFaceView: View {

    /// Sheet-dismissal environment action.
    @Environment(\.dismiss) private var dismiss

    /// Raw text bound to the first-name text field.
    @State private var firstName: String = ""

    /// Raw text bound to the last-name text field.
    @State private var lastName: String = ""

    /// Focus binding used by both text fields.
    @FocusState private var focusedField: Field?

    /// Callback invoked with the trimmed values when the user submits the
    /// form successfully.
    ///
    /// - Parameters (of the closure):
    ///   - firstName: Trimmed given name.
    ///   - lastName: Trimmed family name.
    let onRegister: (String, String) -> Void

    /// Tags for the two focusable text fields.
    private enum Field: Hashable {
        /// First-name text field.
        case firstName
        /// Last-name text field.
        case lastName
    }

    /// `firstName` with leading/trailing whitespace stripped.
    private var trimmedFirst: String {
        firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `lastName` with leading/trailing whitespace stripped.
    private var trimmedLast: String {
        lastName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether the **Register** button is enabled.
    ///
    /// `true` iff both trimmed inputs are non-empty.
    private var isRegisterEnabled: Bool {
        !trimmedFirst.isEmpty && !trimmedLast.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("First name", text: $firstName)
                        .textContentType(.givenName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .focused($focusedField, equals: .firstName)
                        .onSubmit { focusedField = .lastName }

                    TextField("Last name", text: $lastName)
                        .textContentType(.familyName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($focusedField, equals: .lastName)
                        .onSubmit {
                            if isRegisterEnabled { submit() }
                        }
                } header: {
                    Text("Your name")
                } footer: {
                    Text("Both fields are required.")
                }
            }
            .navigationTitle("Enroll Face")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Register") { submit() }
                        .disabled(!isRegisterEnabled)
                }
            }
            .onAppear { focusedField = .firstName }
        }
        .interactiveDismissDisabled(!firstName.isEmpty || !lastName.isEmpty)
    }

    /// Dismisses the sheet and then hands the trimmed values to
    /// ``onRegister``.
    ///
    /// The 0.35 s delay after `dismiss()` gives SwiftUI time to fully
    /// tear the sheet's presentation down before the SDK stacks its own
    /// `UIWindow` on top of the root scene for the camera preview.
    private func submit() {
        let f = trimmedFirst
        let l = trimmedLast
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            onRegister(f, l)
        }
    }
}

#Preview {
    EnrollFaceView { first, last in
        print("register \(first) \(last)")
    }
}
