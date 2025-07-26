import UIKit
import WebKit

/// 一个永远不 “吞” 事件、把触摸全部透传给下层 webView 的 UIImageView
class PassthroughImageView: UIImageView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return false
    }
}

class BrowserViewController: UIViewController, WKNavigationDelegate, UITextFieldDelegate {
    private var webView: WKWebView!
    private var urlTextField: UITextField!

    /// 覆盖层，用来显示原生渲染的帧
    private let frameImageView: PassthroughImageView = {
        let iv = PassthroughImageView()
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.isHidden = true
        return iv
    }()

    private var displayLink: CADisplayLink?
    private var isFetchingFrame = false

    // 1. 隐藏状态栏
    override var prefersStatusBarHidden: Bool { true }
    // 2. 延迟系统底部手势
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { [.top, .bottom] }

    override func viewDidLoad() {
        super.viewDidLoad()

        // —— WKWebView —— //
        webView = WKWebView(frame: view.bounds)
        webView.navigationDelegate = self
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if #available(iOS 11.0, *) {
            webView.scrollView.contentInsetAdjustmentBehavior = .never
        } else {
            automaticallyAdjustsScrollViewInsets = false
        }
        view.addSubview(webView)

        // —— URL 输入框 —— //
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

        // —— 覆盖层 —— //
        view.addSubview(frameImageView)
        NSLayoutConstraint.activate([
            frameImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            frameImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            frameImageView.topAnchor.constraint(equalTo: view.topAnchor),
            frameImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // —— 启动 120Hz 拉取 —— //
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
        guard !isFetchingFrame else { return }
        isFetchingFrame = true

        webView.evaluateJavaScript("window.hook.frame") { [weak self] result, error in
            defer { self?.isFetchingFrame = false }
            guard let self = self, error == nil else { return }

            if let arr = result as? [UInt8], !arr.isEmpty {
                // 有帧数据：隐藏 webView，显示 overlay
                DispatchQueue.main.async {
                    self.webView.isHidden = true
                    self.frameImageView.isHidden = false
                }
                let data = Data(arr)
                self.renderFrame(data)
            } else {
                // 无帧数据或 null：隐藏 overlay，显示 webView
                DispatchQueue.main.async {
                    self.frameImageView.isHidden = true
                    self.webView.isHidden = false
                }
            }

            // 清空 JS 端 frame
            self.webView.evaluateJavaScript("window.hook.frame = null;", completionHandler: nil)
        }
    }

    private func renderFrame(_ data: Data) {
        let scale = UIScreen.main.scale
        let width = Int(webView.bounds.width * scale)
        let height = Int(webView.bounds.height * scale)

        data.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            let provider = CGDataProvider(dataInfo: nil,
                                          data: base,
                                          size: data.count,
                                          releaseData: {_,_,_ in })
            let cgImage = CGImage(width: width,
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
                self.frameImageView.image = UIImage(cgImage: cgImage!)
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