import AppKit

@main
enum TidyMain {
    @MainActor
    static func main() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--design-preview") || Bundle.main.bundleIdentifier == "com.tommymassaro.tidy.designpreview" {
            DesktopDesignPreview.run()
            return
        }
        #endif
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
