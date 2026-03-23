import AppKit
import WebKit

/// Breaks the retain cycle between WKUserContentController and WKScriptMessageHandler.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: (NSObject & WKScriptMessageHandler)?

    init(_ delegate: NSObject & WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ ucc: WKUserContentController,
                                didReceive message: WKScriptMessage) {
        delegate?.userContentController(ucc, didReceive: message)
    }
}

final class MapViewController: NSViewController, WKScriptMessageHandler, WKNavigationDelegate {

    private var webView: WKWebView!

    var cities: [City] = [] {
        didSet { pushCitiesToJS() }
    }

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.userContentController.add(WeakScriptMessageHandler(self), name: "cityBridge")
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.underPageBackgroundColor = .black
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadMap()
    }

    private func loadMap() {
        guard let htmlURL = Bundle.main.url(forResource: "map", withExtension: "html"),
              var html = try? String(contentsOf: htmlURL, encoding: .utf8) else {
            NSLog("WCW: map.html not found in bundle")
            return
        }

        // Inline every <script src="filename.js"></script> from the bundle.
        // This is required under App Sandbox: WKWebView's WebContent process cannot
        // read file:// URLs from the app bundle, but Swift can.
        let scriptPattern = try! NSRegularExpression(
            pattern: #"<script src="([^"]+\.js)"></script>"#
        )
        let range = NSRange(html.startIndex..., in: html)
        let matches = scriptPattern.matches(in: html, range: range)

        // Process in reverse order so string offsets stay valid
        for match in matches.reversed() {
            guard let fileNameRange = Range(match.range(at: 1), in: html),
                  let fileURL = Bundle.main.url(
                      forResource: String(html[fileNameRange].dropLast(3)),
                      withExtension: "js"
                  ),
                  let src = try? String(contentsOf: fileURL, encoding: .utf8),
                  let fullMatchRange = Range(match.range(at: 0), in: html) else { continue }
            html.replaceSubrange(fullMatchRange, with: "<script>\(src)</script>")
        }

        webView.loadHTMLString(html, baseURL: Bundle.main.resourceURL)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        NSLog("WCW load failed: %@", error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        injectWorldData()
        pushCitiesToJS()
    }

    /// Reads world-110m.json from the bundle in Swift (no file:// fetch in WebView)
    /// and calls window.initMap(data) which was defined in map.html.
    private func injectWorldData() {
        guard let jsonURL = Bundle.main.url(forResource: "world-110m", withExtension: "json"),
              let jsonData = try? Data(contentsOf: jsonURL),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            NSLog("WCW: world-110m.json not found")
            return
        }
        webView.evaluateJavaScript("window.initMap(\(jsonString))", completionHandler: nil)
    }

    private func pushCitiesToJS() {
        guard webView != nil,
              let data = try? JSONEncoder().encode(cities),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.updateCities(\(json))", completionHandler: nil)
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController,
                                didReceive message: WKScriptMessage) {
        if message.name == "cityBridge" {
            pushCitiesToJS()
        }
    }
}
