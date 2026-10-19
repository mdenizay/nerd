import SwiftUI
import WebKit

struct MailView: View {
    @Environment(AppState.self) private var state
    @State private var selection: MailMessage.ID?
    @State private var filter = ""
    @State private var confirmClear = false

    private var filtered: [MailMessage] {
        filter.isEmpty ? state.mails : state.mails.filter {
            $0.subject.localizedCaseInsensitiveContains(filter) || $0.to.localizedCaseInsensitiveContains(filter)
                || $0.from.localizedCaseInsensitiveContains(filter)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(filtered, selection: $selection) { m in
                    MailRow(mail: m, unread: !state.readMail.contains(m.id)).tag(m.id)
                }
                .searchable(text: $filter, placement: .sidebar, prompt: "Ara")
                .overlay {
                    if state.mails.isEmpty {
                        ContentUnavailableView {
                            Label("Gelen kutusu boş", systemImage: "tray")
                        } description: {
                            Text("Uygulamanız 127.0.0.1:\(String(state.config.mailPort)) SMTP adresine gönderdiği e-postalar burada görünür.")
                        }
                    }
                }
                Divider()
                HStack {
                    StatusDot(on: state.mailRunning)
                    Text("SMTP :\(String(state.config.mailPort))").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { confirmClear = true } label: { NerdIcon(name: "trash") }
                        .disabled(state.mails.isEmpty)
                        .help("Tümünü sil")
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .frame(width: 290)
            Divider()

            Group {
                if let mail = state.mails.first(where: { $0.id == selection }) {
                    MailDetail(mail: mail).id(mail.id)
                } else {
                    ContentUnavailableView("E-posta seçin", systemImage: "envelope")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .confirmationDialog("Tüm e-postalar silinsin mi?", isPresented: $confirmClear) {
            Button("Tümünü sil", role: .destructive) { state.deleteAllMail(); selection = nil }
        }
        .onChange(of: selection) {
            if let m = state.mails.first(where: { $0.id == selection }) { state.markRead(m) }
        }
        .onAppear {
            state.loadMail()
            if selection == nil { selection = state.mails.first?.id }
        }
    }
}

private struct MailRow: View {
    let mail: MailMessage
    let unread: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(unread ? Color.accentColor : .clear).frame(width: 7, height: 7).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(mail.to.ifEmpty("—")).font(.callout.weight(unread ? .semibold : .regular)).lineLimit(1)
                    Spacer()
                    Text(mail.date, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(.secondary)
                }
                Text(mail.subject).font(.callout).lineLimit(1)
                Text(mail.from).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct MailDetail: View {
    @Environment(AppState.self) private var state
    let mail: MailMessage
    @State private var tab: Int

    init(mail: MailMessage) {
        self.mail = mail
        _tab = State(initialValue: mail.html != nil ? 0 : 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text(mail.subject).font(.system(size: 15, weight: .semibold)).textSelection(.enabled)
                    Spacer()
                    Button { state.deleteMail(mail) } label: { NerdIcon(name: "trash") }
                        .help("Sil")
                }
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                    GridRow { Text("Kimden").foregroundStyle(.secondary); Text(mail.from).textSelection(.enabled) }
                    GridRow { Text("Kime").foregroundStyle(.secondary); Text(mail.to).textSelection(.enabled) }
                    GridRow { Text("Tarih").foregroundStyle(.secondary); Text(mail.date, format: .dateTime) }
                }
                .font(.callout)
                if !mail.attachments.isEmpty {
                    HStack {
                        ForEach(mail.attachments, id: \.self) { Label($0, systemImage: "paperclip").font(.caption) }
                    }
                }
                Picker("", selection: $tab) {
                    Text("HTML").tag(0)
                    Text("Metin").tag(1)
                    Text("Kaynak").tag(2)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            .padding(16)
            Divider()
            switch tab {
            case 0:
                if let html = mail.html { HTMLView(html: html) } else { empty("Bu e-postanın HTML sürümü yok.") }
            case 1:
                if let text = mail.text { LogText(text: text, autoscroll: false) } else { empty("Bu e-postanın metin sürümü yok.") }
            default:
                LogText(text: (try? String(contentsOf: mail.url, encoding: .utf8)) ?? "", autoscroll: false)
            }
        }
    }

    private func empty(_ text: LocalizedStringKey) -> some View {
        Text(text).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Renders email HTML without JavaScript. Emails are designed for light backgrounds,
/// so the preview stays light like Mail.app does.
struct HTMLView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.appearance = NSAppearance(named: .aqua)
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loaded != html else { return }
        context.coordinator.loaded = html
        view.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded: String?

        // Open links in the default browser instead of inside the preview
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
