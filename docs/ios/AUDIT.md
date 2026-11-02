# Tidy iPhone companion: source audit and design

Source: the native Tidy repository (tmass1/tidy), not the Tidy UI website. Inspected README, CLAUDE.md, docs/HANDOFF.md, all rewrite/storage code, Theme.swift, Panel.swift, Resources/AppIcon.png and site/assets/hero-light.png. The original external Lens handoff directory was not found; the implemented Lens tokens and existing app render are the visual source of truth. The unrelated untracked logo/ assets were left alone.

## Existing behavior
- Swift 5.9 package, macOS 14+, AppKit shell and SwiftUI views, zero third-party dependencies.
- Claude.stream uses Anthropic Messages over URLSession.bytes and SSE. Models are Haiku/Sonnet/Opus 5.5 with IDs from Claude.models; Sonnet is default. 4096 output tokens, 60 second request timeout, no exposed temperature. Model availability still needs validation against a real user's account; no IDs silently changed.
- Prompts.system preserves facts, voice, medium and format; Prompts.user wraps text and instructions and optionally source-app name/character limit. Prompts.clean removes wrappers during/following streaming. Tweaks operate on the current result; switching modes operates on the original.
- Clean up, Fix only, Shorter, Warmer, Polished plus editable custom Mode records. Final is editable; Changes is bounded LCS word/whitespace diff. Original is always recoverable.
- Personal Anthropic key in login Keychain (com.tommymassaro.tidy / anthropic-api-key). No Tidy account, authentication server, proxy, or sync backend. Cloudflare serves static site assets only.
- Mac preferences and voice profile: UserDefaults. Modes/history: JSON under Application Support/Tidy; history capped at 500. Voice learning uses edited history on demand or after three edits. Mac clipboard, Accessibility, hotkeys, updater and launch-at-login are platform-specific.

## Prototype decisions
Extract TidyCore as a library product in the existing Swift package. Move pure models, prompts, Claude client, string helpers and word diff there; preserve prompt text, mode instructions and wire contracts. Mac changes are imports/dependency wiring and removal of moved definitions, not UI or storage migration. Build the Mac app but do not install, launch or deploy it.

Native iOS 17+ SwiftUI app plus a custom UIViewController-hosted SwiftUI Share extension. Both consume TidyCore and the same iOS UI source. Lens colors, system type, mode chips, generous prose and underline/strike diff survive; native navigation, scrollable content, keyboard-safe controls and 44pt targets adapt the layout. Original/Changes/Final are explicit mobile tabs. Settings manages a personal API key, existing models, modes and voice instructions. No account or backend added. No Figma work.

App Group preferences share modes/model/voice only on this iPhone. Keychain sharing keeps the user-supplied key accessible to both targets, with when-unlocked-this-device-only protection. No bundled secret and no existing Mac key is read. Import the existing Mac modes.json using Files for explicit manual transfer. Cross-device synchronization, automatic voice learning and iOS history are deferred. Do not interpret Copy/Share as proof that a message was sent.

## Platform boundary
Receive only text deliberately supplied through NSExtensionItem/NSItemProvider. Handle missing/unsupported input and load failures. No global selection listener, synthetic paste, source-app detection, or universal replacement. Copy followed by manual paste is dependable; sharing the result is a separate user action. Cancel when the extension closes/backgrounds; do not promise background generation. Cap input at 20,000 characters and bound word diff to protect extension memory.

Apple's Share extension guidance centers posting content and suggests Action extensions for other transformations. This requested Share prototype sends text to the user's selected provider; distribution suitability should be reviewed, with an Action extension a possible later addition. No unsupported open-containing-app trick.

Sources: https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html
https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionOverview.html
https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html
https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps

## Verification and limitations
Test shared prompts/diff, stream completion/error handling, cancellation and retry. Compile Mac and both iOS targets. Exercise the native app and actual extension in Simulator with a clearly labeled deterministic sample transport; live Anthropic and device provisioning are separate checks requiring user credentials/signing. Test light/dark, large Dynamic Type and reduced motion. Track exact results in VERIFICATION.md.
