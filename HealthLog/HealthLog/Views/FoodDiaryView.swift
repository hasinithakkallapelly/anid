import SwiftUI
import SwiftData

/// Everything you've eaten, newest first, grouped by day and searchable —
/// e.g. search "dairy" or "pizza" to see every time you had it.
struct FoodDiaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<LogEvent> { $0.kindRaw == "food" },
        sort: \LogEvent.timestamp,
        order: .reverse
    ) private var foods: [LogEvent]

    @State private var search = ""
    @State private var editor: EditorRequest?

    private var filtered: [LogEvent] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return foods }
        return foods.filter { food in
            food.title.localizedCaseInsensitiveContains(query)
                || food.detail.localizedCaseInsensitiveContains(query)
                || food.tags.contains { $0.localizedCaseInsensitiveContains(query) }
                || (food.meal?.label.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var days: [(day: Date, items: [LogEvent])] {
        let grouped = Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.timestamp) }
        return grouped
            .map { (day: $0.key, items: $0.value.sorted { $0.timestamp < $1.timestamp }) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        NavigationStack {
            Group {
                if foods.isEmpty {
                    ContentUnavailableView(
                        "No food logged yet",
                        systemImage: "fork.knife",
                        description: Text("Tap + after each meal, snack or drink. Foods you've had before are one tap to log again.")
                    )
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else {
                    List {
                        ForEach(days, id: \.day) { group in
                            Section {
                                ForEach(group.items) { food in
                                    Button {
                                        editor = EditorRequest(kind: .food, event: food)
                                    } label: {
                                        EventRow(event: food)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .onDelete { offsets in
                                    for index in offsets { modelContext.delete(group.items[index]) }
                                }
                            } header: {
                                Text(dayTitle(group.day))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Food")
            .searchable(text: $search, prompt: "Search foods or tags")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        editor = EditorRequest(kind: .food, event: nil)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(item: $editor) { request in
            EventEditorView(kind: .food, event: request.event, day: request.event?.timestamp ?? .now)
        }
    }

    private func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month())
    }
}
