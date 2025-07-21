import UIKit
import WebKit
import UIKit

/// 永久“申请”高刷率的管理器
class HighFPSManager {
    private var displayLink: CADisplayLink?

    /// 启动高刷申请（直到你手动 stop）
    func start(preferred: Float = 120) {
        guard displayLink == nil else { return }  // 避免重复创建

        // 1. Info.plist 里已设置 CADisableMinimumFrameDurationOnPhone = true
        // 2. 取设备支持的最大刷新率
        let maxFPS = Float(UIScreen.main.maximumFramesPerSecond)

        // 3. 构造首选范围
        let range = CAFrameRateRange(
            minimum: 30,
            maximum: maxFPS,
            preferred: preferred
        )

        // 4. 创建并配置 DisplayLink
        let dl = CADisplayLink(target: self, selector: #selector(dummyTick(_:)))
        dl.preferredFrameRateRange = range
        dl.add(to: .main, forMode: .common)

        displayLink = dl
    }

    /// 停止高刷申请
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func dummyTick(_ link: CADisplayLink) {
        // 空方法，只用来保持 DisplayLink 存活
    }
}
// MARK: –– 浏览器控制器
class BrowserViewController: UIViewController, WKNavigationDelegate, UITextFieldDelegate {
    private var webView: WKWebView!
    private var urlTextField: UITextField!
    
    // —— 新增：CADisplayLink 引用 —— //
    private var displayLink: CADisplayLink?

    // 1. 隐藏状态栏
    override var prefersStatusBarHidden: Bool { true }

    // 2. 延迟底部手势
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { return [.top, .bottom] }

    override func viewDidLoad() {
        super.viewDidLoad()

        // 3. 全屏创建 WKWebView
        webView = WKWebView(frame: view.bounds)
        webView.navigationDelegate = self
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // 4. 取消 Safe Area 对 content 的自动 inset
        if #available(iOS 11.0, *) {
            webView.scrollView.contentInsetAdjustmentBehavior = .never
        } else {
            automaticallyAdjustsScrollViewInsets = false
        }
        view.addSubview(webView)

        // —— 新增：在中间创建一个 UITextField —— //
        urlTextField = UITextField()
        urlTextField.borderStyle = .roundedRect
        urlTextField.placeholder = "https://example.com"
        urlTextField.keyboardType = .URL
        urlTextField.clearButtonMode = .whileEditing
        urlTextField.textAlignment = .center
        urlTextField.delegate = self
        urlTextField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(urlTextField)

        // 5. 约束：宽 250，高 40，水平垂直居中
        NSLayoutConstraint.activate([
            urlTextField.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            urlTextField.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            urlTextField.widthAnchor.constraint(equalToConstant: 250),
            urlTextField.heightAnchor.constraint(equalToConstant: 40)
        ])

        // —— 新增：配置并启动 CADisplayLink —— //
        let dl = CADisplayLink(target: self, selector: #selector(tick(_:)))
        if #available(iOS 15.0, *) {
            dl.preferredFrameRateRange = CAFrameRateRange(minimum: 120,
                                                         maximum: 120,
                                                         preferred: 120)
        } else {
            dl.preferredFramesPerSecond = 120
        }
        dl.add(to: .main, forMode: .common)
        displayLink = dl
        // 在 viewDidLoad 或 didFinish 导航时机：
        let fpsManager = HighFPSManager()
        fpsManager.start(preferred: 120)  // 从此开始无限申请 120Hz
        let stub = WKUserScript(
            source: "window.drawFrame = window.drawFrame || function(){};",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        webView.configuration.userContentController.addUserScript(stub)
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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 6. 通知系统更新手势延迟
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
    }

    // MARK: –– UITextFieldDelegate
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()

        // 7. 读取输入，补全协议头并加载
        if var input = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
           !input.isEmpty {
            if !input.hasPrefix("http://") && !input.hasPrefix("https://") {
                input = "https://\(input)"
            }
            if let url = URL(string: input) {
                webView.load(URLRequest(url: url))
            }
        }

        // 8. 输入完后隐藏文本框
        UIView.animate(withDuration: 0.25) {
            textField.alpha = 0
        }
        return true
    }

    // —— 新增：每帧回调 —— //
    @objc private func tick(_ link: CADisplayLink) {
        let js = """
        (function(){
            const fn = window.drawFrame;
            if (typeof fn === 'function') {
                fn(\(link.timestamp));
            }
        })();
        """
        webView.evaluateJavaScript(js) { result, error in
            if let error = error {
                print("⚠️ JS 调用失败:", error)
            }
        }
    }

    // —— 新增：销毁时停止 —— //
    deinit {
        displayLink?.invalidate()
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