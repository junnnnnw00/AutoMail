import Foundation

@MainActor
final class UpdateChecker: ObservableObject {
    static let repoAPI = "https://api.github.com/repos/junnnnnw00/AutoMail/releases/latest"
    static let installCommand = "curl -fsSL https://raw.githubusercontent.com/junnnnnw00/AutoMail/main/Scripts/install.sh | bash"

    @Published private(set) var latestVersion: String?
    @Published private(set) var updateAvailable = false

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func check() {
        Task {
            guard let url = URL(string: Self.repoAPI) else { return }
            var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            guard let (data, _) = try? await URLSession.shared.data(for: req),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { return }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            self.latestVersion = latest
            self.updateAvailable = isNewer(latest, than: currentVersion)
        }
    }

    private func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").compactMap { Int($0) }
        let pb = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(pa.count, pb.count) {
            let va = i < pa.count ? pa[i] : 0
            let vb = i < pb.count ? pb[i] : 0
            if va != vb { return va > vb }
        }
        return false
    }
}
