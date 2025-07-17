import UIKit
import WebKit

// MARK: –– 浏览器主体
class BrowserViewController: UIViewController, WKNavigationDelegate {
    private var webView: WKWebView!

    // 隐藏 Home 指示条，需要连滑两次才能退出
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .bottom }

    override func viewDidLoad() {
        super.viewDidLoad()

        // 1. 全屏创建 WKWebView
        webView = WKWebView(frame: view.bounds)
        webView.navigationDelegate = self
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(webView)

        // 2. 弹框输入 URL
        promptForURL()
    }

    private func promptForURL() {
        let alert = UIAlertController(title: "请输入网址",
                                      message: nil,
                                      preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "https://example.com"
            tf.keyboardType = .URL
            tf.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self] _ in
            guard
                let s = alert.textFields?.first?.text,
                let url = URL(string: s.hasPrefix("http") ? s : "https://\(s)")
            else {
                // 无效输入，重试
                self?.promptForURL()
                return
            }
            self?.webView.load(URLRequest(url: url))
        })
        present(alert, animated: true)
    }
}

// MARK: –– 应用入口
@UIApplicationMain    // 自动生成 main()
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
      _ application: UIApplication,
      didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // 创建 window 并以 BrowserViewController 为根
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = BrowserViewController()
        window?.makeKeyAndVisible()
        return true
    }
}