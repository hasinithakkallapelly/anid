import SwiftUI

/// The main tab: today's log, with arrows to go back and fill in past days.
struct TodayView: View {
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var isPresentingSettings = false
    @State private var isPresentingExport = false

    private var isToday: Bool { Calendar.current.isDateInToday(selectedDay) }

    var body: some View {
        NavigationStack {
            DayView(day: selectedDay)
                .navigationTitle(isToday ? "Today" : selectedDay.formatted(.dateTime.weekday(.abbreviated).day().month()))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            isPresentingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        Button {
                            shiftDay(by: -1)
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        Button {
                            shiftDay(by: 1)
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(isToday)
                        Button {
                            isPresentingExport = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    // Midnight passed while the app was open.
                    selectedDay = Calendar.current.startOfDay(for: .now)
                }
        }
        .sheet(isPresented: $isPresentingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $isPresentingExport) {
            ExportView()
        }
    }

    private func shiftDay(by days: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: days, to: selectedDay) else { return }
        selectedDay = min(next, Calendar.current.startOfDay(for: .now))
    }
}
