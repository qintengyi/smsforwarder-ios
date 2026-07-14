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

// MARK: - Turnstile WebView 消息

enum TurnstileMessage {
    case token(String)
    case expired
    case error(String)
}

// MARK: - Turnstile WebView Coordinator

class TurnstileCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var onMessage: (TurnstileMessage) -> Void

    init(onMessage: @escaping (TurnstileMessage) -> Void) {
        self.onMessage = onMessage
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any] else { return }
        guard let type = dict["type"] as? String else { return }

        switch type {
        case "token":
            if let token = dict["token"] as? String {
                onMessage(.token(token))
            }
        case "expired":
            onMessage(.expired)
        case "error":
            let msg = dict["message"] as? String ?? "验证失败"
            onMessage(.error(msg))
        case "ready":
            onMessage(.token("")) // Signal ready (empty token)
        default:
            break
        }
    }
}

// MARK: - Turnstile WebView Representable

struct TurnstileWebView: UIViewRepresentable {
    let siteKey: String
    var onToken: (String?) -> Void

    func makeCoordinator() -> TurnstileCoordinator {
        TurnstileCoordinator { msg in
            switch msg {
            case .token(let token):
                onToken(token.isEmpty ? nil : token)
            case .expired:
                onToken(nil)
            case .error:
                onToken(nil)
            }
        }
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "turnstile")
        config.userContentController = userContentController
        config.websiteDataStore = WKWebsiteDataStore.default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.translatesAutoresizingMaskIntoConstraints = false

        let html = generateHTML(siteKey: siteKey)
        webView.loadHTMLString(html, baseURL: URL(string: "https://challenges.cloudflare.com"))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // No update needed
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
                .cf-turnstile {
                    transform-origin: center;
                }
            </style>
            <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>
        </head>
        <body>
            <div class="cf-turnstile"
                 data-sitekey="\(siteKey)"
                 data-theme="light"
                 data-callback="onTurnstileSuccess"
                 data-expired-callback="onTurnstileExpired"
                 data-error-callback="onTurnstileError"></div>
            <script>
                function onTurnstileSuccess(token) {
                    window.webkit.messageHandlers.turnstile.postMessage({type: 'token', token: token});
                }
                function onTurnstileExpired() {
                    window.webkit.messageHandlers.turnstile.postMessage({type: 'expired'});
                }
                function onTurnstileError() {
                    window.webkit.messageHandlers.turnstile.postMessage({type: 'error', message: '验证组件出错'});
                }
                // Fallback: if Turnstile auto-renders, also check via API
                window.addEventListener('load', function() {
                    setTimeout(function() {
                        if (window.turnstile && window.turnstile.getResponse) {
                            var token = window.turnstile.getResponse();
                            if (token) {
                                window.webkit.messageHandlers.turnstile.postMessage({type: 'token', token: token});
                            }
                        }
                    }, 3000);
                });
            </script>
        </body>
        </html>
        """
    }
}

// MARK: - Turnstile 视图组件

struct TurnstileView: View {
    let siteKey: String
    @State private var token: String? = nil
    @State private var hasError: Bool = false
    var onTokenChange: (String?) -> Void

    var body: some View {
        VStack(spacing: 8) {
            TurnstileWebView(siteKey: siteKey) { newToken in
                token = newToken
                hasError = newToken == nil
                onTokenChange(newToken)
            }
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
                Text("验证组件加载失败，请刷新重试")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
