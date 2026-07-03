import Foundation

/// Localization: German + English
/// Uses system language automatically.
enum L10n {
    // MARK: - Section Headers
    static var temperature: String { loc("TEMPERATURE", de: "TEMPERATUR") }
    static var mode: String { loc("MODE", de: "MODUS") }
    static var fanCurve: String { loc("FAN CURVE", de: "LÜFTERKURVE") }
    static var manualControl: String { loc("MANUAL CONTROL", de: "MANUELLE STEUERUNG") }
    static var appearance: String { loc("APPEARANCE", de: "DARSTELLUNG") }
    static var helper: String { loc("HELPER", de: "HILFSPROGRAMM") }
    static var profiles: String { loc("PROFILES", de: "PROFILE") }
    static var history: String { loc("HISTORY", de: "VERLAUF") }

    // MARK: - Temperature
    static var cpuTemperature: String { loc("CPU Temperature", de: "CPU-Temperatur") }
    static var gpuTemperature: String { loc("GPU Temperature", de: "GPU-Temperatur") }

    // MARK: - Mode
    static var fanMode: String { loc("Fan Mode", de: "Lüftermodus") }
    static var automatic: String { loc("Automatic", de: "Automatisch") }
    static var manual: String { loc("Manual", de: "Manuell") }
    static var fanCurveMode: String { loc("Fan Curve", de: "Lüfterkurve") }
    static var restore: String { loc("Restore", de: "Wiederherstellen") }

    // MARK: - Fan Control
    static var allFans: String { loc("All Fans", de: "Alle Lüfter") }
    static func fan(_ n: Int) -> String { loc("Fan \(n)", de: "Lüfter \(n)") }

    // MARK: - Curve
    static var activate: String { loc("Activate", de: "Aktivieren") }
    static var reset: String { loc("Reset", de: "Zurücksetzen") }
    static var followingCurve: String { loc("Following curve...", de: "Kurve aktiv...") }

    // MARK: - Profiles
    static var silent: String { loc("Silent", de: "Leise") }
    static var balanced: String { loc("Balanced", de: "Ausgewogen") }
    static var performance: String { loc("Performance", de: "Leistung") }
    static var gaming: String { loc("Gaming", de: "Gaming") }
    static var custom: String { loc("Custom", de: "Eigene") }

    // MARK: - Helper
    static var privilegedHelper: String { loc("Privileged Helper", de: "Hilfsprogramm") }
    static var installed: String { loc("Installed — fan control active", de: "Installiert — Lüftersteuerung aktiv") }
    static var required: String { loc("Required for fan speed control", de: "Für Lüftersteuerung erforderlich") }
    static var install: String { loc("Install", de: "Installieren") }
    static var installing: String { loc("Installing...", de: "Installiere...") }
    static var remove: String { loc("Remove", de: "Entfernen") }
    static var approvalNeeded: String { loc("Enable it in Login Items to finish", de: "Zum Abschluss in Anmeldeobjekten aktivieren") }
    static var openSettings: String { loc("Open Settings", de: "Einstellungen öffnen") }
    static var finishSetup: String { loc("Approve…", de: "Freigeben…") }
    static var approvalTitle: String { loc("Almost done — approve the helper", de: "Fast fertig — Helper freigeben") }
    static var approvalStep1: String { loc("Click “Open Settings” below", de: "Unten „Einstellungen öffnen“ klicken") }
    static var approvalStep2: String { loc("Scroll to “Allow in the Background”", de: "Zum Abschnitt „Im Hintergrund erlauben“ scrollen") }
    static var approvalStep3: String { loc("Turn on the switch next to FANcy", de: "Den Schalter neben FANcy einschalten") }
    static var approvalAutoDetect: String { loc("FANcy detects the approval automatically.", de: "FANcy erkennt die Freigabe automatisch.") }

    // MARK: - Appearance
    static var system: String { loc("System", de: "System") }
    static var light: String { loc("Light", de: "Hell") }
    static var dark: String { loc("Dark", de: "Dunkel") }

    // MARK: - Menu Bar
    static var openFANcy: String { loc("Open FANcy...", de: "FANcy öffnen...") }
    static var quitFANcy: String { loc("Quit FANcy", de: "FANcy beenden") }
    static var activateFanCurve: String { loc("Activate Fan Curve", de: "Lüfterkurve aktivieren") }

    // MARK: - Notifications
    static var tempWarningTitle: String { loc("High Temperature", de: "Hohe Temperatur") }
    static func tempWarningBody(_ t: Double) -> String {
        loc(String(format: "CPU temperature reached %.0f°C", t),
            de: String(format: "CPU-Temperatur hat %.0f°C erreicht", t))
    }
    static var fanFailureTitle: String { loc("Fan Failure", de: "Lüfterausfall") }
    static func fanFailureBody(_ n: Int) -> String {
        loc("Fan \(n) reports 0 RPM — possible failure",
            de: "Lüfter \(n) meldet 0 RPM — möglicher Ausfall")
    }

    // MARK: - Memory
    static var ramUsage: String { loc("RAM Usage", de: "RAM-Auslastung") }

    // MARK: - History
    static var last10Min: String { loc("Last 10 minutes", de: "Letzte 10 Minuten") }

    // MARK: - Helpers

    private static var isGerman: Bool {
        Locale.preferredLanguages.first?.hasPrefix("de") ?? false
    }

    private static func loc(_ en: String, de: String) -> String {
        isGerman ? de : en
    }
}
