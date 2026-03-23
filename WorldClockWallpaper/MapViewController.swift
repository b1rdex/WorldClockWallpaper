import AppKit
import WebKit

/// Breaks the retain cycle between WKUserContentController and WKScriptMessageHandler.
/// WKUserContentController holds a strong ref to its message handler, which would
/// otherwise prevent MapViewController from being deallocated.
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

final class MapViewController: NSViewController, WKScriptMessageHandler {

    private var webView: WKWebView!

    var cities: [City] = [] {
        didSet { pushCitiesToJS() }
    }

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.userContentController.add(WeakScriptMessageHandler(self), name: "cityBridge")
        webView = WKWebView(frame: .zero, configuration: config)
        // underPageBackgroundColor avoids any flash of white before the HTML background renders.
        // Deployment target is 13.0, so no availability guard needed.
        webView.underPageBackgroundColor = .black
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadMap()
    }

    private func loadMap() {
        guard let url = Bundle.main.url(forResource: "map", withExtension: "html") else {
            // map.html is only present in the main app bundle, not in the test runner bundle.
            // A missing resource is a configuration error; log it but do not crash.
            print("WorldClockWallpaper: map.html not found in bundle — check Copy Bundle Resources phase")
            return
        }
        // allowingReadAccessTo grants WKWebView read access to the whole bundle Resources dir,
        // so it can load sibling d3, topojson, suncalc, and world-110m.json files.
        let resourceDir = Bundle.main.resourceURL ?? url.deletingLastPathComponent()
        webView.loadFileURL(url, allowingReadAccessTo: resourceDir)
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
