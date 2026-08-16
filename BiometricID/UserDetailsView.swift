import SwiftUI
@preconcurrency import BiometricidSDK

/// Read-only detail screen shown after a successful sign-in or registration.
///
/// Displays the ``BiometricidSDK/BiometricidUser`` payload returned by the
/// SDK and offers a single **OK** action that dismisses the enclosing
/// presentation.
///
/// The view is presented from ``ContentView`` via `fullScreenCover(item:)`
/// bound to ``BiometricViewModel/authenticatedUser``. It is embedded in its
/// own `NavigationStack` there so that ``navigationTitle(_:)`` and
/// ``navigationBarBackButtonHidden(_:)`` take effect.
struct UserDetailsView: View {

    /// The user returned by the SDK on success. Rendered read-only.
    let user: BiometricidUser

    /// Cover-dismissal environment action. Invoked by the OK button.
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "person.crop.circle.fill.badge.checkmark")
                    .font(.system(size: 72))
                    .foregroundStyle(.tint)
                Text("\(user.firstName) \(user.lastName)")
                    .font(.title2.weight(.semibold))
            }
            .padding(.top, 24)

            VStack(spacing: 12) {
                infoRow(title: "User ID", value: user.userId)
                infoRow(title: "First name", value: user.firstName)
                infoRow(title: "Last name", value: user.lastName)
                infoRow(
                    title: "Last login",
                    value: user.lastLoginDate.formatted(date: .abbreviated, time: .shortened)
                )
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("OK")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.bottom)
        }
        .navigationTitle("Welcome")
        .navigationBarBackButtonHidden(true)
    }

    /// Renders a labelled key/value row used inside the details card.
    ///
    /// - Parameters:
    ///   - title: Left-aligned caption in secondary color.
    ///   - value: Right-aligned value in the row's primary color.
    /// - Returns: A view laying `title` and `value` on the same baseline.
    private func infoRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
        }
    }
}
