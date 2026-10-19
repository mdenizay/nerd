import SwiftUI
import AppKit

/// Nerd's icon set: Lucide line icons (Resources/Assets.xcassets/Icons), looked
/// up by the SF Symbol name used in code; anything unmapped stays an SF Symbol.
enum Icons {
    static let map: [String: String] = [
        "server.rack": "server", "square.grid.2x2": "layout-grid", "globe": "globe", "plus.square": "square-plus",
        "chevron.left.forwardslash.chevron.right": "code-xml", "hexagon": "hexagon", "hexagon.fill": "hexagon",
        "number": "hash", "cylinder.split.1x2": "database", "cylinder": "database", "cylinder.fill": "database",
        "cylinder.split.1x2.fill": "database", "envelope": "mail", "envelope.fill": "mail", "envelope.badge": "mail",
        "envelope.badge.fill": "mail", "list.bullet.rectangle": "list-checks", "gearshape": "settings",
        "leaf": "leaf", "leaf.fill": "leaf", "triangle": "triangle", "triangle.fill": "triangle", "sparkles": "sparkles",
        "doc": "file", "doc.fill": "file", "bolt": "zap", "bolt.fill": "zap", "atom": "atom",
        "v.circle": "layers", "v.circle.fill": "layers", "s.circle": "wind", "s.circle.fill": "wind",
        "shippingbox": "package", "shippingbox.fill": "package", "doc.richtext": "file-text",
        "square.split.2x2": "layout-dashboard", "point.3.connected.trianglepath.dotted": "waypoints", "flame": "flame",
        "terminal": "terminal", "terminal.fill": "terminal", "folder": "folder", "play.circle": "play", "play.fill": "play",
        "stop.circle": "square", "lock.fill": "lock", "paperplane": "send", "paperplane.fill": "send",
        "arrow.clockwise": "refresh-cw", "ellipsis": "ellipsis", "arrow.up.right": "arrow-up-right", "plus": "plus",
        "link": "link", "magnifyingglass": "search", "trash": "trash-2", "trash.fill": "trash-2", "network": "network",
        "memorychip": "memory-stick", "bolt.horizontal": "activity", "externaldrive": "hard-drive",
        "exclamationmark.triangle": "triangle-alert", "exclamationmark": "circle-alert", "exclamationmark.circle": "circle-alert",
        "arrow.left.arrow.right": "arrow-left-right", "checkmark": "check", "cube.fill": "box", "power": "power",
        "power.circle": "power", "macwindow": "app-window", "tablecells": "table", "arrow.down.circle": "circle-arrow-down",
        "ladybug": "bug", "powerplug": "plug", "cpu": "cpu", "scroll": "scroll-text", "pause.circle": "circle-pause",
        "eraser": "eraser", "doc.on.doc": "copy",
    ]

    static func image(_ name: String) -> Image {
        if let asset = map[name], NSImage(named: "Icons/\(asset)") != nil {
            return Image("Icons/\(asset)")
        }
        return Image(systemName: name)
    }
}

/// An icon from Nerd's set at a fixed point size.
struct NerdIcon: View {
    var name: String
    var size: CGFloat = 14

    var body: some View {
        Icons.image(name)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

// MARK: - Technology logos (Simple Icons, see NOTICE.md)

enum Brands {
    /// Brand colours from Simple Icons. Near-black marks use the text colour instead.
    static let colors: [String: Color?] = [
        "laravel": Color(hex: 0xFF2D20), "livewire": Color(hex: 0x4E56A6), "inertia": Color(hex: 0x9553E9),
        "react": Color(hex: 0x58C4DC), "svelte": Color(hex: 0xFF3E00), "nextdotjs": nil, "astro": Color(hex: 0xBC52EE),
        "dotnet": Color(hex: 0x512BD4), "blazor": Color(hex: 0x512BD4), "php": Color(hex: 0x777BB4),
        "nodedotjs": Color(hex: 0x5FA04E), "mysql": Color(hex: 0x4479A1), "mariadb": nil,
        "postgresql": Color(hex: 0x4169E1), "redis": Color(hex: 0xFF4438), "meilisearch": Color(hex: 0xFF5CAA),
        "minio": Color(hex: 0xC72E49), "docker": Color(hex: 0x2496ED), "caddy": Color(hex: 0x1F88C0),
        "composer": Color(hex: 0x885630),
    ]

    static func exists(_ slug: String?) -> Bool {
        guard let slug else { return false }
        return NSImage(named: "Brands/\(slug)") != nil
    }
}

/// A technology logo in its brand colour.
struct BrandLogo: View {
    let slug: String
    var size: CGFloat = 14

    var body: some View {
        Image("Brands/\(slug)")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle((Brands.colors[slug] ?? nil) ?? Color.primary)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
