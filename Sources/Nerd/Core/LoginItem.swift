import Foundation
import ServiceManagement

/// Opening Nerd at login, as a login item of the app itself.
enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }
    static var enabled: Bool { status == .enabled }
    static var needsApproval: Bool { status == .requiresApproval }

    static func set(_ on: Bool) throws {
        if on {
            try SMAppService.mainApp.register()
        } else if status != .notRegistered {
            try SMAppService.mainApp.unregister()
        }
    }

    static var statusText: String {
        switch status {
        case .enabled: String(localized: "Oturum açılınca Nerd başlar.")
        case .requiresApproval: String(localized: "Onay bekliyor: Sistem Ayarları › Genel › Giriş Öğeleri'nden Nerd'e izin verin.")
        default: String(localized: "Oturum açılınca Nerd başlamaz.") // also .notFound: never registered yet
        }
    }
}
