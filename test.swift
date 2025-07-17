import UIKit
import WebKit

// MARK: –– 浏览器控制器
class BrowserViewController: UIViewController, WKNavigationDelegate {
    private var webView: WKWebView!
    private var hasPrompted = false  // 确保只弹一次

    override func viewDidLoad() {
        super.viewDidLoad()
        // 1. 全屏 WebView
        webView = WKWebView(frame: view.bounds)
        webView.navigationDelegate = self
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(webView)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasPrompted else { return }
        hasPrompted = true
        promptForURL()
    }

    private func promptForURL() {
        let alert = UIAlertController(title: "请输入网址",
                                      message: nil,
                                      preferredStyle: .alert)
        alert.addTextField {
            $0.placeholder = "https://example.com"
            $0.keyboardType = .URL
            $0.clearButtonMode = .whileEditing
        }
        alert.addAction(.init(title: "确定", style: .default) { [weak self] _ in
            guard
                let s = alert.textFields?.first?.text,
                let url = URL(string: s.hasPrefix("http") ? s : "https://\(s)"
            ) else {
                // 无效，重试
                self?.hasPrompted = false
                return
            }
            self?.webView.load(URLRequest(url: url))
        })
        present(alert, animated: true)
    }

    // 隐藏 Home 指示条，需要两次上滑才能退出
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .bottom }
}

// MARK: –– 应用入口
@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
      _ application: UIApplication,
      didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // 1. 不使用 Storyboard，手动创建 window
        window = UIWindow(frame: UIScreen.main.bounds)
        // 2. 根控制器设为我们的浏览器
        window?.rootViewController = BrowserViewController()
        window?.makeKeyAndVisible()
        return true
    }
}