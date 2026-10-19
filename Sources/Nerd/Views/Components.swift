import SwiftUI
import AppKit

struct StatusDot: View {
    var on: Bool
    var body: some View {
        Circle().fill(on ? Color.green : Color.secondary.opacity(0.4)).frame(width: 8, height: 8)
    }
}

struct Pill: View {
    var text: LocalizedStringKey
    var color: Color = .secondary
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

struct Card<Content: View>: View {
    var title: LocalizedStringKey
    var icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.headline)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.6)))
    }
}

struct PageHeader<Trailing: View>: View {
    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.bold())
                if let subtitle { Text(subtitle).foregroundStyle(.secondary) }
            }
            Spacer()
            trailing
        }
        .padding(.bottom, 4)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

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
                    .padding(8)
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
                if busy { ProgressView().controlSize(.small) } else if let icon { Image(systemName: icon) }
                Text(title)
            }
        }
        .disabled(busy)
    }
}

/// System Settings–style icon: white glyph on a colored, softly graded rounded square.
struct IconBadge: View {
    var systemName: String
    var color: Color
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(color.gradient)
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            Image(systemName: systemName)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: size, height: size)
        .shadow(color: color.opacity(0.3), radius: size * 0.06, y: size * 0.03)
    }
}

/// Text inside a colored badge (e.g. PHP "8.4").
struct TextBadge: View {
    var text: String
    var color: Color
    var size: CGFloat = 34

    var body: some View {
        Text(text)
            .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .shadow(color: color.opacity(0.3), radius: 2, y: 1)
    }
}

struct SiteIcon: View {
    var kind: SiteKind
    var size: CGFloat = 22

    var body: some View {
        IconBadge(systemName: kind.icon, color: kind.badgeColor, size: size)
    }
}

struct StatTile: View {
    var icon: String
    var color: Color
    var title: LocalizedStringKey
    var value: LocalizedStringKey
    var on: Bool? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                IconBadge(systemName: icon, color: color, size: 28)
                Spacer()
                if let on { StatusDot(on: on) }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.title3.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator.opacity(0.5)))
    }
}

struct IconButton: View {
    var icon: String
    var help: LocalizedStringKey
    var tint: Color? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon).frame(width: 18, height: 18)
        }
        .help(help)
        .tint(tint)
    }
}
