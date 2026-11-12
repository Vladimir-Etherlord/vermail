import AppKit
import SwiftUI
import WebKit

struct MessageWebView: NSViewRepresentable {
    fileprivate struct ContentKey: Equatable {
        let htmlBody: String?
        let plainBody: String?
        let allowRemoteImages: Bool
    }

    let htmlBody: String?
    let plainBody: String?
    let allowRemoteImages: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let contentKey = ContentKey(
            htmlBody: htmlBody,
            plainBody: plainBody,
            allowRemoteImages: allowRemoteImages
        )
        guard context.coordinator.lastContentKey != contentKey else {
            return
        }
        context.coordinator.lastContentKey = contentKey
        context.coordinator.loadGeneration += 1
        let currentGeneration = context.coordinator.loadGeneration
        let htmlDocument = Self.buildHTMLDocument(htmlBody: htmlBody, plainBody: plainBody)

        Task { @MainActor in
            await context.coordinator.applyContentRuleList(
                to: webView,
                allowRemoteImages: allowRemoteImages
            )
            guard context.coordinator.loadGeneration == currentGeneration else { return }
            webView.loadHTMLString(htmlDocument, baseURL: nil)
        }
    }

    static func buildHTMLDocument(htmlBody: String?, plainBody: String?) -> String {
        let bodyContent: String
        if let htmlBody, !htmlBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            bodyContent = htmlBody
        } else {
            let escaped = escapeHTML(plainBody ?? "")
            bodyContent = "<pre class=\"vermail-plain\">\(escaped)</pre>"
        }

        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="color-scheme" content="light dark">
        <style>
            :root {
                color-scheme: light dark;
            }
            html, body {
                margin: 0;
                padding: 0;
                font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
                font-size: 13px;
                line-height: 1.5;
                word-wrap: break-word;
                overflow-wrap: break-word;
            }
            body {
                padding: 16px;
            }
            img {
                max-width: 100%;
                height: auto;
            }
            pre.vermail-plain {
                font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
                white-space: pre-wrap;
                margin: 0;
            }
        </style>
        </head>
        <body>\(bodyContent)</body>
        </html>
        """
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private static let ruleIdentifier = "com.etherlord.vermail.blockRemoteResources"
        private static let blockRulesJSON = """
        [
          {
            "trigger": { "url-filter": "^https?://" },
            "action": { "type": "block" }
          }
        ]
        """

        fileprivate var lastContentKey: ContentKey?
        var loadGeneration = 0
        private var cachedRuleList: WKContentRuleList?

        func applyContentRuleList(to webView: WKWebView, allowRemoteImages: Bool) async {
            let controller = webView.configuration.userContentController
            controller.removeAllContentRuleLists()
            guard !allowRemoteImages else { return }

            if let cachedRuleList {
                controller.add(cachedRuleList)
                return
            }

            if let compiled = try? await WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: Self.ruleIdentifier,
                encodedContentRuleList: Self.blockRulesJSON
            ) {
                cachedRuleList = compiled
                controller.add(compiled)
            }
        }

        func webView(
            _: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url
            {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
