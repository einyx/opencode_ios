import SwiftUI

/// The licences of the packages the app links.
///
/// The notices ship inside the app as a resource, generated from the resolved
/// package graph by `scripts/generate_third_party_notices.py`, so the text
/// cannot drift away from what is actually linked.
struct OpenSourceLicencesView: View {
    private static let noticesResource = "ThirdPartyNotices"

    private var notices: String {
        guard let url = Bundle.main.url(forResource: Self.noticesResource, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return L10n.t(.settingsOpenSourceLicencesMissing)
        }
        return text
    }

    var body: some View {
        ScrollView {
            Text(notices)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DesignSpacing.lg)
                .accessibilityIdentifier("settings-open-source-licences-text")
        }
        .navigationTitle(L10n.t(.settingsOpenSourceLicences))
        .navigationBarTitleDisplayMode(.inline)
    }
}
