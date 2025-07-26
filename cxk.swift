import UIKit
import WebKit

class BrowserViewController: UIViewController, WKNavigationDelegate, UITextFieldDelegate {
    private var webView: WKWebView!
    private var urlTextField: UITextField!

    // 1. 隐藏状态栏
    override var prefersStatusBarHidden: Bool { true }

    // 2. 延迟底部手势
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { return [.top, .bottom] }
    
    /// 用于展示每一帧
    private let frameImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()
    private var displayLink: CADisplayLink?

    override func viewDidLoad() {
        super.viewDidLoad()

        // 1. 创建 WKWebView（不再注入 hook 脚本，假定已在页面里完成）
        webView = WKWebView(frame: view.bounds)
        webView.navigationDelegate = self
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if #available(iOS 11.0, *) {
            webView.scrollView.contentInsetAdjustmentBehavior = .never
        } else {
            automaticallyAdjustsScrollViewInsets = false
        }
        view.addSubview(webView)

        // 2. URL 输入框（同之前）
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

        // 3. 全屏加上 frameImageView，用来覆盖显示 hook 帧
        view.addSubview(frameImageView)
        NSLayoutConstraint.activate([
            frameImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            frameImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            frameImageView.topAnchor.constraint(equalTo: view.topAnchor),
            frameImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // 4. 启动 120Hz 拉取循环
        startDisplayLink()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
    }

    // MARK: –– CADisplayLink

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let dl = CADisplayLink(target: self, selector: #selector(fetchFrame))
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

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func fetchFrame() {
        // 直接从 JS 取 window.hook.frame
        webView.evaluateJavaScript("window.hook.frame") { [weak self] result, error in
            guard let self = self, error == nil,
                  let arr = result as? [UInt8], !arr.isEmpty
            else { return }

            let data = Data(arr)
            self.renderFrame(data)

            // 取完立即清空，确保下一次只拿新帧
            self.webView.evaluateJavaScript("window.hook.frame = null;", completionHandler: nil)
        }
    }

    private func renderFrame(_ data: Data) {
        // 假设 hook.frame 是 RGBA raw，尺寸与 webView 一致（按 scale 计算）
        let scale = UIScreen.main.scale
        let width = Int(webView.bounds.width * scale)
        let height = Int(webView.bounds.height * scale)

        data.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            let provider = CGDataProvider(dataInfo: nil,
                                          data: base,
                                          size: data.count,
                                          releaseData: { _,_,_ in })
            let cg = CGImage(width: width,
                             height: height,
                             bitsPerComponent: 8,
                             bitsPerPixel: 32,
                             bytesPerRow: width * 4,
                             space: CGColorSpaceCreateDeviceRGB(),
                             bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                             provider: provider!,
                             decode: nil,
                             shouldInterpolate: false,
                             intent: .defaultIntent)
            DispatchQueue.main.async {
                self.frameImageView.image = UIImage(cgImage: cg!)
            }
        }
    }

    // MARK: –– UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        if var urlStr = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
           !urlStr.isEmpty {
            if !urlStr.hasPrefix("http://") && !urlStr.hasPrefix("https://") {
                urlStr = "https://\(urlStr)"
            }
            if let url = URL(string: urlStr) {
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