import SafariServices
import SwiftUI

/// RYFT's legal pages, opened in-app (SFSafariViewController).
enum LegalPage: String, Identifiable {
    case privacy, terms

    var id: String { rawValue }

    var url: URL {
        switch self {
        case .privacy: return URL(string: "https://ryftapp.de/privacy")!
        case .terms: return URL(string: "https://ryftapp.de/terms")!
        }
    }

    /// Our own links in Markdown text are opened in-app too.
    init?(url: URL) {
        guard url.host == "ryftapp.de" else { return nil }
        switch url.path {
        case "/privacy": self = .privacy
        case "/terms": self = .terms
        default: return nil
        }
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = UIColor(named: "Accent")
        return vc
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

extension View {
    /// Presents `page` in an in-app Safari sheet, and routes taps on our legal
    /// links in Markdown text to it.
    func safariSheet(_ page: Binding<LegalPage?>) -> some View {
        sheet(item: page) { SafariView(url: $0.url).ignoresSafeArea() }
            .environment(\.openURL, OpenURLAction { url in
                guard let legal = LegalPage(url: url) else { return .systemAction }
                page.wrappedValue = legal
                return .handled
            })
    }
}
