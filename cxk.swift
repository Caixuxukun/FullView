import QuartzCore
import UIKit
import WebKit

// MARK: –– 浏览器控制器
class BrowserViewController: UIViewController, WKNavigationDelegate, UITextFieldDelegate {
    private var webView: WKWebView!
    private var urlTextField: UITextField!

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
        // 6. 通知系统更新手势延迟
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        // 3. 启动 CADisplayLink，跟随屏幕最高帧率：
        displayLink = CADisplayLink(target: self, selector: #selector(onDisplayLink(_:)))
        if #available(iOS 15.0, *) {
            // 让它跑到设备最高刷新率（ProMotion 就 120）
            let maxFPS = Float(UIScreen.main.maximumFramesPerSecond)
            displayLink?.preferredFrameRateRange = CAFrameRateRange(
                minimum: 1.0,
                maximum: maxFPS,
                preferred: maxFPS
            )
        } else {
            // iOS 14 及以下用这个：
            displayLink?.preferredFramesPerSecond = UIScreen.main.maximumFramesPerSecond
        }
        displayLink?.add(to: .main, forMode: .common)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 4. 关闭 DisplayLink
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func onDisplayLink(_ link: CADisplayLink) {
        // 每一帧都“poke” 一下 webView，让它跟上：
        webView.setNeedsDisplay()
    
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

        // 8. 输入完后隐藏文本框（可根据需求改为保留或再次显示）
        UIView.animate(withDuration: 0.25) {
            textField.alpha = 0
        }
        return true
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