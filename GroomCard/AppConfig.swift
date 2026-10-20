import Foundation

/// The GroomCard website this app shows. If the website moves (for example to groomcard.app),
/// change `host` here and WKAppBoundDomains in project.yml, then build a new version.
enum AppConfig {
    static let host = "wouldbebn.pythonanywhere.com"
    static let home = URL(string: "https://\(host)/")!

    /// True for addresses that belong to GroomCard itself (they open inside the app).
    static func isGroomCard(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        return (scheme == "https" || scheme == "http") && url.host?.lowercased() == host
    }
}
