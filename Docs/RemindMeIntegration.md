# Wiring Anid into Remind Me

Anid hands off todo items to your `remind-me` app via a custom URL scheme:
`remindme://importReminders?payload=<base64-encoded JSON>`. This only works
once `remind-me` knows how to receive that link — it doesn't yet. This file
is the exact patch to add there.

(Why not a shared database or App Group? The two apps are independent codebases
with their own SwiftData schemas. A URL-scheme handoff keeps them decoupled —
either app can evolve its own model without breaking the other.)

## What Anid sends

A JSON array, base64-encoded into the `payload` query parameter:

```json
[
  { "text": "Install the skill CLI", "dueDate": null },
  { "text": "Read the skill's SKILL.md", "dueDate": "2026-09-27T18:00:00Z" }
]
```

`dueDate` is ISO 8601 or `null`.

## Why this needs a small feature addition, not just a URL handler

Remind Me's reminders today are **geofence-triggered** — a `Reminder` fires
when you enter its `Place`'s region. Ideas from Anid aren't tied to a place,
so they need Remind Me to support a **placeless, time-based** reminder that
fires once at a specific date/time instead. The good news: `NotificationManager`
already has exactly the primitive for this —`scheduleOneShot(fireDate:)` —
it's just only used today for the daily digest. This patch reuses it per-reminder.

## 1. Register the URL scheme

In `project.yml`, under the `Anid` target's... sorry, the `RemindMe` target's
`info.properties`, add:

```yaml
        CFBundleURLTypes:
          - CFBundleURLSchemes: [remindme]
            CFBundleURLName: com.hasini.remindme
```

Then re-run `xcodegen generate`.

## 2. Add an import handler

New file `RemindMe/Services/ImportManager.swift`:

```swift
import Foundation
import SwiftData

/// Parses `remindme://importReminders?payload=<base64 JSON>` links sent by
/// companion apps (e.g. Anid) and creates placeless, time-based reminders
/// from them. Unlike the geofence-triggered reminders elsewhere in this
/// app, these fire once at a specific date via a scheduled local
/// notification, since they aren't tied to a saved Place.
enum ImportManager {
    private struct ImportedItem: Decodable {
        let text: String
        let dueDate: String?
    }

    static func handle(url: URL, context: ModelContext) {
        guard url.scheme == "remindme", url.host == "importReminders" else { return }
        guard let payload = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "payload" })?.value,
            let data = Data(base64Encoded: payload) else { return }

        guard let items = try? JSONDecoder().decode([ImportedItem].self, from: data) else { return }
        let isoFormatter = ISO8601DateFormatter()

        for imported in items {
            let dueDate = imported.dueDate.flatMap { isoFormatter.date(from: $0) }
            let reminder = Reminder(text: imported.text, dueDate: dueDate, place: nil)
            context.insert(reminder)

            if let dueDate {
                NotificationManager.shared.scheduleOneShot(
                    identifier: reminder.id.uuidString,
                    title: "Reminder",
                    body: reminder.text,
                    fireDate: dueDate
                )
            }
        }
    }
}
```

## 3. Hook it into the app

In `RemindMe/Views/ContentView.swift`, add `.onOpenURL` to the view chain
(alongside the existing `.onAppear`/`.onChange` modifiers):

```swift
.onOpenURL { url in
    ImportManager.handle(url: url, context: modelContext)
}
```

## After applying

A reminder imported this way will show up in Remind Me with no place
attached, so it won't appear under any `Place`'s reminder list in the UI as
written today — `PlacesListView`/`PlaceDetailView` only browse
place-attached reminders. It *will* count toward the daily digest
(`DigestManager` already scans all reminders regardless of place), and it
*will* fire its own notification at `dueDate` via the code above. If you
want placeless reminders visible in the main list too, that's a small
follow-up to `ContentView`/`PlacesListView` — a straightforward filter over
`Query<Reminder>` where `place == nil`, not covered by this patch.
