import AppKit
import WebKit

/// Breaks the retain cycle between WKUserContentController and its script message handler.
///
/// WKUserContentController holds a **strong** reference to every registered
/// WKScriptMessageHandler. If MapViewController were registered directly, the
/// controller (owned by the WKWebViewConfiguration / WKWebView) would keep
/// MapViewController alive indefinitely, preventing it from being deallocated.
/// This lightweight wrapper holds only a weak reference to the real delegate,
/// so the cycle is broken and both objects can be released normally.
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
        guard let url = Bundle.main.url(forResource: "map", withExtension: "html") else {
            NSLog("WCW: map.html not found in bundle")
            return
        }
        let resourceDir = Bundle.main.resourceURL ?? url.deletingLastPathComponent()
        webView.loadFileURL(url, allowingReadAccessTo: resourceDir)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!,
                 withError error: Error) {
        NSLog("WCW provisional load failed: %@", error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        NSLog("WCW load failed: %@", error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        injectWorldData()
    }

    /// Reads world-50m.json from the bundle on a background thread, then calls window.initMap(data).
    private func injectWorldData() {
        guard let jsonURL = Bundle.main.url(forResource: "world-50m", withExtension: "json") else {
            NSLog("WCW: world-50m.json not found in bundle")
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let jsonString = try? String(contentsOf: jsonURL, encoding: .utf8) else {
                NSLog("WCW: failed to read world-50m.json")
                return
            }
            DispatchQueue.main.async {
                self?.webView.evaluateJavaScript("window.initMap(\(jsonString))", completionHandler: nil)
            }
        }
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
