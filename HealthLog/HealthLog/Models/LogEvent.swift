import Foundation
import SwiftData

enum EventKind: String, Codable, CaseIterable, Identifiable {
    case symptom, bowel, food, medication, note

    var id: String { rawValue }

    var label: String {
        switch self {
        case .symptom: "Symptom"
        case .bowel: "Poop"
        case .food: "Food / drink"
        case .medication: "Medicine"
        case .note: "Note"
        }
    }

    var systemImage: String {
        switch self {
        case .symptom: "bolt.heart"
        case .bowel: "toilet"
        case .food: "fork.knife"
        case .medication: "pills"
        case .note: "note.text"
        }
    }
}

enum Meal: String, Codable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack, drink

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    /// A starting guess from the time of day; the user can change it.
    static func guess(for date: Date) -> Meal {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<11: .breakfast
        case 11..<16: .lunch
        case 18..<23: .dinner
        default: .snack
        }
    }
}

/// Anything that happens at a specific time during the day. One model for all
/// kinds keeps the day timeline, history, and CSV export simple; fields that
/// don't apply to a kind are just left empty.
@Model
final class LogEvent {
    var timestamp: Date
    /// Stored as a raw string so it can be used in #Predicate filters.
    var kindRaw: String
    /// Symptom name, food description, medicine name, or note text.
    var title: String
    /// Symptom severity, 1 (mild) ... 5 (severe). Also bowel pain for poops.
    var severity: Int?
    /// Bristol stool scale, 1 ... 7. Poops only.
    var bristol: Int?
    /// Food trigger tags or poop flags (blood, mucus, urgent...).
    var tags: [String]
    /// Medicine dose, or any extra free text.
    var detail: String
    /// Meal.rawValue for food entries, nil otherwise. Optional so existing
    /// data migrates automatically.
    var mealRaw: String?

    init(
        kind: EventKind,
        timestamp: Date = .now,
        title: String = "",
        severity: Int? = nil,
        bristol: Int? = nil,
        tags: [String] = [],
        detail: String = ""
    ) {
        self.timestamp = timestamp
        self.kindRaw = kind.rawValue
        self.title = title
        self.severity = severity
        self.bristol = bristol
        self.tags = tags
        self.detail = detail
        self.mealRaw = nil
    }

    var meal: Meal? {
        get { mealRaw.flatMap(Meal.init(rawValue:)) }
        set { mealRaw = newValue?.rawValue }
    }

    var kind: EventKind {
        get { EventKind(rawValue: kindRaw) ?? .note }
        set { kindRaw = newValue.rawValue }
    }

    var displayTitle: String {
        switch kind {
        case .bowel:
            if let bristol { return "Poop — type \(bristol)" }
            return "Poop"
        default:
            return title.isEmpty ? kind.label : title
        }
    }

    /// Whether this event is something worth flagging to a doctor.
    var isRedFlag: Bool {
        switch kind {
        case .symptom: Catalog.redFlagSymptoms.contains(title)
        case .bowel: tags.contains(Catalog.bloodFlag)
        default: false
        }
    }
}
