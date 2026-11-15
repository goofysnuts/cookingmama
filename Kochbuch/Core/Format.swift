import Foundation
import SwiftUI

/// Feste Werte und deutsche Bezeichnungen (entsprechen lib/mealtime.ts, lib/diet.ts, lib/bake.ts im Backend)
enum Labels {
  static let mealTypes = ["fruehstueck", "mittag", "snack", "abend", "dessert", "immer"]
  static let configurableMealTypes = ["fruehstueck", "mittag", "snack", "abend"]

  static func mealType(_ key: String) -> String {
    switch key {
    case "fruehstueck": return "Frühstück"
    case "mittag": return "Mittagessen"
    case "snack": return "Snack"
    case "abend": return "Abendessen"
    case "dessert": return "Dessert"
    case "immer": return "Immer passend"
    default: return key
    }
  }

  static let dietTypes = ["vegan", "vegetarisch", "keins"]

  static func diet(_ key: String?) -> String {
    switch key {
    case "vegan": return "Vegan"
    case "vegetarisch": return "Vegetarisch"
    case "keins": return "Weder noch"
    default: return "Keine Einschränkung"
    }
  }

  static func dietColor(_ key: String?) -> Color {
    switch key {
    case "vegan": return .green
    case "vegetarisch": return .mint
    default: return .secondary
    }
  }

  static let bakeModes = ["ober_unterhitze", "umluft", "ober_unterhitze_umluft", "grill"]

  static func bakeMode(_ key: String?) -> String {
    switch key {
    case "ober_unterhitze": return "Ober-/Unterhitze"
    case "umluft": return "Umluft"
    case "ober_unterhitze_umluft": return "Ober-/Unterhitze + Umluft"
    case "grill": return "Grill"
    default: return "–"
    }
  }

  struct ReminderOption: Hashable {
    let hours: Int?
    let label: String
  }

  static let reminderIntervals: [ReminderOption] = [
    ReminderOption(hours: nil, label: "Keine Erinnerung"),
    ReminderOption(hours: 24, label: "Täglich"),
    ReminderOption(hours: 72, label: "Alle 3 Tage"),
    ReminderOption(hours: 168, label: "Wöchentlich"),
  ]

  static let commonUnits = ["g", "kg", "ml", "l", "Stück", "EL", "TL", "Prise", "Bund", "Dose", "Packung", "Zehe", "Scheibe", "Becher"]
}

enum Fmt {
  private static let numberFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.locale = Locale(identifier: "de_DE")
    f.numberStyle = .decimal
    f.maximumFractionDigits = 2
    f.minimumFractionDigits = 0
    return f
  }()

  static func number(_ value: Double) -> String {
    numberFormatter.string(from: NSNumber(value: value)) ?? String(value)
  }

  static func quantity(_ value: Double, _ unit: String?) -> String {
    let u = (unit ?? "").trimmingCharacters(in: .whitespaces)
    return u.isEmpty ? number(value) : "\(number(value)) \(u)"
  }

  /// Text-Eingabe ("1,5") in Zahl umwandeln
  static func parse(_ text: String) -> Double? {
    let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
    guard !t.isEmpty else { return nil }
    return Double(t)
  }

  static func editable(_ value: Double?) -> String {
    guard let value else { return "" }
    return number(value).replacingOccurrences(of: ".", with: "")
  }

  static func minutes(_ minutes: Int) -> String {
    if minutes < 60 { return "\(minutes) Min." }
    let h = minutes / 60
    let m = minutes % 60
    return m == 0 ? "\(h) Std." : "\(h) Std. \(m) Min."
  }

  static func range(_ min: Int, _ max: Int) -> String {
    if min == max { return minutes(min) }
    if min % 60 == 0, max % 60 == 0 { return "\(min / 60)–\(max / 60) Std." }
    return "\(minutes(min)) – \(minutes(max))"
  }

  static func restPlan(_ p: RestPlan) -> String {
    let d = range(p.minMinutes, p.maxMinutes)
    return p.location.isEmpty ? d : "\(d) (\(p.location))"
  }

  private static let isoFull: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()

  private static let isoPlain = ISO8601DateFormatter()

  static func date(_ s: String?) -> Date? {
    guard let s else { return nil }
    return isoFull.date(from: s) ?? isoPlain.date(from: s)
  }

  static func relative(_ s: String?) -> String {
    guard let d = date(s) else { return "" }
    let f = RelativeDateTimeFormatter()
    f.locale = Locale(identifier: "de_DE")
    f.unitsStyle = .full
    return f.localizedString(for: d, relativeTo: Date())
  }

  static func day(_ s: String?) -> String {
    guard let d = date(s) else { return "" }
    return d.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "de_DE")))
  }
}

extension String {
  var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
  var nilIfEmpty: String? { trimmed.isEmpty ? nil : trimmed }
}
