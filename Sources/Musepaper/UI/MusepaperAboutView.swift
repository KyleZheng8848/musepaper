import SwiftUI

struct MusepaperAboutView: View {
    @ObservedObject private var language = LanguagePreferences.shared
    var close: () -> Void = {}

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text(AppIdentity.name)
                    .font(.largeTitle.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(L10n.tr("版本 \(AppVersion.display)"))
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            }
            Divider()
            SofunAIPublisherView()
            Link(L10n.tr("GitHub 开源主页"), destination: AppIdentity.repositoryURL)
                .foregroundStyle(MuseTheme.amber)
                .accessibilityLabel(L10n.tr("在浏览器打开 Musepaper GitHub 开源主页"))
            Text(AppIdentity.copyright)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(L10n.tr("关闭"), action: close)
                .buttonStyle(.plain)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 20)
                .padding(.vertical, 7)
                .background(Capsule().fill(MuseTheme.amber))
                .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(width: 420, height: 320)
        .foregroundStyle(MuseTheme.ink)
        .background(MuseTheme.canvas)
        .preferredColorScheme(.dark)
        .environment(\.locale, language.selection.locale)
    }
}
