import SwiftUI
import SwiftData

/// Add or edit one timeline event. The form changes with the kind.
struct EventEditorView: View {
    let kind: EventKind
    let event: LogEvent?
    let day: Date

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.customSymptoms) private var customSymptomsRaw = ""

    @Query(
        filter: #Predicate<LogEvent> { $0.kindRaw == "medication" },
        sort: \LogEvent.timestamp,
        order: .reverse
    ) private var pastMedications: [LogEvent]

    @State private var timestamp: Date
    @State private var title: String
    @State private var severity: Int?
    @State private var bristol: Int?
    @State private var tags: Set<String>
    @State private var detail: String
    /// New symptoms can be logged several at once (e.g. burning + urgency).
    @State private var selectedSymptoms: Set<String>
    @State private var newSymptom = ""

    init(kind: EventKind, event: LogEvent?, day: Date) {
        self.kind = kind
        self.event = event
        self.day = day

        let defaultTime: Date
        if Calendar.current.isDateInToday(day) {
            defaultTime = .now
        } else {
            defaultTime = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        }
        _timestamp = State(initialValue: event?.timestamp ?? defaultTime)
        _title = State(initialValue: event?.title ?? "")
        _severity = State(initialValue: event?.severity ?? (kind == .symptom ? 3 : nil))
        _bristol = State(initialValue: event?.bristol ?? (kind == .bowel ? 4 : nil))
        _tags = State(initialValue: Set(event?.tags ?? []))
        _detail = State(initialValue: event?.detail ?? "")
        _selectedSymptoms = State(initialValue: event.map { [$0.title] } ?? [])
    }

    private var customSymptoms: [String] { SettingsKeys.parseList(customSymptomsRaw) }

    private var canSave: Bool {
        switch kind {
        case .symptom: !selectedSymptoms.isEmpty && severity != nil
        case .bowel: bristol != nil
        case .food, .medication, .note: !title.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                switch kind {
                case .symptom: symptomFields
                case .bowel: bowelFields
                case .food: foodFields
                case .medication: medicationFields
                case .note: noteFields
                }

                Section {
                    DatePicker("Time", selection: $timestamp, in: ...Date.now)
                }
            }
            .navigationTitle(event == nil ? "Log \(kind.label.lowercased())" : "Edit \(kind.label.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
        }
    }

    // MARK: - Symptom

    @ViewBuilder private var symptomFields: some View {
        Section {
            RatingRow(title: "How bad?", low: "Very mild", high: "Severe", value: $severity)
        }
        symptomSection("Urinary / UTI", Catalog.urinarySymptoms)
        symptomSection("Gut / IBS", Catalog.gutSymptoms)
        symptomSection("General", Catalog.generalSymptoms)
        if !customSymptoms.isEmpty {
            symptomSection("Your own", customSymptoms)
        }
        Section {
            HStack {
                TextField("Something else…", text: $newSymptom)
                Button("Add", action: addCustomSymptom)
                    .disabled(newSymptom.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } footer: {
            Text("Added symptoms are saved to “Your own” for next time.")
        }
        Section("Notes") {
            TextField("Optional", text: $detail, axis: .vertical)
        }
    }

    private func symptomSection(_ header: String, _ symptoms: [String]) -> some View {
        Section(header) {
            ForEach(symptoms, id: \.self) { symptom in
                Button {
                    toggleSymptom(symptom)
                } label: {
                    HStack {
                        Text(symptom)
                            .foregroundStyle(Catalog.redFlagSymptoms.contains(symptom) ? Color.red : Color.primary)
                        Spacer()
                        if selectedSymptoms.contains(symptom) {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
            }
        }
    }

    private func toggleSymptom(_ symptom: String) {
        if event != nil {
            // Editing one existing entry: single choice.
            selectedSymptoms = [symptom]
        } else if selectedSymptoms.contains(symptom) {
            selectedSymptoms.remove(symptom)
        } else {
            selectedSymptoms.insert(symptom)
        }
    }

    private func addCustomSymptom() {
        let name = newSymptom.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let allKnown = Catalog.urinarySymptoms + Catalog.gutSymptoms + Catalog.generalSymptoms + customSymptoms
        if !allKnown.contains(name) {
            customSymptomsRaw = (customSymptoms + [name.replacingOccurrences(of: ",", with: " ")]).joined(separator: ", ")
        }
        toggleSymptom(name)
        newSymptom = ""
    }

    // MARK: - Poop

    @ViewBuilder private var bowelFields: some View {
        Section {
            ForEach(1...7, id: \.self) { type in
                Button {
                    bristol = type
                } label: {
                    HStack {
                        Text("\(type)").bold().frame(width: 20)
                        VStack(alignment: .leading) {
                            Text(Catalog.bristolDescriptions[type] ?? "")
                            Text(Catalog.bristolMeaning(type))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if bristol == type {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                    .foregroundStyle(Color.primary)
                }
            }
        } header: {
            Text("Type (Bristol stool scale)")
        } footer: {
            Text("1–2 lean constipated, 3–4 are normal, 5–7 lean loose. Tracking this is the main way doctors tell IBS-C, IBS-D and mixed apart.")
        }
        Section("Anything else?") {
            TagGrid(options: Catalog.bowelFlags, selection: $tags, highlight: [Catalog.bloodFlag])
        }
        Section {
            RatingRow(title: "Pain", low: "Mild", high: "Severe", value: $severity)
        } footer: {
            Text("Leave empty if it didn't hurt.")
        }
        Section("Notes") {
            TextField("Optional", text: $detail, axis: .vertical)
        }
    }

    // MARK: - Food

    @ViewBuilder private var foodFields: some View {
        Section("What did you eat or drink?") {
            TextField("e.g. Paneer pizza and a Coke", text: $title, axis: .vertical)
        }
        Section {
            TagGrid(options: Catalog.foodTags, selection: $tags, highlight: [])
        } header: {
            Text("Contains")
        } footer: {
            Text("Tags power the patterns on the Trends tab — they're what let the app notice e.g. “bloating is worse after dairy”.")
        }
        Section("Notes") {
            TextField("Optional", text: $detail, axis: .vertical)
        }
    }

    // MARK: - Medicine

    private var recentMedicationNames: [String] {
        var seen = Set<String>()
        return pastMedications.compactMap { med in
            seen.insert(med.title).inserted ? med.title : nil
        }
        .prefix(8)
        .map { $0 }
    }

    @ViewBuilder private var medicationFields: some View {
        Section("Medicine") {
            TextField("Name", text: $title)
            TextField("Dose (optional), e.g. 500 mg", text: $detail)
        }
        if !recentMedicationNames.isEmpty {
            Section("Recent") {
                ForEach(recentMedicationNames, id: \.self) { name in
                    Button(name) {
                        title = name
                        if let last = pastMedications.first(where: { $0.title == name }), detail.isEmpty {
                            detail = last.detail
                        }
                    }
                }
            }
        }
    }

    // MARK: - Note

    @ViewBuilder private var noteFields: some View {
        Section("Note") {
            TextField("Anything worth remembering", text: $title, axis: .vertical)
                .lineLimit(3...10)
        }
    }

    // MARK: - Save

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let orderedTags = orderTags(tags)

        if kind == .symptom {
            var symptoms = Array(selectedSymptoms).sorted()
            if let event, let first = symptoms.first {
                apply(to: event, title: first, tags: [], detail: cleanDetail)
                symptoms.removeFirst()
            }
            for symptom in symptoms {
                let new = LogEvent(kind: .symptom)
                apply(to: new, title: symptom, tags: [], detail: cleanDetail)
                modelContext.insert(new)
            }
        } else {
            let target = event ?? LogEvent(kind: kind)
            apply(to: target, title: cleanTitle, tags: orderedTags, detail: cleanDetail)
            if event == nil { modelContext.insert(target) }
        }
        dismiss()
    }

    private func apply(to target: LogEvent, title: String, tags: [String], detail: String) {
        target.timestamp = timestamp
        target.title = title
        target.severity = severity
        target.bristol = kind == .bowel ? bristol : nil
        target.tags = tags
        target.detail = detail
    }

    /// Keep tags in the catalog's order so exports read consistently.
    private func orderTags(_ tags: Set<String>) -> [String] {
        let order = Catalog.bowelFlags + Catalog.foodTags
        return tags.sorted { (order.firstIndex(of: $0) ?? .max) < (order.firstIndex(of: $1) ?? .max) }
    }
}

/// Toggleable chips in a grid.
struct TagGrid: View {
    let options: [String]
    @Binding var selection: Set<String>
    let highlight: Set<String>

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], alignment: .leading, spacing: 8) {
            ForEach(options, id: \.self) { option in
                let isOn = selection.contains(option)
                Button {
                    if isOn { selection.remove(option) } else { selection.insert(option) }
                } label: {
                    Text(option)
                        .font(.subheadline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule().fill(isOn
                                ? (highlight.contains(option) ? Color.red : Color.accentColor)
                                : Color.secondary.opacity(0.15))
                        )
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}
