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
  { "text": "Install the skill CLI", "dueDate": null, "placeName": null },
  { "text": "Read the skill's SKILL.md", "dueDate": "2026-09-27T18:00:00Z", "placeName": null },
  { "text": "Try the skill out in a real project", "dueDate": null, "placeName": "Room" }
]
```

`dueDate` is ISO 8601 or `null`. `placeName` is a plain string or `null`, and
when present it's meant to exactly match the `name` of one of your existing
saved `Place`s (Anid asks the user to type their place names in its own
Settings, since it has no way to read remind-me's actual Place list).
At most one of `dueDate` / `placeName` is set per item, but treat both as
independently optional — don't assume they're mutually exclusive in the
data itself.

## Two kinds of imported reminder

- **Place-matched** (`placeName` matches an existing `Place.name`,
  case-insensitively): attach the new `Reminder` to that place, exactly
  like `AddReminderView` already does. No new notification code needed —
  the existing geofence machinery (`LocationManager`) already fires a
  notification whenever that place's region is entered, for any
  not-yet-completed reminder attached to it.
- **Placeless / time-based** (`placeName` is `null`, or names a place you
  haven't saved): create the `Reminder` with `place: nil`. If `dueDate` is
  set, schedule a one-shot notification for it directly — this is the part
  that needs a small addition, since today `NotificationManager
  .scheduleOneShot(fireDate:)` is only ever called for the daily digest, not
  for an individual reminder's own due date.

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
/// companion apps (e.g. Anid). When the imported item names one of the
/// user's existing places, it's attached there and rides the app's normal
/// geofence notifications. Otherwise it's created placeless, and — if it
/// has a due date — fires once via a scheduled local notification, since
/// nothing else will trigger it.
enum ImportManager {
    private struct ImportedItem: Decodable {
        let text: String
        let dueDate: String?
        let placeName: String?
    }

    static func handle(url: URL, context: ModelContext) {
        guard url.scheme == "remindme", url.host == "importReminders" else { return }
        guard let payload = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "payload" })?.value,
            let data = Data(base64Encoded: payload) else { return }

        guard let items = try? JSONDecoder().decode([ImportedItem].self, from: data) else { return }
        let isoFormatter = ISO8601DateFormatter()
        let allPlaces = (try? context.fetch(FetchDescriptor<Place>())) ?? []

        for imported in items {
            let dueDate = imported.dueDate.flatMap { isoFormatter.date(from: $0) }
            let matchedPlace = imported.placeName.flatMap { name in
                allPlaces.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            }

            let reminder = Reminder(text: imported.text, dueDate: dueDate, place: matchedPlace)
            context.insert(reminder)

            // Only placeless reminders need their own scheduled notification —
            // a place-attached one already fires when its geofence is entered.
            if matchedPlace == nil, let dueDate {
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

**Place-matched imports** (Anid sent a `placeName` that matches one of your
saved places, e.g. "Room") behave exactly like any other reminder you'd
added by hand from `PlaceDetailView`/`AddReminderView`: they show up under
that place, count toward the daily digest, and fire a notification the next
time you enter that place's geofence — no new UI needed for these.

**Placeless imports** (no `placeName`, or one that doesn't match anything
you've saved) show up in Remind Me with no place attached, so they won't
appear under any `Place`'s reminder list in the UI as written today —
`PlacesListView`/`PlaceDetailView` only browse place-attached reminders.
They *will* still count toward the daily digest (`DigestManager` already
scans all reminders regardless of place) and *will* fire their own
notification at `dueDate` via the code above, if one was set. If you want
placeless reminders visible in the main list too, that's a small follow-up
to `ContentView`/`PlacesListView` — a straightforward filter over
`Query<Reminder>` where `place == nil`, not covered by this patch.
