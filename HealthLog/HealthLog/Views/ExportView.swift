import SwiftUI
import SwiftData

/// A summary to show or send a doctor, plus the raw data as CSV.
struct ExportView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var events: [LogEvent]
    @Query private var dayLogs: [DayLog]
    @AppStorage(SettingsKeys.waterGoal) private var waterGoal = SettingsKeys.defaultWaterGoal

    @State private var start = Calendar.current.date(byAdding: .day, value: -29, to: .now) ?? .now
    @State private var end = Date.now
    @State private var output: Exporter.Output?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("From", selection: $start, in: ...end, displayedComponents: .date)
                    DatePicker("To", selection: $end, in: start...Date.now, displayedComponents: .date)
                } footer: {
                    Text("Tip: before a doctor visit, export since your symptoms started (or the last 1–3 months).")
                }

                Section {
                    Button("Create summary", action: generate)
                    if let output {
                        ShareLink(items: output.files) {
                            Label("Share summary + CSV files", systemImage: "square.and.arrow.up")
                        }
                    }
                } footer: {
                    Text("Shares a readable summary (.txt) and your full data as two spreadsheets (.csv). Also works as a backup — save them to Files.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }

                if let output {
                    Section("Preview") {
                        Text(output.summary)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: start) { output = nil }
            .onChange(of: end) { output = nil }
        }
    }

    private func generate() {
        do {
            output = try Exporter.make(from: start, to: end, events: events, dayLogs: dayLogs, waterGoal: waterGoal)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't create the files: \(error.localizedDescription)"
        }
    }
}
