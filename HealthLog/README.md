# Health Log

A private, personal iPhone app for tracking daily health — built around
urinary (UTI) and gut (IBS) symptoms. Separate app from Anid; it just lives
in this repo for now.

Everything is stored **only on the phone** (SwiftData). No account, no
server, no network calls.

## What you can log

**Today tab** — one screen per day (arrows to go back and fill in past days):

- **Daily numbers**: water (glasses), times peed, sleep, stress 1–5,
  overall feeling 1–5, period day (optional, turn on in Settings), notes.
- **Timeline events**, each with a time:
  - **Symptom** — pick from Urinary/UTI, Gut/IBS, General, or your own.
    Several at once (e.g. burning + urgency) with one severity 1–5.
  - **Poop** — Bristol stool type 1–7, plus urgent / straining / incomplete
    / painful / mucus / blood.
  - **Food / drink** — what you had and which meal (breakfast, lunch,
    dinner, snack, drink; guessed from the time), tagged with common IBS
    triggers and bladder irritants (dairy, onion/garlic, caffeine, alcohol,
    spicy, fizzy, citrus…). Foods you've had before show up as one-tap
    suggestions that fill in the name *and* its tags.
  - **Medicine** — name + dose, with recently used ones one tap away.
  - **Note**.
- **Red-flag warnings**: logging fever/chills, back or side pain, or blood
  in urine shows a "get seen today" banner (possible kidney infection);
  blood in poop shows a "tell a doctor" note (not a typical IBS symptom).

**Food tab** — your whole food diary, grouped by day, with search (e.g.
"pizza" or "dairy" to see every time you had it). `+` logs a meal from here
too.

**History tab** — every logged day with a one-line summary; tap to edit.

**Trends tab** — charts of worst urinary/gut symptom per day, Bristol types
against the normal band, water vs goal, plus **possible patterns**: e.g.
"gut symptoms worse on days with dairy (or the day after)", low water vs
urinary symptoms, stress and short sleep vs gut symptoms. These are simple
with/without averages, need ≥3 days on each side, and are shown as hints to
test (cut it out for 2–3 weeks), not conclusions.

**Export** (share icon on Today) — pick a date range, get a readable
doctor summary (.txt, including a day-by-day food diary) plus all data as two CSV spreadsheets. Doubles as your
backup.

**Settings** — water goal, period tracking, your own symptoms, daily
reminder notification, Face ID lock.

## Setup (Mac with Xcode)

Not built yet — it was written in a Linux sandbox without Xcode, same as
Anid. Expect possibly a small compile fix or two on first build.

1. `brew install xcodegen` (if needed)
2. `cd HealthLog && xcodegen generate`
3. Open `HealthLog/HealthLog.xcodeproj`, set your Apple ID team under
   Signing & Capabilities.
4. Run on your iPhone.

## Things to know

- **Free Apple ID signing expires after 7 days.** Re-running from Xcode
  reinstalls over the top and keeps your data. **Deleting the app deletes
  your data** — export first.
- No iCloud sync/backup of the database itself (that needs a paid developer
  account for CloudKit). Export regularly; the CSVs hold everything.
- Custom symptoms aren't counted as "urinary" or "gut" in charts and
  patterns — only in History and the export's "Other symptoms".
- Not connected to Apple Health. Could be added later (HealthKit has water,
  sleep, and menstrual data), but it isn't needed for any of the above.
- This is a tracker, not a diagnosis tool.

## Layout

```
HealthLog/
  project.yml                 # XcodeGen spec
  HealthLog/
    HealthLogApp.swift        # Entry point, tabs, Face ID lock
    Models/
      DayLog.swift            # Once-a-day numbers (water, pee count, sleep...)
      LogEvent.swift          # Timed events: symptom, poop, food, medicine, note
      Catalog.swift           # Symptom lists, red flags, Bristol scale, food tags
    Services/
      DaySummary.swift        # Per-day rollup used by History/Trends/Export
      Patterns.swift          # "Worse with X" comparisons
      Exporter.swift          # Doctor summary + CSV
      ReminderService.swift   # Daily local notification
      AppLock.swift           # Face ID / passcode
      Settings.swift          # AppStorage keys
    Views/
      TodayView.swift, DayView.swift, EventEditorView.swift, FoodDiaryView.swift,
      HistoryView.swift, TrendsView.swift, ExportView.swift, SettingsView.swift
```
