import AppKit
import Security

/// Updates Tidy from the latest GitHub release of tmass1/tidy (built and notarized by
/// release.sh). Checks quietly once a day; installing replaces the app and relaunches it.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case installing
        case failed(String)
    }

    struct Release: Equatable {
        let version: String
        let download: URL
    }

    @Published private(set) var state: State = .idle

    /// Only builds signed by this team are installed.
    private static let teamID = "Y5V8Y3BH9A"
    private static let latestRelease = URL(string: "https://api.github.com/repos/tmass1/tidy/releases/latest")!
    private static let assetName = "Tidy.zip"
    private var timer: Timer?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var available: Release? {
        if case .available(let release) = state { return release }
        return nil
    }

    /// Checks a few seconds after launch, then every 24 hours.
    func startAutomaticChecks() {
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await check()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { _ in
            Task { @MainActor in await Updater.shared.check() }
        }
    }

    func check() async {
        guard state != .checking, state != .installing else { return }
        state = .checking
        do {
            var request = URLRequest(url: Self.latestRelease)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Tidy/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 {
                state = .upToDate // no releases published yet
                return
            }
            guard status == 200 else { throw ClaudeError(message: "GitHub returned \(status).") }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
            guard Self.isNewer(version, than: currentVersion),
                  let asset = release.assets.first(where: { $0.name == Self.assetName }),
                  let url = URL(string: asset.browser_download_url) else {
                state = .upToDate
                return
            }
            state = .available(Release(version: version, download: url))
        } catch {
            NSLog("Tidy: update check failed: \(error.localizedDescription)")
            state = .failed("Couldn't check for updates. \(error.localizedDescription)")
        }
    }

    /// Downloads the release, checks its signature, then hands off to a small script that swaps
    /// the app once Tidy has quit and opens the new one.
    func install() async {
        guard let release = available else { return }
        let destination = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: destination.deletingLastPathComponent().path) else {
            state = .failed("Move Tidy to your Applications folder to update it.")
            return
        }
        state = .installing
        do {
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("TidyUpdate-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let (zip, _) = try await URLSession.shared.download(from: release.download)
            try run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
            let newApp = work.appendingPathComponent("Tidy.app")
            guard Self.teamIdentifier(of: newApp) == Self.teamID else {
                throw ClaudeError(message: "The download isn't signed by Tidy's developer.")
            }

            let script = work.appendingPathComponent("install.sh")
            try """
            #!/bin/bash
            while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
            rm -rf "$2" && /usr/bin/ditto "$3" "$2" && /usr/bin/open "$2"
            """.write(to: script, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), destination.path, newApp.path]
            try process.run()
            NSApp.terminate(nil)
        } catch {
            NSLog("Tidy: update failed: \(error.localizedDescription)")
            state = .failed("Couldn't update. \(error.localizedDescription)")
        }
    }

    // MARK: Helpers

    /// "1.10" is newer than "1.9"; missing parts count as 0.
    static func isNewer(_ version: String, than current: String) -> Bool {
        let a = version.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func teamIdentifier(of app: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil) == errSecSuccess
        else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ClaudeError(message: "\(URL(fileURLWithPath: tool).lastPathComponent) failed.")
        }
    }

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let assets: [Asset]
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
    }
}
