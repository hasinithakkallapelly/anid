# Anid

Quick idea capture for iPhone, with an optional Gemini-powered breakdown
step: turn a note about a reel/skill/tool you want to learn into a concrete
action list, then send selected steps to your
[Remind Me](https://github.com/hasinithakkallapelly/remind-me) app.

## How it works

- **Capture**: tap `+`, type the idea (and optionally paste a reel/article
  link), save. No network call, no waiting — this is the "quickly and
  easily" part, and it works with zero setup.
- **Break down**: open a saved idea and tap "Break This Down". This sends
  the idea's text (and link, if any) to the Gemini API, which returns a
  short summary plus 3-7 concrete action steps. Each step gets at most one
  reminder trigger, and Gemini picks which kind fits: a **due date** for
  steps with real urgency ("finish this by the weekend"), or a **place**
  for steps tied to being somewhere specific — a laptop-only step suggests
  "Room", a step needing gym equipment suggests "Gym" — matched against the
  place names you've listed in Settings. Most steps get neither and are
  just plain checklist items. You can override any of Gemini's guesses
  per-step before sending.
- **Send to Remind Me**: pick which steps to send, tap the button. Anid
  hands them to Remind Me via a `remindme://` URL — see
  [`Docs/RemindMeIntegration.md`](Docs/RemindMeIntegration.md) for what that
  needs on the Remind Me side (**not yet applied there** — read that file
  before expecting this to work end-to-end).

## Why Gemini, not Claude

Anid originally called the Claude API, but that needs a paid Anthropic
account with credits loaded — there's no free tier. Google's Gemini API has
a genuinely free tier (no credit card, no expiry, roughly 1,500 requests/day
as of writing — see [ai.google.dev](https://ai.google.dev)), which fits a
personal, low-volume app like this one far better. If that ever changes, or
you'd rather run something fully offline, two other free paths worth
knowing about:
- **Groq** (free tier, open-weight models like Llama) — similar shape to
  this integration, just a different endpoint/auth/schema.
- **Apple's on-device Foundation Models framework** — zero network calls,
  fully private, but only on Apple Intelligence-capable iPhones (15 Pro or
  newer) running iOS 26+.

## Important limitation: Anid can't see your actual saved places

Anid and Remind Me are separate apps with separate databases — Anid has no
way to read the list of places you've already saved in Remind Me (no shared
API between them). So in Anid's Settings, you list your place names once
yourself (e.g. "Room, Gym, Kitchen"), spelled exactly as they are in Remind
Me. Gemini only ever picks from that list, and Remind Me matches reminders
to real places by exact name — a typo or a place you add later in Remind Me
but forget to add here just means that step falls back to no trigger (or
you can pick a different place manually on the step itself).

## Important limitation: reels aren't read automatically

There's no public API for reading an arbitrary public Instagram reel's
caption or transcript from just a link — Instagram doesn't expose one to
third-party apps, and scraping it would be fragile and against their terms.
So pasting a reel link alone does **not** give Gemini anything to work
with. The capture screen makes this explicit: paste the link *and* write a
line or two about what the reel is about (its caption, or your own
paraphrase) — that's the actual input Gemini reasons over.

If you want this to feel more automatic later, the natural next step is a
Share Extension (share a reel from Instagram straight into Anid, capturing
whatever caption text iOS's share sheet exposes) rather than trying to
fetch reel content server-side.

## Setup (you'll need a Mac with Xcode)

This was written in a Linux sandbox with no Xcode available, so it hasn't
been built/run yet — same situation as the remind-me repo it talks to.

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) if needed:
   `brew install xcodegen`
2. From the repo root: `xcodegen generate` (creates `Anid.xcodeproj`)
3. Open `Anid.xcodeproj`, select your Apple ID under Signing & Capabilities
4. Run it on your device (Simulator works fine here — no location/geofence
   dependency like Remind Me has)
5. In the app, go to Settings and paste in a Gemini API key — get one for
   free at [aistudio.google.com](https://aistudio.google.com) → Get API
   key. No credit card, no expiry.
6. Also in Settings, type in the names of the places you've already saved
   in Remind Me (comma-separated, spelled exactly as they are there) — see
   "Anid can't see your actual saved places" above.
7. Apply the patch in `Docs/RemindMeIntegration.md` to your `remind-me`
   checkout, rebuild that app too, and install both on the same device.

## Project layout

```
Anid/
  AnidApp.swift              # App entry point, SwiftData container setup
  Models/
    Idea.swift                # SwiftData model: raw text, link, status, summary
    TodoItem.swift             # SwiftData model: step text, notes, due date/place trigger
  Services/
    GeminiService.swift        # Gemini generateContent API client (raw HTTPS, no SDK)
    KeychainService.swift      # Secure storage for the Gemini API key
    RemindMeBridge.swift       # Builds/opens the remindme:// handoff URL
  Views/
    ContentView.swift          # Idea list
    IdeaCaptureView.swift      # Fast-capture sheet
    IdeaDetailView.swift       # Breakdown + send-to-Remind-Me flow
    TodoRowView.swift          # Per-step row (select + trigger: none/time/place)
    SettingsView.swift         # API key, model choice, known Remind Me places
project.yml                    # XcodeGen spec to produce the .xcodeproj
Docs/
  RemindMeIntegration.md       # Patch to apply to the remind-me repo
```

## Known limitations / next steps

- No Share Extension yet — see "reels aren't read automatically" above.
- The Remind Me side of the integration isn't applied yet (it's a separate
  repo); Anid will report "Remind Me didn't open this link" until it is.
- No retry/offline queue if a Gemini API call fails mid-flight — just tap
  "Break This Down" again.
- No editing of a step's text after breakdown (only its due date and
  whether it's selected) — delete the idea and re-add for now if the
  wording needs to change.
