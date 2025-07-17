import UIKit
import WebKit

class ViewController: UIViewController, WKNavigationDelegate {
    
    private var webView: WKWebView!
    
    // MARK: - 生命周期
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupWebView()
        promptForURL()
    }
    
    // MARK: - WebView 初始化
    
    private func setupWebView() {
        // 创建并添加到 self.view
        webView = WKWebView(frame: view.bounds)
        webView.navigationDelegate = self
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(webView)
    }
    
    // MARK: - 弹框输入网址
    
    private func promptForURL() {
        let alert = UIAlertController(title: "请输入网址",
                                      message: nil,
                                      preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "https://example.com"
            textField.keyboardType = .URL
            textField.clearButtonMode = .whileEditing
        }
        let ok = UIAlertAction(title: "确定", style: .default) { [weak self] _ in
            guard let str = alert.textFields?.first?.text,
                  let url = URL(string: str.hasPrefix("http") ? str : "https://\(str)") else {
                // 输入无效，重新弹框
                self?.promptForURL()
                return
            }
            self?.webView.load(URLRequest(url: url))
        }
        alert.addAction(ok)
        present(alert, animated: true)
    }
    
    // MARK: - 隐藏 Home Indicator（需要两次上滑才能退出）
    
    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }
    
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        // 告诉系统：底部边缘的手势应当延迟处理
        return .bottom
    }
    
    // 当界面需要更新时，主动调用
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
    }
}