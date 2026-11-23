import SwiftUI

@main struct TidyMobileApp: App {
    @StateObject private var store: MobileStore
    private let initialText: String
    init() {
        let store = MobileStore()
        var text = ""
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--tidy-preview") {
            store.isPreview = true
            store.defaults.set(true, forKey: "previewTransport")
            text = SampleRewrite.original
        }
        if ProcessInfo.processInfo.arguments.contains("--tidy-live") {
            store.isPreview = false
            store.defaults.set(false, forKey: "previewTransport")
            text = SampleRewrite.original
        }
        #endif
        _store = StateObject(wrappedValue: store)
        initialText = text
    }
    var body: some Scene {
        WindowGroup { EditorView(store: store, text: initialText) }
    }
}
