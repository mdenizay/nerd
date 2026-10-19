import SwiftUI
import AppKit

// MARK: - Compact design kit
//
// One quiet visual language for every page: a 44pt header bar, small section
// labels, 30pt rows split by hairlines, monochrome glyphs. Colour is kept for
// status dots and the one primary action on a screen.

enum Metrics {
    static let inset: CGFloat = 16
    static let row: CGFloat = 30
}

/// Page title bar: title, optional note, actions on the right, hairline below.
struct Header<Trailing: View>: View {
    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var icon: String? = nil
    var color: Color = .accentColor
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                if let icon { TintIcon(systemName: icon, color: color, size: 24) }
                Text(title).font(.system(size: 15, weight: .semibold))
                if let subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) { trailing }
                    .controlSize(.small)
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, Metrics.inset)
            .frame(height: 44)
            Divider()
        }
    }
}

extension Header where Trailing == EmptyView {
    init(title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, icon: String? = nil, color: Color = .accentColor) {
        self.init(title: title, subtitle: subtitle, icon: icon, color: color) { EmptyView() }
    }
}

struct SectionLabel<Trailing: View>: View {
    var text: LocalizedStringKey
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Spacer()
            trailing.font(.system(size: 11)).controlSize(.mini).buttonStyle(.borderless)
        }
        .padding(.horizontal, Metrics.inset + 4)
        .padding(.top, 16).padding(.bottom, 6)
    }
}

extension SectionLabel where Trailing == EmptyView {
    init(_ text: LocalizedStringKey) {
        self.init(text: text) { EmptyView() }
    }
}

/// A dense list row with a hairline below and a hover tint.
struct Row<Content: View>: View {
    var action: (() -> Void)? = nil
    @ViewBuilder var content: Content
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) { content }
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .frame(minHeight: Metrics.row)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hover && action != nil ? Color.primary.opacity(0.045) : .clear)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .onTapGesture { action?() }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.5)).frame(height: 0.5)
                    .padding(.leading, 12)
            }
    }
}

/// A monochrome symbol at row size.
struct Glyph: View {
    var systemName: String
    var color: Color = .secondary
    var size: CGFloat = 12

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(color)
            .frame(width: size + 6)
    }
}

/// Secondary detail text in a row.
struct Detail: View {
    var text: String
    var body: some View {
        Text(text).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
    }
}

struct StatusDot: View {
    var on: Bool
    var color: Color = .green
    var body: some View {
        Circle().fill(on ? color : Color.secondary.opacity(0.35)).frame(width: 6, height: 6)
    }
}

/// A small, quiet tag (e.g. "Default", "FPM").
struct Pill: View {
    var text: LocalizedStringKey
    var color: Color = .secondary
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 1.5)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }
}

/// Borderless "…" menu used at the end of rows.
struct MoreMenu<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        Menu { content } label: {
            Image(systemName: "ellipsis").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct SiteIcon: View {
    var kind: SiteKind
    var size: CGFloat = 20

    var body: some View {
        TintIcon(systemName: kind.icon, color: kind.badgeColor, size: size)
    }
}

/// Modern soft-tint icon: coloured glyph on a light wash of the same colour.
struct TintIcon: View {
    var systemName: String
    var color: Color
    var size: CGFloat = 20
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(scheme == .dark ? 0.24 : 0.14),
                        in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

/// Coloured capsule for status and facts ("Running", "PHP 8.5").
struct Chip: View {
    var text: LocalizedStringKey
    var color: Color = .secondary
    var systemImage: String? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 9, weight: .bold)) }
            Text(text)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(color)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(color.opacity(scheme == .dark ? 0.22 : 0.12), in: Capsule())
    }
}

/// Rounded container for a group of rows.
struct ListCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5))
            .padding(.horizontal, Metrics.inset)
    }
}

/// Coloured badge, kept for sheets and the app mark.
struct IconBadge: View {
    var systemName: String
    var color: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
    }
}

// MARK: - Shared pieces

struct LogText: View {
    var text: String
    var autoscroll = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text.isEmpty ? " " : text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                Color.clear.frame(height: 1).id("bottom")
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: text) { if autoscroll { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }
}

enum Panels {
    @MainActor
    static func chooseFolder(_ message: String = String(localized: "Klasör seçin")) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = message
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    static func chooseFile(_ message: String = String(localized: "Dosya seçin")) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = message
        return panel.runModal() == .OK ? panel.url : nil
    }
}

struct BusyButton: View {
    var title: LocalizedStringKey
    var icon: String? = nil
    var busy: Bool
    var action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 4) {
                if busy { ProgressView().controlSize(.mini) } else if let icon { Image(systemName: icon) }
                Text(title)
            }
        }
        .disabled(busy)
    }
}

struct IconButton: View {
    var icon: String
    var help: LocalizedStringKey
    var tint: Color? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(tint ?? .secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}
