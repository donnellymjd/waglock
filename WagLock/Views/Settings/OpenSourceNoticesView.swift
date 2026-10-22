import SwiftUI

struct OpenSourceNoticesView: View {
    private var notices: String {
        guard let url = Bundle.main.url(forResource: "OpenSourceNotices", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "Original attribution and license notices are available in the source repository's LICENSE and NOTICE.md files."
        }
        return text
    }

    var body: some View {
        ScrollView {
            Text(verbatim: notices)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .textSelection(.enabled)
        }
        .background(ColorTheme.primaryBackground.ignoresSafeArea())
        .foregroundStyle(ColorTheme.primaryText)
        .navigationTitle("Open Source Notices")
        .navigationBarTitleDisplayMode(.inline)
    }
}
