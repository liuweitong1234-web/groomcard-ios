import UIKit
import WebKit

/// Shows the GroomCard website and adds what a plain website can't do on an iPhone:
/// phone reminders, a proper offline screen, the share sheet for backups, and opening
/// WhatsApp, Messages, Phone, Maps and Mail in their own apps.
final class WebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate,
                               WKScriptMessageHandler, WKDownloadDelegate {
    private var webView: WKWebView!
    private let offlineView = OfflineView()
    private let refreshControl = UIRefreshControl()
    private var downloadedFile: URL?

    override func loadView() {
        let contentController = WKUserContentController()
        contentController.add(WeakScriptMessageHandler(self), name: "groomcard")

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.websiteDataStore = .default()          // keeps you signed in
        config.limitsNavigationsToAppBoundDomains = true

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.backgroundColor = .white
        webView.isOpaque = false
        webView.translatesAutoresizingMaskIntoConstraints = false

        refreshControl.addTarget(self, action: #selector(pullToRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl

        offlineView.isHidden = true
        offlineView.translatesAutoresizingMaskIntoConstraints = false
        offlineView.onRetry = { [weak self] in self?.reload() }

        let root = UIView()
        root.backgroundColor = .white
        root.addSubview(webView)
        root.addSubview(offlineView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            offlineView.topAnchor.constraint(equalTo: root.topAnchor),
            offlineView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            offlineView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            offlineView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        webView.load(URLRequest(url: AppConfig.home))
        NotificationCenter.default.addObserver(self, selector: #selector(appBecameActive),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    /// Open a page of GroomCard, for example "/#/day/2026-10-21" from a reminder.
    func open(path: String) {
        loadViewIfNeeded()
        guard let url = URL(string: path, relativeTo: AppConfig.home)?.absoluteURL, AppConfig.isGroomCard(url) else { return }
        offlineView.isHidden = true
        webView.load(URLRequest(url: url))
    }

    @objc private func pullToRefresh() { reload() }

    @objc private func appBecameActive() {
        Reminders.reportPermission(to: webView)
        if !offlineView.isHidden { reload() }
    }

    private func reload() {
        offlineView.isHidden = true
        if webView.url == nil {
            webView.load(URLRequest(url: AppConfig.home))
        } else {
            webView.reload()
        }
    }

    // MARK: - Where links go

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        let scheme = url.scheme?.lowercased() ?? ""
        if AppConfig.isGroomCard(url) || scheme == "about" || scheme == "blob" || scheme == "data" {
            decisionHandler(.allow)
            return
        }
        // WhatsApp, text messages, phone calls, Google Maps, email and other websites open in their own apps.
        UIApplication.shared.open(url)
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let http = navigationResponse.response as? HTTPURLResponse,
           let disposition = http.value(forHTTPHeaderField: "Content-Disposition"),
           disposition.lowercased().contains("attachment") {
            decisionHandler(.download)
            return
        }
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    /// Links that open a new window (target="_blank").
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            if AppConfig.isGroomCard(url) {
                webView.load(navigationAction.request)
            } else {
                UIApplication.shared.open(url)
            }
        }
        return nil
    }

    // MARK: - Loading and offline

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshControl.endRefreshing()
        offlineView.isHidden = true
        Reminders.reportPermission(to: webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadingFailed(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadingFailed(error)
    }

    private func loadingFailed(_ error: Error) {
        refreshControl.endRefreshing()
        let nsError = error as NSError
        // Cancelled loads, and loads handed to a download or another app, aren't real failures.
        if nsError.code == NSURLErrorCancelled || (nsError.domain == "WebKitErrorDomain" && nsError.code == 102) {
            return
        }
        offlineView.isHidden = false
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        reload()
    }

    // MARK: - Pop-ups ("Delete this booking?")

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        if !showOnTop(alert) { completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        if !showOnTop(alert) { completionHandler(false) }
    }

    /// Shows a pop-up on top of whatever is showing. Returns false if it can't be shown right now.
    @discardableResult
    private func showOnTop(_ controller: UIViewController) -> Bool {
        var top: UIViewController = self
        while let presented = top.presentedViewController {
            if presented.isBeingDismissed { break }
            top = presented
        }
        if top is UIAlertController { return false }
        controller.popoverPresentationController?.sourceView = view
        controller.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        top.present(controller, animated: true)
        return true
    }

    // MARK: - Backups: download, then the iPhone share sheet (Save to Files, Mail, AirDrop...)

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let name = suggestedFilename.isEmpty ? "groomcard-backup.csv" : suggestedFilename
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: file)
        downloadedFile = file
        completionHandler(file)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let file = downloadedFile else { return }
        showOnTop(UIActivityViewController(activityItems: [file], applicationActivities: nil))
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let alert = UIAlertController(title: "Download failed",
                                      message: "The backup couldn't be downloaded. Please check your internet and try again.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        showOnTop(alert)
    }

    // MARK: - Messages from the website (phone reminders)

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              message.frameInfo.securityOrigin.host.lowercased() == AppConfig.host,
              let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        switch type {
        case "reminders":
            Reminders.update(from: body, webView: webView)
        case "clear":
            Reminders.clearAll()
        default:
            break
        }
    }
}

/// Lets the web view send messages to the screen without keeping it alive forever.
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
