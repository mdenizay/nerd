import SwiftUI
import AppKit

// MARK: - Design kit
//
// Premium and quiet: one brand colour (the violet of the app icon), neutral
// tiles and text, Liquid Glass surfaces (materials before macOS 26) floating
// over a faint brand-tinted backdrop. Colour carries meaning only: status
// dots, the selection and the primary action.

extension Color {
    static let brand = Color(red: 0.45, green: 0.36, blue: 0.95)
}

enum Metrics {
    static let inset: CGFloat = 20
    static let row: CGFloat = 32
    static let radius: CGFloat = 14
}

extension View {
    /// Liquid Glass on macOS 26+, a material before that.
    @ViewBuilder
    func glassSurface<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            let base: Glass = tint.map { Glass.regular.tint($0) } ?? .regular
            self.glassEffect(interactive ? base.interactive() : base, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
    }

    @ViewBuilder
    func primaryButton() -> some View {
        if #available(macOS 26.0, *) { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.borderedProminent) }
    }

    @ViewBuilder
    func glassButton() -> some View {
        if #available(macOS 26.0, *) { self.buttonStyle(.glass) } else { self.buttonStyle(.bordered) }
    }
}

/// Quiet glass capsule for header actions: neutral, never a block of colour.
struct QuietButtonStyle: ButtonStyle {
    @State private var hover = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.primary.opacity(configuration.isPressed ? 0.5 : 0.8))
            .padding(.horizontal, 9).frame(height: 26)
            .glassSurface(Capsule(), interactive: true)
            .contentShape(Capsule())
    }
}

/// The faint brand-tinted field the glass sits on.
struct Backdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(colors: [Color.brand.opacity(scheme == .dark ? 0.16 : 0.10), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 700)
            RadialGradient(colors: [Color.brand.opacity(scheme == .dark ? 0.08 : 0.05), .clear],
                           center: .bottomLeading, startRadius: 0, endRadius: 600)
        }
        .ignoresSafeArea()
    }
}

/// Page title: large title, quiet note, glass actions on the right.
struct Header<Trailing: View>: View {
    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 20, weight: .semibold)).tracking(-0.3)
                if let subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) { trailing }
                .controlSize(.small)
                .buttonStyle(QuietButtonStyle())
        }
        .padding(.horizontal, Metrics.inset)
        .padding(.top, 12).padding(.bottom, 6)
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
            Text(text).textCase(.uppercase)
                .font(.system(size: 10.5, weight: .semibold)).tracking(0.6)
                .foregroundStyle(.tertiary)
            Spacer()
            trailing.font(.system(size: 11)).controlSize(.mini).buttonStyle(.borderless)
        }
        .padding(.horizontal, Metrics.inset + 4)
        .padding(.top, 18).padding(.bottom, 6)
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
            .padding(.horizontal, 14)
            .frame(minHeight: Metrics.row)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hover && action != nil ? Color.primary.opacity(0.05) : .clear)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .onTapGesture { action?() }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 0.5)
                    .padding(.leading, 14)
            }
    }
}

/// Glass container for a group of rows.
struct ListCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
            .glassSurface(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
            .padding(.horizontal, Metrics.inset)
    }
}

/// Neutral icon tile; `emphasized` uses the brand colour.
struct Tile: View {
    var systemName: String
    var brand: String? = nil
    var size: CGFloat = 20
    var emphasized = false

    var body: some View {
        Group {
            if let brand, Brands.exists(brand) {
                BrandLogo(slug: brand, size: size * 0.64)
            } else {
                NerdIcon(name: systemName, size: size * 0.55)
                    .foregroundStyle(emphasized ? Color.white : Color.primary.opacity(0.75))
            }
        }
        .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(emphasized ? AnyShapeStyle(Color.brand.gradient) : AnyShapeStyle(Color.primary.opacity(0.06)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(Color.primary.opacity(emphasized ? 0 : 0.08), lineWidth: 0.5)
            }
    }
}

/// A monochrome symbol at row size.
struct Glyph: View {
    var systemName: String
    var color: Color = .secondary
    var size: CGFloat = 12

    var body: some View {
        NerdIcon(name: systemName, size: size + 1)
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
            .shadow(color: on ? color.opacity(0.6) : .clear, radius: 3)
    }
}

/// Glass capsule for facts and status. Only `tone` adds colour (a dot).
struct Chip: View {
    enum Tone { case neutral, positive, negative }
    var text: LocalizedStringKey
    var systemImage: String? = nil
    var tone: Tone = .neutral

    var body: some View {
        HStack(spacing: 5) {
            switch tone {
            case .positive: StatusDot(on: true)
            case .negative: StatusDot(on: true, color: .red)
            case .neutral: if let systemImage { Image(systemName: systemImage).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary) }
            }
            Text(text)
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 9).padding(.vertical, 4)
        .glassSurface(Capsule())
    }
}

/// A small tag; `accent` uses the brand colour.
struct Pill: View {
    var text: LocalizedStringKey
    var accent = false
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 1.5)
            .foregroundStyle(accent ? Color.brand : .secondary)
            .background((accent ? Color.brand : Color.primary).opacity(accent ? 0.12 : 0.06), in: Capsule())
    }
}

/// Borderless "…" menu used at the end of rows.
struct MoreMenu<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        Menu { content } label: {
            NerdIcon(name: "ellipsis", size: 14).foregroundStyle(.secondary)
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
        Tile(systemName: kind.icon, brand: kind.brand, size: size)
    }
}

/// Coloured badge, kept for sheets.
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
            NerdIcon(name: icon, size: 15)
                .foregroundStyle(tint ?? .secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}
