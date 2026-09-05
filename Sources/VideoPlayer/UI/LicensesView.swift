import SwiftUI

struct LicensesView: View {
    private let notices = licenseText(named: "THIRD-PARTY-NOTICES")
    private let license = licenseText(named: "MPVKit-LGPL-3.0")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Open Source Licenses")
                    .font(.title2.weight(.semibold))

                Text(notices)

                Divider()

                Text(license)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }
}

private func licenseText(named name: String) -> String {
    guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
          let text = try? String(contentsOf: url, encoding: .utf8) else {
        return "License text is unavailable."
    }
    return text
}

struct LicensesCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Legal") {
            Button("Open Source Licenses…") {
                openWindow(id: "licenses")
            }
        }
    }
}
