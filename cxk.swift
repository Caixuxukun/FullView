import UIKit
import WebKit
import Metal
import CoreImage
import IOSurface

// MARK: –– 透传触摸的 UIImageView
class PassthroughImageView: UIImageView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // 永远不吞事件，事件会继续传给下层 webView
        return false
    }
}

// MARK: –– 主浏览器控制器
class BrowserViewController: UIViewController, WKNavigationDelegate, UITextFieldDelegate {
    private var webView: WKWebView!
    private var urlTextField: UITextField!
    private let frameImageView = PassthroughImageView()
    private var displayLink: CADisplayLink?
    private let ciContext = CIContext(mtlDevice: MTLCreateSystemDefaultDevice()!)

    // 隐藏状态栏
    override var prefersStatusBarHidden: Bool { true }
    // 延迟系统底部手势
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { [.top, .bottom] }

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
        urlTextField = UITextField(frame: .zero)
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

        // 3. 覆盖层：展示原生渲染帧
        frameImageView.translatesAutoresizingMaskIntoConstraints = false
        frameImageView.contentMode = .scaleAspectFit
        frameImageView.isHidden = true
        view.addSubview(frameImageView)
        NSLayoutConstraint.activate([
            frameImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            frameImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            frameImageView.topAnchor.constraint(equalTo: view.topAnchor),
            frameImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // 4. 启动原生 120Hz 渲染循环
        startNativeDisplayLink()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
    }

    // MARK: –– 原生 120Hz 渲染
    private func startNativeDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(renderNativeFrame))
        if #available(iOS 15.0, *) {
            displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 120,
                                                                    maximum: 120,
                                                                    preferred: 120)
        } else {
            displayLink?.preferredFramesPerSecond = 120
        }
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func renderNativeFrame() {
        guard let surface = webView.nextIOSurface() else {
            frameImageView.isHidden = true
            return
        }
        // 将 IOSurface → CIImage → CGImage → UIImage
        let ciImage = CIImage(ioSurface: surface)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        let uiImage = UIImage(cgImage: cgImage)

        DispatchQueue.main.async {
            self.frameImageView.image = uiImage
            self.frameImageView.isHidden = false
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
        UIView.animate(withDuration: 0.25) {
            textField.alpha = 0
        }
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

// MARK: –– WKWebView 私有 API 扩展
extension WKWebView {
    /// 取出内部 CAMetalLayer 的下一个 IOSurface
    func nextIOSurface() -> IOSurfaceRef? {
        // 1. 拿到私有的 content view
        guard let scroll = value(forKey: "scrollView") as? UIScrollView,
              let wkContent = scroll.value(forKey: "web_DynamicViewportContentView") as? UIView
        else { return nil }

        // 2. 递归查找 Metal Layer
        func findMetalLayer(in layer: CALayer) -> CAMetalLayer? {
            if let metal = layer as? CAMetalLayer { return metal }
            for sub in layer.sublayers ?? [] {
                if let m = findMetalLayer(in: sub) { return m }
            }
            return nil
        }

        guard let metalLayer = findMetalLayer(in: wkContent.layer),
              let drawable = metalLayer.nextDrawable()
        else { return nil }

        return drawable.texture.iosurface
    }
}