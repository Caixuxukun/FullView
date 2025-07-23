import UIKit
import WebKit
import ObjectiveC.runtime
import ObjectiveC.message

// MARK: - 私有SPI封装
private func disablePrefer60FPS(on config: WKWebViewConfiguration) {
    let candidates = [
        "_setPreferPageRenderingUpdatesNear60FPSEnabled:",
        "setPreferPageRenderingUpdatesNear60FPSEnabled:"
    ]
    for name in candidates {
        let sel = NSSelectorFromString(name)
        if config.responds(to: sel) {
            typealias F = @convention(c) (AnyObject, Selector, Bool) -> Void
            let imp = config.method(for: sel)
            let f = unsafeBitCast(imp, to: F.self)
            f(config, sel, false)
            return
        }
    }
    // Fallback：KVC（有崩溃风险）
    // 如果你敢用，可放开下一行（注意：一旦 key 不存在会直接 crash）
    //config.setValue(false, forKey: "PreferPageRenderingUpdatesNear60FPSEnabled")
}

// MARK: –– 浏览器控制器
class BrowserViewController: UIViewController, WKNavigationDelegate, UITextFieldDelegate {
    private var webView: WKWebView!
    private var urlTextField: UITextField!

    override var prefersStatusBarHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { [.top, .bottom] }

    override func viewDidLoad() {
        super.viewDidLoad()

        // 1. 创建配置并关闭 60fps
        let config = WKWebViewConfiguration()
        disablePrefer60FPS(on: config)

        // 2. 用该配置创建 WKWebView
        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.navigationDelegate = self
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        if #available(iOS 11.0, *) {
            webView.scrollView.contentInsetAdjustmentBehavior = .never
        } else {
            automaticallyAdjustsScrollViewInsets = false
        }
        view.addSubview(webView)

        // —— 中间的 UITextField —— //
        urlTextField = UITextField()
        urlTextField.borderStyle = .roundedRect
        urlTextField.placeholder = "https://example.com"
        urlTextField.keyboardType = .URL
        urlTextField.clearButtonMode = .whileEditing
        urlTextField.textAlignment = .center
        urlTextField.delegate = self
        urlTextField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(urlTextField)

        NSLayoutConstraint.activate([
            urlTextField.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            urlTextField.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            urlTextField.widthAnchor.constraint(equalToConstant: 250),
            urlTextField.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
    }

    // MARK: –– UITextFieldDelegate
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        if var input = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
           !input.isEmpty {
            if !input.hasPrefix("http://") && !input.hasPrefix("https://") {
                input = "https://\(input)"
            }
            if let url = URL(string: input) {
                webView.load(URLRequest(url: url))
            }
        }
        UIView.animate(withDuration: 0.25) { textField.alpha = 0 }
        return true
    }
}

// MARK: –– 应用入口
@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = BrowserViewController()
        window?.makeKeyAndVisible()
        return true
    }
}