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
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
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
    init(title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
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
        .padding(.horizontal, Metrics.inset)
        .padding(.top, 18).padding(.bottom, 4)
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
            .padding(.horizontal, Metrics.inset)
            .frame(minHeight: Metrics.row)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hover && action != nil ? Color.primary.opacity(0.045) : .clear)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .onTapGesture { action?() }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.6)).frame(height: 0.5)
                    .padding(.leading, Metrics.inset)
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
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .foregroundStyle(color)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(color.opacity(0.35), lineWidth: 0.5))
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
    var size: CGFloat = 12

    var body: some View {
        Glyph(systemName: kind.icon, size: size)
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
