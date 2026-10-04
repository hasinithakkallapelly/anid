import Foundation

/// The built-in pick lists. Custom symptoms from Settings are added on top.
enum Catalog {
    static let urinarySymptoms = [
        "Burning when peeing",
        "Urgency (sudden need to pee)",
        "Peeing often, small amounts",
        "Lower belly / pelvic pain",
        "Cloudy or strong-smelling urine",
        "Blood in urine",
        "Back or side pain",
        "Fever / chills",
    ]

    // Diarrhea / constipation live in the poop log (Bristol type) instead,
    // so they aren't logged twice.
    static let gutSymptoms = [
        "Bloating",
        "Stomach pain / cramps",
        "Gas",
        "Nausea",
        "Heartburn / reflux",
        "Loss of appetite",
    ]

    static let generalSymptoms = [
        "Fatigue",
        "Headache",
        "Anxiety",
        "Back pain",
        "Period cramps",
    ]

    /// Urinary symptoms that can mean an infection has spread past the
    /// bladder (or something else needing a doctor), rather than a simple UTI.
    static let redFlagSymptoms: Set<String> = [
        "Blood in urine",
        "Back or side pain",
        "Fever / chills",
    ]

    static let bloodFlag = "Blood"

    static let bowelFlags = ["Urgent", "Straining", "Felt incomplete", "Painful", "Mucus", bloodFlag]

    /// Common IBS triggers (several are high-FODMAP) plus common bladder
    /// irritants (caffeine, alcohol, fizzy, acidic, sweeteners, spicy).
    static let foodTags = [
        "Dairy",
        "Wheat / gluten",
        "Onion / garlic",
        "Beans / lentils",
        "Spicy",
        "Fried / fatty",
        "Caffeine",
        "Alcohol",
        "Fizzy drinks",
        "Citrus / acidic",
        "Artificial sweeteners",
        "Big meal",
    ]

    static let bristolDescriptions = [
        1: "Separate hard lumps",
        2: "Lumpy, sausage-shaped",
        3: "Sausage with cracks",
        4: "Smooth, soft sausage",
        5: "Soft blobs, clear edges",
        6: "Mushy, ragged edges",
        7: "Watery, no solid pieces",
    ]

    static func bristolMeaning(_ type: Int) -> String {
        switch type {
        case 1, 2: "Constipated"
        case 3, 4: "Normal"
        case 5: "Leaning loose"
        default: "Diarrhea"
        }
    }

    static func severityLabel(_ value: Int) -> String {
        switch value {
        case 1: "Very mild"
        case 2: "Mild"
        case 3: "Moderate"
        case 4: "Bad"
        default: "Severe"
        }
    }

    static func isUrinary(_ symptom: String) -> Bool { urinarySymptoms.contains(symptom) }
    static func isGut(_ symptom: String) -> Bool { gutSymptoms.contains(symptom) }
}
