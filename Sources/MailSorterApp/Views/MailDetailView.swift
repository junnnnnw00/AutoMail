import SwiftUI
@preconcurrency import WebKit
import SharedKit

struct WebView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        // Proxy https image loads through URLSession to bypass WKWebView origin restrictions
        config.setURLSchemeHandler(ImageProxyHandler(), forURLScheme: "mailimg")
        let webView = WKWebView(frame: .zero, configuration: config)
        // Force light mode — prevents macOS dark mode from inverting email colors
        webView.appearance = NSAppearance(named: .aqua)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        nsView.loadHTMLString(styledHTML, baseURL: URL(string: "https://localhost/"))
    }

    // Injected before </head>: forces light color-scheme, sets Outlook-like base style
    private static let baseCSS = """
    <meta name="color-scheme" content="light">
    <style>
    :root { color-scheme: light !important; }
    html, body { background-color: #ffffff !important; }
    body {
        color: #1d1d1f;
        font-family: -apple-system, 'Helvetica Neue', Arial, sans-serif;
        font-size: 14px;
        line-height: 1.6;
        margin: 0;
        padding: 4px 0;
        overflow-x: hidden;
    }
    img { max-width: 100%; height: auto; background-color: #f2f2f7; }
    a { color: #0563C1; }
    pre { white-space: pre-wrap; word-break: break-word; font-family: inherit; }
    table { max-width: 100%; }
    </style>
    """

    private var styledHTML: String {
        var base: String
        if html.localizedCaseInsensitiveContains("<html") {
            if let r = html.range(of: "</head>", options: .caseInsensitive) {
                base = String(html[..<r.lowerBound]) + Self.baseCSS + "</head>" + String(html[r.upperBound...])
            } else if let r = html.range(of: "<head>", options: .caseInsensitive) {
                base = String(html[..<r.upperBound]) + Self.baseCSS + String(html[r.upperBound...])
            } else {
                base = "<head>\(Self.baseCSS)</head>" + html
            }
        } else {
            base = "<!DOCTYPE html><html><head><meta charset=\"utf-8\">\(Self.baseCSS)</head><body>\(html)</body></html>"
        }
        // Rewrite https:// image src attributes to go through the proxy handler
        let pattern = #"(?i)(src\s*=\s*["'])https://"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            base = regex.stringByReplacingMatches(
                in: base,
                range: NSRange(base.startIndex..., in: base),
                withTemplate: "$1mailimg://"
            )
        }
        return base
    }
}

private final class ImageProxyHandler: NSObject, WKURLSchemeHandler, @unchecked Sendable {
    private var activeTasks: [ObjectIdentifier: URLSessionDataTask] = [:]

    func webView(_ webView: WKWebView, start schemeTask: WKURLSchemeTask) {
        guard let url = schemeTask.request.url,
              var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            schemeTask.didFailWithError(URLError(.badURL)); return
        }
        comps.scheme = "https"
        guard let realURL = comps.url else {
            schemeTask.didFailWithError(URLError(.badURL)); return
        }

        var req = URLRequest(url: realURL, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        let id = ObjectIdentifier(schemeTask)
        nonisolated(unsafe) let capturedTask = schemeTask
        let task = URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.activeTasks[id] != nil else { return }
                self.activeTasks.removeValue(forKey: id)
                if let error { capturedTask.didFailWithError(error); return }
                guard let response, let data else {
                    capturedTask.didFailWithError(URLError(.badServerResponse)); return
                }
                capturedTask.didReceive(response)
                capturedTask.didReceive(data)
                capturedTask.didFinish()
            }
        }
        activeTasks[id] = task
        task.resume()
    }

    func webView(_ webView: WKWebView, stop schemeTask: WKURLSchemeTask) {
        let id = ObjectIdentifier(schemeTask)
        activeTasks[id]?.cancel()
        activeTasks.removeValue(forKey: id)
    }
}

struct MailDetailView: View {
    @EnvironmentObject var store: MailStore
    let mail: Mail

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(mail.subject)
                .font(.title2)
                .textSelection(.enabled)

            HStack {
                Image(systemName: "person.crop.circle")
                VStack(alignment: .leading) {
                    Text(mail.fromName ?? mail.fromAddress)
                        .font(.subheadline)
                    if mail.fromName != nil {
                        Text(mail.fromAddress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(mail.receivedAt, format: .dateTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            relabelBar

            Divider()

            WebView(html: mail.body)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
        }
        .padding(20)
        .onAppear {
            store.markAsSeen(mail: mail)
        }
        .onChange(of: mail.id) { _, _ in
            store.markAsSeen(mail: mail)
        }
    }

    private var relabelBar: some View {
        HStack {
            Text("분류:")
                .foregroundStyle(.secondary)
            ForEach(MailLabel.allCases, id: \.self) { label in
                let isActive = mail.labels.contains(label)
                if isActive {
                    Button {
                        store.toggleLabel(mail: mail, label: label)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: label.sfSymbol)
                            Text(label.displayName)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(label.color)
                } else {
                    Button {
                        store.toggleLabel(mail: mail, label: label)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: label.sfSymbol)
                            Text(label.displayName)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            Spacer()
            if mail.userOverridden {
                Label("사용자 라벨", systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if store.isModelTrained {
                Text("자동 (점수 \(String(format: "%.2f", mail.score)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("모델 미학습", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}
