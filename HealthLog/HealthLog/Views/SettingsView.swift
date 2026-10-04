import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(SettingsKeys.waterGoal) private var waterGoal = SettingsKeys.defaultWaterGoal
    @AppStorage(SettingsKeys.trackPeriod) private var trackPeriod = false
    @AppStorage(SettingsKeys.customSymptoms) private var customSymptomsRaw = ""
    @AppStorage(SettingsKeys.reminderEnabled) private var reminderEnabled = false
    @AppStorage(SettingsKeys.reminderTime) private var reminderTime = SettingsKeys.defaultReminderTime
    @AppStorage(SettingsKeys.lockEnabled) private var lockEnabled = false

    @State private var reminderMessage: String?

    private var reminderDate: Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(reminderTime) },
            set: { reminderTime = $0.timeIntervalSince(Calendar.current.startOfDay(for: $0)) }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tracking") {
                    Stepper("Water goal: \(waterGoal) glasses", value: $waterGoal, in: 1...20)
                    Toggle("Track period days", isOn: $trackPeriod)
                }

                Section {
                    TextField("e.g. Itching, Skin rash", text: $customSymptomsRaw, axis: .vertical)
                } header: {
                    Text("Your own symptoms")
                } footer: {
                    Text("Comma-separated. These show up under “Your own” when logging a symptom.")
                }

                Section {
                    Toggle("Daily reminder", isOn: $reminderEnabled)
                    if reminderEnabled {
                        DatePicker("Time", selection: reminderDate, displayedComponents: .hourAndMinute)
                    }
                    if let reminderMessage {
                        Text(reminderMessage).font(.caption).foregroundStyle(.red)
                    }
                } footer: {
                    Text("A nudge to log your day. Logging daily (even “nothing happened”) is what makes the patterns trustworthy.")
                }

                Section {
                    Toggle("Require Face ID", isOn: $lockEnabled)
                } footer: {
                    Text("Everything is stored only on this iPhone — there's no account, server, or sync. Deleting the app deletes your log, so export it now and then as a backup.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: reminderEnabled) { updateReminder() }
            .onChange(of: reminderTime) { updateReminder() }
        }
    }

    private func updateReminder() {
        // Not cleared when turning off: a failed schedule turns the toggle
        // off itself, and its message should stay visible.
        guard reminderEnabled else {
            ReminderService.cancel()
            return
        }
        reminderMessage = nil
        Task {
            let ok = await ReminderService.schedule(secondsSinceMidnight: reminderTime)
            if !ok {
                reminderEnabled = false
                reminderMessage = "Notifications are off for Health Log. Turn them on in iOS Settings → Notifications."
            }
        }
    }
}
