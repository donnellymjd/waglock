import SwiftUI

struct NetworkVerificationView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Plain-language privacy details").font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                WagLockInfoCard(title: "Local storage", detail: "Imported files are encrypted and stored on this device. This build does not transfer vault media through an app backend.")
                Text("WHAT IOS MAY DO").font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                WagLockNavigationRow(symbol: "arrow.down.to.line", title: "Cloud file downloads", detail: "The system picker may fetch a file")
                WagLockNavigationRow(symbol: "square.and.arrow.up", title: "Export & sharing", detail: "Chosen destination apps receive unencrypted copies")
                Text("Open source helps you inspect behavior. These explanations do not replace an independent security review.")
                    .font(.body).foregroundStyle(ColorTheme.secondaryText)
                Text("Guest Mode and alternate icons do not make a vault undetectable.")
                    .font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                WagLockInfoCard(title: "Early test build", detail: "Portable recovery, protected metadata and independent alternative vaults are still in development. Keep independent originals.")
            }.padding(24)
        }.background(ColorTheme.primaryBackground.ignoresSafeArea()).navigationTitle("Offline & privacy")
            .navigationBarTitleDisplayMode(.inline)
    }
}
