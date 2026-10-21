// Cabin 0.23.0: tokens for Swift, generated from tokens/tokens.json by scripts/swift.mjs. Do not edit.
// Colours follow the window's appearance (light or dark) on their own, in SwiftUI and AppKit alike.
// Use the token names, never the palette: Cabin.card, Cabin.mutedForeground, Cabin.primary; Cabin.NS.card for AppKit.

#if canImport(AppKit)
import AppKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif
import Foundation   // CGFloat (CoreGraphics on the Mac, Foundation on Linux, where the logic is tested)

/// Cabin's design tokens. `Cabin.version` is the Cabin release they came from.
public enum Cabin {
    public static let version = "0.23.0"

    /// A light and a dark value, as 0xRRGGBBAA.
    public struct Pair: Sendable, Hashable {
        public let light: UInt32
        public let dark: UInt32
        public init(light: UInt32, dark: UInt32) { self.light = light; self.dark = dark }
    }

    /// Every colour token's light and dark values.
    public enum Values {
        /// App ground and the page behind every card.
        public static let background = Pair(light: 0xF3F4F6FF, dark: 0x0E0F11FF)
        /// Primary text and icons on `background`, `card`, `popover`, `secondary` and `muted`.
        public static let foreground = Pair(light: 0x121316FF, dark: 0xF3F4F6FF)
        /// Cards, the side panel, sheets and docked panels resting on `background`.
        public static let card = Pair(light: 0xFFFFFFFF, dark: 0x1A1B1FFF)
        /// Text on `card`.
        public static let cardForeground = Pair(light: 0x121316FF, dark: 0xF3F4F6FF)
        /// Menus, popovers and dialogs floating above cards (pair with `shadow-float`).
        public static let popover = Pair(light: 0xFFFFFFFF, dark: 0x24262BFF)
        /// Text on `popover`.
        public static let popoverForeground = Pair(light: 0x121316FF, dark: 0xF3F4F6FF)
        /// The one confirm action per view and any ON / selected state: Button default, active segment, switch on, slider fill. The bright brand cyan #2FC3F9 in dark (as in Stash); a deeper #0295CA in light so marks hold 3:1 on white.
        public static let primary = Pair(light: 0x0295CAFF, dark: 0x2FC3F9FF)
        /// Text and icons on a `primary` fill: white, as in Stash. In dark that is about 2:1 on the bright cyan, a deliberate exception to the 4.5:1 rule (see check-contrast.mjs): keep labels short, semibold and at control size; in light it is 3.4:1.
        public static let primaryForeground = Pair(light: 0xFFFFFFFF, dark: 0xFFFFFFFF)
        /// Neutral control fill: secondary buttons, idle tiles, segmented tracks, stepper arrows.
        public static let secondary = Pair(light: 0xE6E8ECFF, dark: 0x2A2C31FF)
        /// Text and icons on `secondary`.
        public static let secondaryForeground = Pair(light: 0x121316FF, dark: 0xF3F4F6FF)
        /// Quiet fills: skeletons, disabled controls, table stripes, slider track.
        public static let muted = Pair(light: 0xECEEF1FF, dark: 0x1F2024FF)
        /// Labels, units and metadata on `background`, `card`, `secondary` and `muted`.
        public static let mutedForeground = Pair(light: 0x5A5E66FF, dark: 0xA1A4ABFF)
        /// Hover / pressed fill for ghost and outline controls (shadcn `accent`).
        public static let accent = Pair(light: 0xE6E8ECFF, dark: 0x2A2C31FF)
        /// Text on `accent`.
        public static let accentForeground = Pair(light: 0x121316FF, dark: 0xF3F4F6FF)
        /// Destructive actions and critical alerts; always with a word or icon, never colour alone.
        public static let destructive = Pair(light: 0xDC1028FF, dark: 0xFF5C63FF)
        /// Text and icons on a `destructive` fill (dark ink in dark, white in light).
        public static let destructiveForeground = Pair(light: 0xFFFFFFFF, dark: 0x0E0F11FF)
        /// Hairlines and card separators (decorative; never the only boundary of a control).
        public static let border = Pair(light: 0xDCDEE3FF, dark: 0x2A2C31FF)
        /// Input and outline-button borders: holds 3:1 on `background` and `card`.
        public static let input = Pair(light: 0x7D818AFF, dark: 0x6B6F78FF)
        /// Focus ring: solid 2px outside a 2px `background` gap, 3:1 on every surface.
        public static let ring = Pair(light: 0x0295CAFF, dark: 0x2FC3F9FF)
        /// Translucent frosted surface (a light frosted grey at 62% in dark, white at 72% in light) for dialogs, sheets and panels floating over content. Always with `blur-glass` backdrop blur + saturate(180%), the `glass-sheen` highlight and `shadow-glass`. Secondary text inside uses `glass-muted-foreground`.
        public static let glass = Pair(light: 0xFFFFFFB8, dark: 0x34373E9E)
        /// 1px inner edge that catches light on a glass panel (part of `shadow-glass`).
        public static let glassEdge = Pair(light: 0xFFFFFFCC, dark: 0xFFFFFF29)
        /// Top of the vertical highlight gradient on glass (fades to transparent halfway down): the light catching the panel.
        public static let glassSheen = Pair(light: 0xFFFFFF73, dark: 0xFFFFFF14)
        /// Secondary text, units and icons on `glass`. Stronger than `muted-foreground` so it holds 4.5:1 over blurred scene, path and vehicles behind the panel.
        public static let glassMutedForeground = Pair(light: 0x45494FFF, dark: 0xDCDEE3FF)
        /// Fill for secondary buttons, steppers and list rows sitting on a `glass` surface, where `secondary` would vanish. Text on it stays `foreground`.
        public static let glassControl = Pair(light: 0x1213160F, dark: 0xFFFFFF1F)
        /// Glass finish: the ground the aura sits on (`glass-ground`). A near-black blue in dark, a cool near-white in light.
        public static let aura = Pair(light: 0xF8FAFCFF, dark: 0x020618FF)
        /// Glass finish: the cool wash at the ground's top left.
        public static let auraCyan = Pair(light: 0xB8E6FEFF, dark: 0x024A70FF)
        /// Glass finish: the violet wash at the ground's top right.
        public static let auraViolet = Pair(light: 0xC6D2FFFF, dark: 0x1E1A4DFF)
        /// Glass finish: the warm wash at the ground's foot, the lamp's side of the room.
        public static let auraAmber = Pair(light: 0xFFD6A7FF, dark: 0x432004FF)
        /// Glass finish: the mint wash at the ground's bottom left.
        public static let auraMint = Pair(light: 0xCBFBF1FF, dark: 0x022F2EFF)
        /// Glass finish: a brighter cool light in the ground, so the panes have colour to frost.
        public static let auraGlowCyan = Pair(light: 0x74D4FFFF, dark: 0x104E64FF)
        /// Glass finish: a brighter warm light in the ground, so the panes have colour to frost.
        public static let auraGlowAmber = Pair(light: 0xFEE685FF, dark: 0x461901FF)
        /// Glass finish: the top of a pane (cards, lists, the dock, notices), fading to `pane-end`. Always over `blur-pane`.
        public static let pane = Pair(light: 0xFFFFFFCC, dark: 0xFFFFFF1A)
        /// Glass finish: the foot of a pane. Text on a pane is `foreground` and `glass-muted-foreground`, held to 4.5:1 here over every aura colour.
        public static let paneEnd = Pair(light: 0xFFFFFF80, dark: 0xFFFFFF0A)
        /// Glass finish: the 1px edge around a pane (part of `shadow-pane`).
        public static let paneEdge = Pair(light: 0xFFFFFFB3, dark: 0xFFFFFF0F)
        /// Glass finish: neutral pressables (secondary buttons, steppers, tiles at rest, keypad keys), with `shadow-pane-raised`.
        public static let paneRaised = Pair(light: 0xFFFFFF99, dark: 0xFFFFFF14)
        /// Glass finish: the chosen segment, and a raised control under the pointer.
        public static let paneActive = Pair(light: 0xFFFFFFE6, dark: 0xFFFFFF1A)
        /// Glass finish: anything cut into a pane (segmented, switch and slider tracks, progress), with `shadow-pane-well`.
        public static let paneWell = Pair(light: 0x1213160F, dark: 0x0000004D)
        /// Light dim behind a modal (40% dark / 24% light) so the blurred screen still shows through; always with `blur-scrim`.
        public static let scrim = Pair(light: 0x1213163D, dark: 0x00000066)
        /// Lit finish only: the flat stand-in for `cta-fill` (Figma solids, fallbacks, a 1px mark); the same cyan as `primary` in dark. One per view.
        public static let cta = Pair(light: 0x2FC3F9FF, dark: 0x2FC3F9FF)
        /// Top stop of `cta-fill`: the aqua #25E4F8 (cabin-cyan-300), as in Stash.
        public static let ctaFrom = Pair(light: 0x25E4F8FF, dark: 0x25E4F8FF)
        /// Bottom stop of `cta-fill`: the blue #2EA0FE (cabin-blue-400), as in Stash.
        public static let ctaTo = Pair(light: 0x2EA0FEFF, dark: 0x2EA0FEFF)
        /// Text and icons on `cta`/`cta-fill`: white in dark, as in Stash (a deliberate exception: about 1.6:1 at the aqua top); dark ink in light, where the bright gradient sits on a white page.
        public static let ctaForeground = Pair(light: 0x0B1A24FF, dark: 0xFFFFFFFF)
        /// Lit finish: the accent as a line or mark on a ground (track, ring arc, progress, active indicator). Light deepens it because bright cyan fails 3:1 on white.
        public static let glow = Pair(light: 0x0B7FB8FF, dark: 0x2FC3F9FF)
        /// Lit finish: the trailing (left) stop of `glow-fill`, on progress and slider fills.
        public static let glowStart = Pair(light: 0x2EA0FEFF, dark: 0x2EA0FEFF)
        /// Lit finish: the leading (right) stop of `glow-fill`, the brightest point of a fill.
        public static let glowEnd = Pair(light: 0x25E4F8FF, dark: 0x25E4F8FF)
        /// Charging, connected, done. As text on `background`/`card`; always with icon or word.
        public static let success = Pair(light: 0x02803AFF, dark: 0x3EE084FF)
        /// Text on a `success` fill.
        public static let successForeground = Pair(light: 0xFFFFFFFF, dark: 0x06180DFF)
        /// Attention without danger (low range, door open). As text on `background`/`card`.
        public static let warning = Pair(light: 0xB05500FF, dark: 0xFFC233FF)
        /// Text on a `warning` fill.
        public static let warningForeground = Pair(light: 0xFFFFFFFF, dark: 0x1D1300FF)
        /// Neutral notices, links and cyan as text on `background`/`card` (deeper than `primary` in light, where cyan text fails).
        public static let info = Pair(light: 0x0072B5FF, dark: 0x2FC3F9FF)
        /// Warming states (seat / steering heat, temperature up). As text or icon on `background`/`card`.
        public static let heat = Pair(light: 0xC93C02FF, dark: 0xFF7A3DFF)
        /// Cooling states (A/C, fan, temperature down) and water. Blue, so it never reads as the action cyan. As text or icon on `background`/`card`.
        public static let cool = Pair(light: 0x2152F0FF, dark: 0x6F9DFFFF)
        /// Success as a fill: solid badges, a Notice's action, tints. Bright in both themes with `fill-foreground` text; `success` stays the colour for words, icons and marks.
        public static let successFill = Pair(light: 0x22C55EFF, dark: 0x3EE084FF)
        /// Warning as a fill, with `fill-foreground` text. `warning` is the colour for words, icons and marks.
        public static let warningFill = Pair(light: 0xF2B233FF, dark: 0xFFC233FF)
        /// Destructive as a fill in badges, Notice actions and tints, with `fill-foreground` text. A destructive Button uses `destructive` with `destructive-foreground`.
        public static let destructiveFill = Pair(light: 0xFF5C63FF, dark: 0xFF5C63FF)
        /// Heat as a fill, with `fill-foreground` text.
        public static let heatFill = Pair(light: 0xFF7A3DFF, dark: 0xFF7A3DFF)
        /// Cool as a fill, with `fill-foreground` text.
        public static let coolFill = Pair(light: 0x5B93FFFF, dark: 0x6F9DFFFF)
        /// Text and icons on every bright status fill (`*-fill`): dark ink, 4.5:1 on all of them in both themes.
        public static let fillForeground = Pair(light: 0x121316FF, dark: 0x0E0F11FF)
        /// A light that's on: the icon and ring of a lit light's tile, a warm mark. Only for lights; anything else that's on is `primary`. Kept apart from `warning`, which always carries its icon and word.
        public static let lamp = Pair(light: 0x8C6A00FF, dark: 0xFFE39EFF)
        /// A lit light as a fill (a solid badge, the tint of its tile), with `fill-foreground` text.
        public static let lampFill = Pair(light: 0xFFDB70FF, dark: 0xFFE39EFF)
        /// Ground of the SceneView (drive / track view) and full-bleed visual areas.
        public static let scene = Pair(light: 0xE2E4E8FF, dark: 0x16171BFF)
        /// Lane lines and track marks inside SceneView.
        public static let sceneLine = Pair(light: 0x71757EFF, dark: 0x6B6F78FF)
        /// Other vehicles and obstacles in SceneView.
        public static let sceneObject = Pair(light: 0x7D818AFF, dark: 0x7D818AFF)
        /// The planned path / active lane band in SceneView: the action cyan, a step deeper in dark so glass over it keeps 4.5:1.
        public static let path = Pair(light: 0x007099FF, dark: 0x14A8DEFF)
        /// The ego vehicle / runner marker in SceneView.
        public static let selfMarker = Pair(light: 0x2A2C31FF, dark: 0xF3F4F6FF)
        /// Effort zone 1 (recovery). Fill for zone pills and bars; holds 3:1 on `card` and `background` in both themes.
        public static let zone1 = Pair(light: 0x9AA6B8FF, dark: 0x9AA6B8FF)
        /// Effort zone 2 (endurance).
        public static let zone2 = Pair(light: 0x5B93FFFF, dark: 0x5B93FFFF)
        /// Effort zone 3 (tempo).
        public static let zone3 = Pair(light: 0x22C55EFF, dark: 0x3EE084FF)
        /// Effort zone 4 (threshold).
        public static let zone4 = Pair(light: 0xFFAE2BFF, dark: 0xFFAE2BFF)
        /// Effort zone 5 (max).
        public static let zone5 = Pair(light: 0xFF5C63FF, dark: 0xFF5C63FF)
        /// Text on any `zone-*` fill (the "Z3" pill): dark ink on bright zones, 4.5:1 on all five. Zones always show their number, never colour alone.
        public static let zoneForeground = Pair(light: 0x121316FF, dark: 0x0E0F11FF)
        /// Chart series 1 (cyan: the primary metric; water). Assign series in this order, never cycled; past 8, fold into Other. Validated as a set in both themes: lightness band, chroma, colour-blind and normal-vision separation of neighbours, 3:1 on card and background; the first three also apart from every other (scatter).
        public static let chart1 = Pair(light: 0x0B7FB8FF, dark: 0x0295CAFF)
        /// Chart series 2 (orange: the second series; warmth). Assign series in this order, never cycled; past 8, fold into Other. Validated as a set in both themes: lightness band, chroma, colour-blind and normal-vision separation of neighbours, 3:1 on card and background; the first three also apart from every other (scatter).
        public static let chart2 = Pair(light: 0xC2410CFF, dark: 0xEB6032FF)
        /// Chart series 3 (violet). Assign series in this order, never cycled; past 8, fold into Other. Validated as a set in both themes: lightness band, chroma, colour-blind and normal-vision separation of neighbours, 3:1 on card and background; the first three also apart from every other (scatter).
        public static let chart3 = Pair(light: 0x9810FAFF, dark: 0xAD46FFFF)
        /// Chart series 4 (green). Assign series in this order, never cycled; past 8, fold into Other. Validated as a set in both themes: lightness band, chroma, colour-blind and normal-vision separation of neighbours, 3:1 on card and background; the first three also apart from every other (scatter).
        public static let chart4 = Pair(light: 0x1C925EFF, dark: 0x23845AFF)
        /// Chart series 5 (blue). Assign series in this order, never cycled; past 8, fold into Other. Validated as a set in both themes: lightness band, chroma, colour-blind and normal-vision separation of neighbours, 3:1 on card and background; the first three also apart from every other (scatter).
        public static let chart5 = Pair(light: 0x2F6BD0FF, dark: 0x4D86EFFF)
        /// Chart series 6 (yellow). Assign series in this order, never cycled; past 8, fold into Other. Validated as a set in both themes: lightness band, chroma, colour-blind and normal-vision separation of neighbours, 3:1 on card and background; the first three also apart from every other (scatter).
        public static let chart6 = Pair(light: 0xB86A00FF, dark: 0xC88000FF)
        /// Chart series 7 (magenta). Assign series in this order, never cycled; past 8, fold into Other. Validated as a set in both themes: lightness band, chroma, colour-blind and normal-vision separation of neighbours, 3:1 on card and background; the first three also apart from every other (scatter).
        public static let chart7 = Pair(light: 0xC800DEFF, dark: 0xE12AFBFF)
        /// Chart series 8 (red; last, since red also means danger). Assign series in this order, never cycled; past 8, fold into Other. Validated as a set in both themes: lightness band, chroma, colour-blind and normal-vision separation of neighbours, 3:1 on card and background; the first three also apart from every other (scatter).
        public static let chart8 = Pair(light: 0xD93C3CFF, dark: 0xD93C3CFF)
        /// shadcn Sidebar ground (alias of `card`).
        public static let sidebar = Pair(light: 0xFFFFFFFF, dark: 0x1A1B1FFF)
        /// Text on `sidebar`.
        public static let sidebarForeground = Pair(light: 0x121316FF, dark: 0xF3F4F6FF)
        /// Active sidebar item fill.
        public static let sidebarPrimary = Pair(light: 0x0295CAFF, dark: 0x2FC3F9FF)
        /// Text on `sidebar-primary`.
        public static let sidebarPrimaryForeground = Pair(light: 0xFFFFFFFF, dark: 0xFFFFFFFF)
        /// Hovered sidebar item.
        public static let sidebarAccent = Pair(light: 0xE6E8ECFF, dark: 0x2A2C31FF)
        /// Text on `sidebar-accent`.
        public static let sidebarAccentForeground = Pair(light: 0x121316FF, dark: 0xF3F4F6FF)
        /// Sidebar hairlines.
        public static let sidebarBorder = Pair(light: 0xDCDEE3FF, dark: 0x2A2C31FF)
        /// Focus ring inside the sidebar.
        public static let sidebarRing = Pair(light: 0x0295CAFF, dark: 0x2FC3F9FF)
        /// The window ground under the Desk finish (`.cb-desk-ground`, Shell, Window): content areas sit on it.
        public static let deskGround = Pair(light: 0xF9FAFBFF, dark: 0x121316FF)
        /// Desk finish chrome: the title bar, a sidebar, an inspector, a toolbar band. One step off the ground so the content area reads as the page.
        public static let deskChrome = Pair(light: 0xF3F4F6FF, dark: 0x16171BFF)
        /// Neutral pressables under the Desk finish (secondary buttons, stepper buttons, the active segment), with `shadow-desk-control`.
        public static let deskControl = Pair(light: 0xFFFFFFFF, dark: 0x24262BFF)
        /// The hairline that edges cards, lists, tables and chrome under the Desk finish. Decorative: a control's own edge is `input`.
        public static let deskEdge = Pair(light: 0xE2E4E8FF, dark: 0x24262BFF)
    }

    public enum Space {
        /// Icon-to-label gap inside a control.
        public static let _1: CGFloat = 4
        /// Gap between a readout and its unit; tight rows.
        public static let _2: CGFloat = 8
        /// Between stacked cards and between tiles in a grid.
        public static let _3: CGFloat = 12
        /// Card and sheet padding (default density).
        public static let _4: CGFloat = 16
        /// Status bar and dock side insets.
        public static let _5: CGFloat = 20
        /// Card padding in glance density; between sections.
        public static let _6: CGFloat = 24
        /// Between major regions of a screen.
        public static let _8: CGFloat = 32
        /// Hero readout breathing room.
        public static let _12: CGFloat = 48
    }

    public enum Radius {
        /// Badges, inputs in compact density, small chips.
        public static let sm: CGFloat = 8
        /// Inputs, tiles, segmented thumbs, menus. Also shadcn's base `--radius`.
        public static let md: CGFloat = 12
        /// Cards, sheets, dialogs, the side panel.
        public static let lg: CGFloat = 20
        /// The dock and full-bleed scene panels.
        public static let xl: CGFloat = 28
        /// Buttons, switches, slider thumbs, steppers: every pressable is a pill.
        public static let full: CGFloat = 9999
        /// Desk finish: buttons, inputs, segmented controls, steppers, menu items. Switches, badges and avatars stay round.
        public static let deskControl: CGFloat = 6
        /// Desk finish: cards, lists, tables, menus, popovers, dialogs, sheets, notices.
        public static let deskPanel: CGFloat = 10
    }

    public enum Size {
        /// Control height in `compact` density (dense desktop tools).
        public static let controlSm: CGFloat = 32
        /// Control height in `default` density (web and mobile).
        public static let controlMd: CGFloat = 40
        /// Control height in `touch` density (wall panels, kiosks, the car screen at rest).
        public static let controlLg: CGFloat = 52
        /// Control height in `glance` density (arm's length, in motion: treadmill, driving, pool deck).
        public static let controlXl: CGFloat = 68
        /// Minimum touch target in any density; smaller visuals pad out to this.
        public static let hitMin: CGFloat = 44
        /// Body size in `compact` density.
        public static let textCompact: CGFloat = 13
        /// Body size in `default` density.
        public static let textDefault: CGFloat = 15
        /// Body size in `touch` density.
        public static let textTouch: CGFloat = 17
        /// Body size in `glance` density.
        public static let textGlance: CGFloat = 20
        /// Icons in compact controls.
        public static let iconSm: CGFloat = 16
        /// Icons in default controls.
        public static let iconMd: CGFloat = 20
        /// Icons in touch controls and the dock.
        public static let iconLg: CGFloat = 24
        /// Icons in glance controls and control tiles.
        public static let iconXl: CGFloat = 32
        /// Status bar height.
        public static let statusbarH: CGFloat = 44
        /// Dock height (touch and glance).
        public static let dockH: CGFloat = 76
        /// A desktop window's title bar (TitleBar): tall enough for the Mac's window buttons with room around them.
        public static let titlebarH: CGFloat = 38
        /// Space a TitleBar keeps at its left for the Mac's close, minimise and zoom buttons (a Tauri window with titleBarStyle Overlay).
        public static let titlebarInset: CGFloat = 78
    }
}

#if canImport(AppKit)
extension Cabin {
    static func rgba(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 24) & 0xff) / 255, green: CGFloat((v >> 16) & 0xff) / 255,
                blue: CGFloat((v >> 8) & 0xff) / 255, alpha: CGFloat(v & 0xff) / 255)
    }
    /// An NSColor that resolves to the pair's light or dark value for whatever appearance draws it.
    public static func dynamic(_ pair: Pair) -> NSColor {
        let light = pair.light, dark = pair.dark   // plain integers, so the provider stays Sendable
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? Cabin.rgba(dark) : Cabin.rgba(light)
        }
    }

    /// Colour tokens as AppKit colours (attributed strings, NSView layers, NSTextView).
    public enum NS {
        public static var background: NSColor { Cabin.dynamic(Values.background) }
        public static var foreground: NSColor { Cabin.dynamic(Values.foreground) }
        public static var card: NSColor { Cabin.dynamic(Values.card) }
        public static var cardForeground: NSColor { Cabin.dynamic(Values.cardForeground) }
        public static var popover: NSColor { Cabin.dynamic(Values.popover) }
        public static var popoverForeground: NSColor { Cabin.dynamic(Values.popoverForeground) }
        public static var primary: NSColor { Cabin.dynamic(Values.primary) }
        public static var primaryForeground: NSColor { Cabin.dynamic(Values.primaryForeground) }
        public static var secondary: NSColor { Cabin.dynamic(Values.secondary) }
        public static var secondaryForeground: NSColor { Cabin.dynamic(Values.secondaryForeground) }
        public static var muted: NSColor { Cabin.dynamic(Values.muted) }
        public static var mutedForeground: NSColor { Cabin.dynamic(Values.mutedForeground) }
        public static var accent: NSColor { Cabin.dynamic(Values.accent) }
        public static var accentForeground: NSColor { Cabin.dynamic(Values.accentForeground) }
        public static var destructive: NSColor { Cabin.dynamic(Values.destructive) }
        public static var destructiveForeground: NSColor { Cabin.dynamic(Values.destructiveForeground) }
        public static var border: NSColor { Cabin.dynamic(Values.border) }
        public static var input: NSColor { Cabin.dynamic(Values.input) }
        public static var ring: NSColor { Cabin.dynamic(Values.ring) }
        public static var glass: NSColor { Cabin.dynamic(Values.glass) }
        public static var glassEdge: NSColor { Cabin.dynamic(Values.glassEdge) }
        public static var glassSheen: NSColor { Cabin.dynamic(Values.glassSheen) }
        public static var glassMutedForeground: NSColor { Cabin.dynamic(Values.glassMutedForeground) }
        public static var glassControl: NSColor { Cabin.dynamic(Values.glassControl) }
        public static var aura: NSColor { Cabin.dynamic(Values.aura) }
        public static var auraCyan: NSColor { Cabin.dynamic(Values.auraCyan) }
        public static var auraViolet: NSColor { Cabin.dynamic(Values.auraViolet) }
        public static var auraAmber: NSColor { Cabin.dynamic(Values.auraAmber) }
        public static var auraMint: NSColor { Cabin.dynamic(Values.auraMint) }
        public static var auraGlowCyan: NSColor { Cabin.dynamic(Values.auraGlowCyan) }
        public static var auraGlowAmber: NSColor { Cabin.dynamic(Values.auraGlowAmber) }
        public static var pane: NSColor { Cabin.dynamic(Values.pane) }
        public static var paneEnd: NSColor { Cabin.dynamic(Values.paneEnd) }
        public static var paneEdge: NSColor { Cabin.dynamic(Values.paneEdge) }
        public static var paneRaised: NSColor { Cabin.dynamic(Values.paneRaised) }
        public static var paneActive: NSColor { Cabin.dynamic(Values.paneActive) }
        public static var paneWell: NSColor { Cabin.dynamic(Values.paneWell) }
        public static var scrim: NSColor { Cabin.dynamic(Values.scrim) }
        public static var cta: NSColor { Cabin.dynamic(Values.cta) }
        public static var ctaFrom: NSColor { Cabin.dynamic(Values.ctaFrom) }
        public static var ctaTo: NSColor { Cabin.dynamic(Values.ctaTo) }
        public static var ctaForeground: NSColor { Cabin.dynamic(Values.ctaForeground) }
        public static var glow: NSColor { Cabin.dynamic(Values.glow) }
        public static var glowStart: NSColor { Cabin.dynamic(Values.glowStart) }
        public static var glowEnd: NSColor { Cabin.dynamic(Values.glowEnd) }
        public static var success: NSColor { Cabin.dynamic(Values.success) }
        public static var successForeground: NSColor { Cabin.dynamic(Values.successForeground) }
        public static var warning: NSColor { Cabin.dynamic(Values.warning) }
        public static var warningForeground: NSColor { Cabin.dynamic(Values.warningForeground) }
        public static var info: NSColor { Cabin.dynamic(Values.info) }
        public static var heat: NSColor { Cabin.dynamic(Values.heat) }
        public static var cool: NSColor { Cabin.dynamic(Values.cool) }
        public static var successFill: NSColor { Cabin.dynamic(Values.successFill) }
        public static var warningFill: NSColor { Cabin.dynamic(Values.warningFill) }
        public static var destructiveFill: NSColor { Cabin.dynamic(Values.destructiveFill) }
        public static var heatFill: NSColor { Cabin.dynamic(Values.heatFill) }
        public static var coolFill: NSColor { Cabin.dynamic(Values.coolFill) }
        public static var fillForeground: NSColor { Cabin.dynamic(Values.fillForeground) }
        public static var lamp: NSColor { Cabin.dynamic(Values.lamp) }
        public static var lampFill: NSColor { Cabin.dynamic(Values.lampFill) }
        public static var scene: NSColor { Cabin.dynamic(Values.scene) }
        public static var sceneLine: NSColor { Cabin.dynamic(Values.sceneLine) }
        public static var sceneObject: NSColor { Cabin.dynamic(Values.sceneObject) }
        public static var path: NSColor { Cabin.dynamic(Values.path) }
        public static var selfMarker: NSColor { Cabin.dynamic(Values.selfMarker) }
        public static var zone1: NSColor { Cabin.dynamic(Values.zone1) }
        public static var zone2: NSColor { Cabin.dynamic(Values.zone2) }
        public static var zone3: NSColor { Cabin.dynamic(Values.zone3) }
        public static var zone4: NSColor { Cabin.dynamic(Values.zone4) }
        public static var zone5: NSColor { Cabin.dynamic(Values.zone5) }
        public static var zoneForeground: NSColor { Cabin.dynamic(Values.zoneForeground) }
        public static var chart1: NSColor { Cabin.dynamic(Values.chart1) }
        public static var chart2: NSColor { Cabin.dynamic(Values.chart2) }
        public static var chart3: NSColor { Cabin.dynamic(Values.chart3) }
        public static var chart4: NSColor { Cabin.dynamic(Values.chart4) }
        public static var chart5: NSColor { Cabin.dynamic(Values.chart5) }
        public static var chart6: NSColor { Cabin.dynamic(Values.chart6) }
        public static var chart7: NSColor { Cabin.dynamic(Values.chart7) }
        public static var chart8: NSColor { Cabin.dynamic(Values.chart8) }
        public static var sidebar: NSColor { Cabin.dynamic(Values.sidebar) }
        public static var sidebarForeground: NSColor { Cabin.dynamic(Values.sidebarForeground) }
        public static var sidebarPrimary: NSColor { Cabin.dynamic(Values.sidebarPrimary) }
        public static var sidebarPrimaryForeground: NSColor { Cabin.dynamic(Values.sidebarPrimaryForeground) }
        public static var sidebarAccent: NSColor { Cabin.dynamic(Values.sidebarAccent) }
        public static var sidebarAccentForeground: NSColor { Cabin.dynamic(Values.sidebarAccentForeground) }
        public static var sidebarBorder: NSColor { Cabin.dynamic(Values.sidebarBorder) }
        public static var sidebarRing: NSColor { Cabin.dynamic(Values.sidebarRing) }
        public static var deskGround: NSColor { Cabin.dynamic(Values.deskGround) }
        public static var deskChrome: NSColor { Cabin.dynamic(Values.deskChrome) }
        public static var deskControl: NSColor { Cabin.dynamic(Values.deskControl) }
        public static var deskEdge: NSColor { Cabin.dynamic(Values.deskEdge) }
    }
}
#endif

#if canImport(SwiftUI) && canImport(AppKit)
extension Cabin {
    public static var background: Color { Color(nsColor: NS.background) }
    public static var foreground: Color { Color(nsColor: NS.foreground) }
    public static var card: Color { Color(nsColor: NS.card) }
    public static var cardForeground: Color { Color(nsColor: NS.cardForeground) }
    public static var popover: Color { Color(nsColor: NS.popover) }
    public static var popoverForeground: Color { Color(nsColor: NS.popoverForeground) }
    public static var primary: Color { Color(nsColor: NS.primary) }
    public static var primaryForeground: Color { Color(nsColor: NS.primaryForeground) }
    public static var secondary: Color { Color(nsColor: NS.secondary) }
    public static var secondaryForeground: Color { Color(nsColor: NS.secondaryForeground) }
    public static var muted: Color { Color(nsColor: NS.muted) }
    public static var mutedForeground: Color { Color(nsColor: NS.mutedForeground) }
    public static var accent: Color { Color(nsColor: NS.accent) }
    public static var accentForeground: Color { Color(nsColor: NS.accentForeground) }
    public static var destructive: Color { Color(nsColor: NS.destructive) }
    public static var destructiveForeground: Color { Color(nsColor: NS.destructiveForeground) }
    public static var border: Color { Color(nsColor: NS.border) }
    public static var input: Color { Color(nsColor: NS.input) }
    public static var ring: Color { Color(nsColor: NS.ring) }
    public static var glass: Color { Color(nsColor: NS.glass) }
    public static var glassEdge: Color { Color(nsColor: NS.glassEdge) }
    public static var glassSheen: Color { Color(nsColor: NS.glassSheen) }
    public static var glassMutedForeground: Color { Color(nsColor: NS.glassMutedForeground) }
    public static var glassControl: Color { Color(nsColor: NS.glassControl) }
    public static var aura: Color { Color(nsColor: NS.aura) }
    public static var auraCyan: Color { Color(nsColor: NS.auraCyan) }
    public static var auraViolet: Color { Color(nsColor: NS.auraViolet) }
    public static var auraAmber: Color { Color(nsColor: NS.auraAmber) }
    public static var auraMint: Color { Color(nsColor: NS.auraMint) }
    public static var auraGlowCyan: Color { Color(nsColor: NS.auraGlowCyan) }
    public static var auraGlowAmber: Color { Color(nsColor: NS.auraGlowAmber) }
    public static var pane: Color { Color(nsColor: NS.pane) }
    public static var paneEnd: Color { Color(nsColor: NS.paneEnd) }
    public static var paneEdge: Color { Color(nsColor: NS.paneEdge) }
    public static var paneRaised: Color { Color(nsColor: NS.paneRaised) }
    public static var paneActive: Color { Color(nsColor: NS.paneActive) }
    public static var paneWell: Color { Color(nsColor: NS.paneWell) }
    public static var scrim: Color { Color(nsColor: NS.scrim) }
    public static var cta: Color { Color(nsColor: NS.cta) }
    public static var ctaFrom: Color { Color(nsColor: NS.ctaFrom) }
    public static var ctaTo: Color { Color(nsColor: NS.ctaTo) }
    public static var ctaForeground: Color { Color(nsColor: NS.ctaForeground) }
    public static var glow: Color { Color(nsColor: NS.glow) }
    public static var glowStart: Color { Color(nsColor: NS.glowStart) }
    public static var glowEnd: Color { Color(nsColor: NS.glowEnd) }
    public static var success: Color { Color(nsColor: NS.success) }
    public static var successForeground: Color { Color(nsColor: NS.successForeground) }
    public static var warning: Color { Color(nsColor: NS.warning) }
    public static var warningForeground: Color { Color(nsColor: NS.warningForeground) }
    public static var info: Color { Color(nsColor: NS.info) }
    public static var heat: Color { Color(nsColor: NS.heat) }
    public static var cool: Color { Color(nsColor: NS.cool) }
    public static var successFill: Color { Color(nsColor: NS.successFill) }
    public static var warningFill: Color { Color(nsColor: NS.warningFill) }
    public static var destructiveFill: Color { Color(nsColor: NS.destructiveFill) }
    public static var heatFill: Color { Color(nsColor: NS.heatFill) }
    public static var coolFill: Color { Color(nsColor: NS.coolFill) }
    public static var fillForeground: Color { Color(nsColor: NS.fillForeground) }
    public static var lamp: Color { Color(nsColor: NS.lamp) }
    public static var lampFill: Color { Color(nsColor: NS.lampFill) }
    public static var scene: Color { Color(nsColor: NS.scene) }
    public static var sceneLine: Color { Color(nsColor: NS.sceneLine) }
    public static var sceneObject: Color { Color(nsColor: NS.sceneObject) }
    public static var path: Color { Color(nsColor: NS.path) }
    public static var selfMarker: Color { Color(nsColor: NS.selfMarker) }
    public static var zone1: Color { Color(nsColor: NS.zone1) }
    public static var zone2: Color { Color(nsColor: NS.zone2) }
    public static var zone3: Color { Color(nsColor: NS.zone3) }
    public static var zone4: Color { Color(nsColor: NS.zone4) }
    public static var zone5: Color { Color(nsColor: NS.zone5) }
    public static var zoneForeground: Color { Color(nsColor: NS.zoneForeground) }
    public static var chart1: Color { Color(nsColor: NS.chart1) }
    public static var chart2: Color { Color(nsColor: NS.chart2) }
    public static var chart3: Color { Color(nsColor: NS.chart3) }
    public static var chart4: Color { Color(nsColor: NS.chart4) }
    public static var chart5: Color { Color(nsColor: NS.chart5) }
    public static var chart6: Color { Color(nsColor: NS.chart6) }
    public static var chart7: Color { Color(nsColor: NS.chart7) }
    public static var chart8: Color { Color(nsColor: NS.chart8) }
    public static var sidebar: Color { Color(nsColor: NS.sidebar) }
    public static var sidebarForeground: Color { Color(nsColor: NS.sidebarForeground) }
    public static var sidebarPrimary: Color { Color(nsColor: NS.sidebarPrimary) }
    public static var sidebarPrimaryForeground: Color { Color(nsColor: NS.sidebarPrimaryForeground) }
    public static var sidebarAccent: Color { Color(nsColor: NS.sidebarAccent) }
    public static var sidebarAccentForeground: Color { Color(nsColor: NS.sidebarAccentForeground) }
    public static var sidebarBorder: Color { Color(nsColor: NS.sidebarBorder) }
    public static var sidebarRing: Color { Color(nsColor: NS.sidebarRing) }
    public static var deskGround: Color { Color(nsColor: NS.deskGround) }
    public static var deskChrome: Color { Color(nsColor: NS.deskChrome) }
    public static var deskControl: Color { Color(nsColor: NS.deskControl) }
    public static var deskEdge: Color { Color(nsColor: NS.deskEdge) }
}
#endif
