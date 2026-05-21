import Foundation

/// Checks the GitHub Releases API for a newer version of MynahPad.
/// Comparison is purely semver string-based (major.minor.patch integers).
final class UpdateChecker {

    static let shared = UpdateChecker()
    private init() {}

    private let apiURL = URL(string: "https://api.github.com/repos/90n9/mynah-pad/releases/latest")!

    /// Fetches the latest release tag and calls `completion` on the main queue
    /// with the version string **only if it is newer** than the running bundle version.
    func check(completion: @escaping (String) -> Void) {
        var request = URLRequest(url: apiURL, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self, error == nil, let data else { return }

            struct Release: Decodable { let tag_name: String }
            guard let release = try? JSONDecoder().decode(Release.self, from: data) else { return }

            let latestTag = release.tag_name.hasPrefix("v")
                ? String(release.tag_name.dropFirst())
                : release.tag_name

            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

            if self.isNewer(latestTag, than: currentVersion) {
                DispatchQueue.main.async { completion(latestTag) }
            }
        }.resume()
    }

    // MARK: - Version comparison

    /// Returns true if `candidate` is strictly newer than `current`.
    /// Falls back to lexicographic comparison for non-semver strings.
    private func isNewer(_ candidate: String, than current: String) -> Bool {
        let c = versionTuple(candidate)
        let k = versionTuple(current)
        if c == (0, 0, 0) || k == (0, 0, 0) {
            // Fallback — just compare as strings (better than nothing).
            return candidate > current
        }
        return c > k
    }

    private func versionTuple(_ v: String) -> (Int, Int, Int) {
        let parts = v.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 3 else { return (0, 0, 0) }
        return (parts[0], parts[1], parts[2])
    }
}
