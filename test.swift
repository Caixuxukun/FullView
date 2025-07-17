import UIKit
import WebKit

// MARK: –– 浏览器控制器
class BrowserViewController: UIViewController, WKNavigationDelegate {
    private var webView: WKWebView!
    private var hasPrompted = false

    // 1. 隐藏状态栏
    override var prefersStatusBarHidden: Bool { true }

    // 2. 隐藏 Home 指示条，延迟底部手势
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .bottom }

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
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // 5. 通知系统更新手势延迟和指示条隐藏
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        setNeedsUpdateOfHomeIndicatorAutoHidden()

        // 6. 只弹一次输入框
        guard !hasPrompted else { return }
        hasPrompted = true
        promptForURL()
    }

    private func promptForURL() {
        let alert = UIAlertController(
            title: "请输入网址",
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField {
            $0.placeholder = "https://example.com"
            $0.keyboardType = .URL
            $0.clearButtonMode = .whileEditing
        }
        alert.addAction(.init(title: "确定", style: .default) { [weak self] _ in
            guard
                let s = alert.textFields?.first?.text,
                let url = URL(string: s.hasPrefix("http") ? s : "https://\(s)")
            else {
                // 输入无效，允许重试
                self?.hasPrompted = false
                return
            }
            self?.webView.load(URLRequest(url: url))
        })
        present(alert, animated: true)
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
        // 7. 手动创建 window，不使用 Storyboard
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = BrowserViewController()
        window?.makeKeyAndVisible()
        return true
    }
}