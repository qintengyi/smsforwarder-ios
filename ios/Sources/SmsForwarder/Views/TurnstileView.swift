import SwiftUI
import WebKit

// MARK: - Turnstile 配置

struct TurnstileConfig: Codable {
    let enabled: Bool
    let siteKey: String

    enum CodingKeys: String, CodingKey {
        case enabled
        case siteKey = "site_key"
    }
}

// MARK: - Turnstile WebView Coordinator

class TurnstileCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var onMessage: (String?) -> Void
    var onLoadError: (String) -> Void

    init(onMessage: @escaping (String?) -> Void, onLoadError: @escaping (String) -> Void) {
        self.onMessage = onMessage
        self.onLoadError = onLoadError
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any] else { return }
        guard let type = dict["type"] as? String else { return }

        switch type {
        case "token":
            let token = dict["token"] as? String ?? ""
            onMessage(token.isEmpty ? nil : token)
        case "expired":
            onMessage(nil)
        case "error":
            onLoadError(dict["message"] as? String ?? "验证组件出错")
        case "ready":
            // 脚本已加载，等待渲染
            break
        case "log":
            // 调试日志（不显示给用户）
            #if DEBUG
            print("[Turnstile] \(dict["message"] ?? "")")
            #endif
        default:
            break
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onLoadError("页面加载失败: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onLoadError("资源加载失败: \(error.localizedDescription)")
    }
}

// MARK: - Turnstile WebView Representable

struct TurnstileWebView: UIViewRepresentable {
    let siteKey: String
    let serverURL: String
    var onToken: (String?) -> Void
    var onError: (String) -> Void

    func makeCoordinator() -> TurnstileCoordinator {
        TurnstileCoordinator(
            onMessage: { token in
                onToken(token)
            },
            onLoadError: { msg in
                onError(msg)
            }
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "turnstile")
        config.userContentController = userContentController
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.preferences.javaScriptEnabled = true
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.translatesAutoresizingMaskIntoConstraints = false

        let html = generateHTML(siteKey: siteKey)
        // 使用面板服务器地址作为 baseURL，让 Turnstile 验证域名匹配
        let baseURL = URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)) ?? URL(string: "https://smsf.xiaoyyua.top")!
        webView.loadHTMLString(html, baseURL: baseURL)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
    }

    private func generateHTML(siteKey: String) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body {
                    background: transparent;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    min-height: 65px;
                    overflow: hidden;
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                }
                #ts-container { transform-origin: center; }
            </style>
        </head>
        <body>
            <div id="ts-container"></div>
            <script>
                // 使用显式渲染，确保脚本加载完成后再渲染
                function onTurnstileLoad() {
                    window.webkit.messageHandlers.turnstile.postMessage({type: 'log', message: 'API loaded, rendering...'});
                    try {
                        turnstile.render('#ts-container', {
                            sitekey: '\(siteKey)',
                            theme: 'light',
                            callback: function(token) {
                                window.webkit.messageHandlers.turnstile.postMessage({type: 'token', token: token});
                            },
                            'expired-callback': function() {
                                window.webkit.messageHandlers.turnstile.postMessage({type: 'expired'});
                            },
                            'error-callback': function(code) {
                                window.webkit.messageHandlers.turnstile.postMessage({type: 'error', message: '验证失败: ' + code});
                            }
                        });
                        window.webkit.messageHandlers.turnstile.postMessage({type: 'log', message: 'Render called'});
                    } catch(e) {
                        window.webkit.messageHandlers.turnstile.postMessage({type: 'error', message: '渲染异常: ' + e.message});
                    }
                }

                // 超时检测：10 秒后仍未获取 token，报告错误
                var tsTimeout = setTimeout(function() {
                    if (!window.turnstile || !turnstile.getResponse || !turnstile.getResponse()) {
                        window.webkit.messageHandlers.turnstile.postMessage({type: 'error', message: '验证组件加载超时'});
                    }
                }, 10000);

                // 成功后清除超时
                var origCallback = onTurnstileLoad;
            </script>
            <script src="https://challenges.cloudflare.com/turnstile/v0/api.js?onload=onTurnstileLoad" async defer></script>
        </body>
        </html>
        """
    }
}

// MARK: - Turnstile 视图组件

struct TurnstileView: View {
    let siteKey: String
    let serverURL: String
    @State private var token: String? = nil
    @State private var hasError: Bool = false
    @State private var errorMessage: String = ""
    @State private var reloadTrigger: Int = 0
    var onTokenChange: (String?) -> Void

    var body: some View {
        VStack(spacing: 8) {
            TurnstileWebView(
                siteKey: siteKey,
                serverURL: serverURL,
                onToken: { newToken in
                    token = newToken
                    hasError = newToken == nil && errorMessage.isEmpty
                    onTokenChange(newToken)
                },
                onError: { msg in
                    errorMessage = msg
                    hasError = true
                    onTokenChange(nil)
                }
            )
            .id(reloadTrigger)
            .frame(height: 65)
            .frame(maxWidth: .infinity)

            if token == nil && !hasError {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("正在加载验证组件…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if hasError {
                VStack(spacing: 4) {
                    Text(errorMessage.isEmpty ? "验证组件加载失败" : errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button("重试") {
                        errorMessage = ""
                        hasError = false
                        token = nil
                        reloadTrigger += 1
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}
