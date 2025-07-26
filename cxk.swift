import UIKit
import WebKit

class BrowserViewController: UIViewController, WKNavigationDelegate, UITextFieldDelegate {
    private var webView: WKWebView!
    private var urlTextField: UITextField!

    /// 覆盖层，展示每帧 hook.frame
    private let frameImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.isHidden = true
        return iv
    }()

    private var displayLink: CADisplayLink?
    private var isFetchingFrame = false

    // 1. 隐藏状态栏
    override var prefersStatusBarHidden: Bool { true }

    // 2. 延迟底部手势
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { [.top, .bottom] }

    override func viewDidLoad() {
        super.viewDidLoad()

        // —— 初始化 webView —— 
        webView = WKWebView(frame: view.bounds)
        webView.navigationDelegate = self
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if #available(iOS 11.0, *) {
            webView.scrollView.contentInsetAdjustmentBehavior = .never
        } else {
            automaticallyAdjustsScrollViewInsets = false
        }
        view.addSubview(webView)

        // —— URL 输入框 —— 
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

        // —— 添加 frameImageView —— 
        view.addSubview(frameImageView)
        NSLayoutConstraint.activate([
            frameImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            frameImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            frameImageView.topAnchor.constraint(equalTo: view.topAnchor),
            frameImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // —— 启动抓帧循环 —— 
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
            dl.preferredFrameRateRange = CAFrameRateRange(minimum: 60,
                                                         maximum: 60,
                                                         preferred: 60)
        } else {
            dl.preferredFramesPerSecond = 60
        }
        dl.add(to: .main, forMode: .common)
        displayLink = dl
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func fetchFrame() {
        // 串行化调用，防止并发
        guard !isFetchingFrame else { return }
        isFetchingFrame = true

        webView.evaluateJavaScript("window.hook.frame") { [weak self] result, error in
            defer { self?.isFetchingFrame = false }
            guard let self = self, error == nil else { return }

            if let arr = result as? [UInt8], !arr.isEmpty {
                // 有新帧，渲染并确保 webView 可见
                let data = Data(arr)
                self.renderFrame(data)
                DispatchQueue.main.async {
                    self.webView.isHidden = false
                }
            } else {
                // hook.frame == null：隐藏 webView
                DispatchQueue.main.async {
                    self.webView.isHidden = true
                    self.frameImageView.isHidden = true
                }
            }

            // 清空 JS 端 frame，准备下一次
            self.webView.evaluateJavaScript("window.hook.frame = null;", completionHandler: nil)
        }
    }

    private func renderFrame(_ data: Data) {
        DispatchQueue.main.async {
            self.frameImageView.isHidden = false
        }

        let scale = UIScreen.main.scale
        let w = Int(self.webView.bounds.width * scale)
        let h = Int(self.webView.bounds.height * scale)

        data.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            let provider = CGDataProvider(dataInfo: nil,
                                          data: base,
                                          size: data.count,
                                          releaseData: {_,_,_ in })
            let cg = CGImage(width: w,
                             height: h,
                             bitsPerComponent: 8,
                             bitsPerPixel: 32,
                             bytesPerRow: w * 4,
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