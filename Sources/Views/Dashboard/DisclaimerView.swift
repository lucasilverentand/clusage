import SwiftUI

struct DisclaimerView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                disclaimerCard(
                    title: "Unofficial API",
                    icon: "exclamationmark.triangle.fill",
                    color: .orange,
                    texts: [
                        "Clusage is an independent, third-party app that is **not affiliated with, endorsed by, or supported by Anthropic**. It relies on an unofficial, undocumented API to retrieve your usage data.",
                        "This API could change or be removed at any time without notice, which would break this app's functionality. There is no guarantee of continued access.",
                    ]
                )

                disclaimerCard(
                    title: "Account Risk",
                    icon: "person.crop.circle.badge.exclamationmark",
                    color: .red,
                    texts: [
                        "By using this app, you acknowledge that accessing unofficial APIs may violate Anthropic's Terms of Service. While no enforcement action is guaranteed, Anthropic **could restrict, suspend, or terminate accounts** that use unofficial tools.",
                        "The developers of Clusage accept no responsibility for any consequences to your Anthropic account resulting from the use of this app.",
                    ]
                )

                disclaimerCard(
                    title: "Your Data",
                    icon: "lock.shield",
                    color: .green,
                    texts: [
                        "Clusage stores your OAuth token locally in the macOS Keychain. Your credentials and usage data **never leave your device** — there is no telemetry, analytics, or external data collection of any kind.",
                        "You can remove your accounts and their tokens at any time from this app.",
                    ]
                )

                disclaimerCard(
                    title: "No Warranty",
                    icon: "hand.raised",
                    color: .secondary,
                    texts: [
                        "This software is provided **as-is**, without any warranty of any kind, express or implied. Usage data displayed may be inaccurate, incomplete, or delayed. Do not rely on it for billing or compliance purposes.",
                    ]
                )
            }
            .padding(24)
        }
        .navigationTitle("Disclaimer")
        .navigationSubtitle("Please read before using Clusage")
        .toolbarTitleDisplayMode(.inline)
    }

    private func disclaimerCard(title: String, icon: String, color: Color, texts: [LocalizedStringKey]) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(color)

                ForEach(Array(texts.enumerated()), id: \.offset) { _, text in
                    Text(text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
