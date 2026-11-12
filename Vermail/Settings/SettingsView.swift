import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 520, height: 240)
    }
}

struct GeneralSettingsView: View {
    @State private var language = AppLanguage.current()

    var body: some View {
        Form {
            Picker("Language:", selection: $language) {
                ForEach([AppLanguage.system] + AppLanguage.available()) { language in
                    if let nativeName = language.nativeName {
                        Text(verbatim: nativeName).tag(language)
                    } else {
                        Text("System").tag(language)
                    }
                }
            }
            .onChange(of: language) { _, newValue in
                newValue.apply()
            }
            Text("Requires restart")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}

#Preview {
    SettingsView()
}
