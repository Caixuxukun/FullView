import UIKit
import WebKit
import Metal
import IOSurface

// MARK: –– 透传触摸的 UIImageView
class PassthroughImageView: UIImageView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return false
    }
}

// MARK: –– 主浏览器控制器
class BrowserViewController: UIViewController, WKNavigationDelegate, UITextFieldDelegate {
    private var webView: WKWebView!
    private var urlTextField: UITextField!
    private let frameImageView = PassthroughImageView()
    private var displayLink: CADisplayLink?

    // 隐藏状态栏
    override var prefersStatusBarHidden: Bool { true }
    // 延迟系统底部手势
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { [.top, .bottom] }

    // JS 片段：隐藏/显示页面按钮
    private let hideButtonsJS = """
      document.getElementById('startBtn')?.style.setProperty('display','none','important');
      document.getElementById('stopBtn')?.style.setProperty('display','none','important');
    """
    private let showButtonsJS = """
      document.getElementById('startBtn')?.style.removeProperty('display');
      document.getElementById('stopBtn')?.style.removeProperty('display');
    """

    override func viewDidLoad() {
        super.viewDidLoad()

        // 1. 初始化 WKWebView
        webView = WKWebView(frame: view.bounds)
        webView.navigationDelegate = self
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if #available(iOS 11.0, *) {
            webView.scrollView.contentInsetAdjustmentBehavior = .never
        } else {
            automaticallyAdjustsScrollViewInsets = false
        }
        view.addSubview(webView)

        // 2. URL 输入框
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

        // 3. 覆盖层：直接把 IOSurface 贴到 layer.contents
        frameImageView.translatesAutoresizingMaskIntoConstraints = false
        frameImageView.contentMode = .scaleAspectFit
        frameImageView.isHidden = true
        frameImageView.layer.contentsGravity = .resizeAspect
        view.addSubview(frameImageView)
        NSLayoutConstraint.activate([
            frameImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            frameImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            frameImageView.topAnchor.constraint(equalTo: view.topAnchor),
            frameImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // 4. 启动 120Hz CADisplayLink
        startDisplayLink()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 不做任何 windowScene/screen 的额外设置
    }

    // MARK: –– CADisplayLink 120Hz
    private func startDisplayLink() {
        let dl = CADisplayLink(target: self, selector: #selector(renderNativeFrame))
        if #available(iOS 15.0, *) {
            dl.preferredFrameRateRange = CAFrameRateRange(minimum: 120,
                                                         maximum: 120,
                                                         preferred: 120)
        } else {
            dl.preferredFramesPerSecond = 120
        }
        dl.add(to: .main, forMode: .common)
        displayLink = dl
    }

    @objc private func renderNativeFrame() {
        if let surface = webView.nextIOSurface() {
            // 拿到 surface 就隐藏 webView 并隐藏 HTML 按钮
            webView.isHidden = true
            webView.evaluateJavaScript(hideButtonsJS, completionHandler: nil)

            // 直接把 IOSurface 贴到 layer.contents
            DispatchQueue.main.async {
                self.frameImageView.layer.contentsScale = UIScreen.main.scale
                self.frameImageView.layer.contents = surface
                self.frameImageView.isHidden = false
            }
        } else {
            // 没拿到 surface，就恢复 webView 和按钮
            webView.evaluateJavaScript(showButtonsJS, completionHandler: nil)
            DispatchQueue.main.async {
                self.webView.isHidden = false
                self.frameImageView.isHidden = true
            }
        }
    }

    // MARK: –– UITextFieldDelegate
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        if var s = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
           !s.isEmpty {
            if !s.hasPrefix("http://") && !s.hasPrefix("https://") {
                s = "https://\(s)"
            }
            if let url = URL(string: s) {
                webView.load(URLRequest(url: url))
            }
        }
        UIView.animate(withDuration: 0.25) { textField.alpha = 0 }
        return true
    }

    // MARK: –– WKNavigationDelegate
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
}

// MARK: –– 应用入口
@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = BrowserViewController()
        window?.makeKeyAndVisible()
        return true
    }
}

// MARK: –– WKWebView 原生 Layer 拓展
extension WKWebView {
    /// 递归查找 layer 树中的第一个 CAMetalLayer，并取它的 nextDrawable().texture.iosurface
    func nextIOSurface() -> IOSurfaceRef? {
        guard let metalLayer = findMetal(in: layer),
              let drawable = metalLayer.nextDrawable()
        else { return nil }
        return drawable.texture.iosurface
    }

    private func findMetal(in layer: CALayer) -> CAMetalLayer? {
        if let m = layer as? CAMetalLayer { return m }
        for sub in layer.sublayers ?? [] {
            if let found = findMetal(in: sub) { return found }
                }
        return nil
    }
}