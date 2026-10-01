# Anid

Quick idea capture for iPhone, with an optional Gemini-powered breakdown
step: turn a note about a reel/skill/tool you want to learn into a concrete
action list, then send selected steps to your
[Remind Me](https://github.com/hasinithakkallapelly/remind-me) app.

## How it works

- **Capture**: tap `+`, type the idea, optionally attach the reel's actual
  video (picked from your Photos library) and/or paste a link for your own
  reference, save. No network call at this step — this is the "quickly and
  easily" part, and it works with zero setup.
- **Break down**: open a saved idea and tap "Break This Down". If a video
  is attached, Anid uploads it to the Gemini Files API and Gemini genuinely
  watches and listens to it — not just a guess from a typed caption. Either
  way, Gemini returns a short summary plus 3-7 concrete action steps. Each
  step gets at most one reminder trigger, and Gemini picks which kind fits:
  a **due date** for steps with real urgency ("finish this by the
  weekend"), or a **place** for steps tied to being somewhere specific — a
  laptop-only step suggests "Room", a step needing gym equipment suggests
  "Gym" — matched against the place names you've listed in Settings. Most
  steps get neither and are just plain checklist items. You can override
  any of Gemini's guesses per-step before sending.
- **Chat about it**: once an idea has a summary, "Chat About This Idea"
  opens a normal back-and-forth with Gemini about it — ask it to go deeper
  on a step, troubleshoot something you got stuck on, or just talk through
  the idea. The idea's text, summary, steps, and attached video (if any)
  are resent as context on every message, since the API itself has no
  memory between requests.
- **Send to Remind Me**: pick which steps to send, tap the button. Anid
  hands them to Remind Me via a `remindme://` URL — see
  [`Docs/RemindMeIntegration.md`](Docs/RemindMeIntegration.md) for what that
  needs on the Remind Me side (**not yet applied there** — read that file
  before expecting this to work end-to-end).

## Why Gemini, not Claude

Anid originally called the Claude API, but that needs a paid Anthropic
account with credits loaded — there's no free tier. Google's Gemini API has
a genuinely free tier (no credit card, no expiry), which fits a personal,
low-volume app like this one far better.

**Google's free-tier caps and model names shift more than you'd expect** —
this app already got bitten once by a model ID (`gemini-2.5-flash`) getting
retired for new API keys. `GeminiModel` in `GeminiService.swift` is where
the current model IDs live; if a request ever 404s with a "no longer
available" message, that error names the replacement model to swap in. As
of writing, `gemini-3.5-flash-lite` (the default) gets roughly 500 free
requests/day and `gemini-3.8-flash` gets roughly 20/day — check
[ai.google.dev/gemini-api/docs/pricing](https://ai.google.dev/gemini-api/docs/pricing)
for the current numbers rather than trusting this file.

If the free tier ever stops working for you, or you'd rather run something
fully offline, two other free paths worth knowing about:
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

## Important limitation: a pasted link alone still isn't content

There's no public API for reading an arbitrary public Instagram reel's
video or caption from just a link — Instagram doesn't expose one to
third-party apps, and scraping it would be fragile and against their terms.
So pasting a reel link by itself still gives Gemini nothing to work with.

What does work: save the reel to your Photos library (Instagram's own
"Save video" option on reels that allow it), then either:
- attach it in-app via the video picker on the capture screen, or
- **from the Photos app**, tap Share on that saved video → Anid. This runs
  Anid's Share Extension (`AnidShare/`), which drops you straight into a
  tiny "add a note" screen with the video already attached and saves
  directly into the same data Anid's main app reads — no need to open Anid
  first.

Either way Gemini genuinely analyzes the real video, not a paraphrase. If a
reel can't be saved (creator disabled it), typing a note about what it's
about is still a reasonable fallback, just a weaker one.

This only works sharing *from Photos*, not directly from Instagram's share
sheet on the reel itself — Instagram hands other apps a link there, not
the video file, so the save-to-Photos step can't be skipped regardless of
mechanism.

## Setup (you'll need a Mac with Xcode)

This was written in a Linux sandbox with no Xcode available, so it hasn't
been built/run yet — same situation as the remind-me repo it talks to.

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) if needed:
   `brew install xcodegen`
2. From the repo root: `xcodegen generate` (creates `Anid.xcodeproj`, with
   two targets: `Anid` and the `AnidShare` Share Extension)
3. Open `Anid.xcodeproj`. Under Signing & Capabilities, select your Apple
   ID for **both** targets — switch the target picker at the top of that
   tab from `Anid` to `AnidShare` and set the same team there too; each
   target signs independently. Xcode should auto-provision the
   `group.com.hasini.anid` App Group for both from the entitlements
   XcodeGen already generated — if it flags the App Group as missing, add
   it manually via the `+ Capability` button on whichever target complains.
4. Run the `Anid` scheme on your device (Simulator works fine here — no
   location/geofence dependency like Remind Me has)
5. In the app, go to Settings and paste in a Gemini API key — get one for
   free at [aistudio.google.com](https://aistudio.google.com) → Get API
   key. No credit card, no expiry.
6. Also in Settings, type in the names of the places you've already saved
   in Remind Me (comma-separated, spelled exactly as they are there) — see
   "Anid can't see your actual saved places" above.
7. Apply the patch in `Docs/RemindMeIntegration.md` to your `remind-me`
   checkout, rebuild that app too, and install both on the same device.
8. To test the Share Extension: save any video to Photos, open the Photos
   app, tap Share on it, and look for **Anid** in the share sheet (scroll
   the app row if it's not immediately visible — iOS sometimes buries new
   extensions under "More").

## Project layout

```
Anid/
  AnidApp.swift              # App entry point, shared SwiftData container setup
  Anid.entitlements           # App Group capability (generated by XcodeGen)
  Models/
    Idea.swift                # SwiftData model: raw text, link, video ref, status, summary
    TodoItem.swift             # SwiftData model: step text, notes, due date/place trigger
    ChatMessage.swift          # SwiftData model: one chat turn (role, text)
  Services/
    GeminiService.swift        # Gemini generateContent API client (breakdown + chat, raw HTTPS)
    GeminiFilesService.swift   # Gemini Files API client (resumable video upload)
    SharedModelContainer.swift # ModelContainer backed by the shared App Group, used by both targets
    VideoStorage.swift         # Persists a video into the shared App Group container
    KeychainService.swift      # Secure storage for the Gemini API key
    RemindMeBridge.swift       # Builds/opens the remindme:// handoff URL
  Views/
    ContentView.swift          # Idea list
    IdeaCaptureView.swift      # Fast-capture sheet (text, video picker, link)
    IdeaDetailView.swift       # Breakdown + chat entry point + send-to-Remind-Me flow
    IdeaChatView.swift         # Per-idea chat thread
    TodoRowView.swift          # Per-step row (select + trigger: none/time/place)
    SettingsView.swift         # API key, model choice, known Remind Me places
AnidShare/                     # Share Extension target: Photos → Anid
  ShareViewController.swift    # Extension entry point; pulls the shared video, saves the Idea
  ShareComposeView.swift       # The tiny "add a note" screen the extension shows
  AnidShare.entitlements       # App Group capability (generated by XcodeGen)
project.yml                    # XcodeGen spec to produce the .xcodeproj (both targets)
Docs/
  RemindMeIntegration.md       # Patch to apply to the remind-me repo
```

## Known limitations / next steps

- The Share Extension and its App Group storage are untested on an actual
  device (no Mac/Xcode in the environment this was written in) — the main
  risk spot is Xcode auto-provisioning the `group.com.hasini.anid` App
  Group correctly for both targets on a free personal team; see step 3 in
  Setup if it doesn't.
- Attaching a video still means a manual save-to-Photos step first either
  way — see "a pasted link alone still isn't content" above.
- The Remind Me side of the integration isn't applied yet (it's a separate
  repo); Anid will report "Remind Me didn't open this link" until it is.
- No retry/offline queue if a Gemini API call fails mid-flight — just tap
  "Break This Down" (or resend the chat message) again.
- No editing of a step's text after breakdown (only its due date/place
  trigger and whether it's selected) — delete the idea and re-add for now
  if the wording needs to change.
- A chat conversation that continues more than 48 hours after the video
  was uploaded will try to re-upload it automatically (Gemini Files API
  uploads expire after 48 hours) — this should be transparent, but hasn't
  been tested against an actual 48-hour-old upload.
- Large videos take real time to upload before "Break This Down" or a chat
  reply comes back — there's a distinct "Uploading video..." state, but no
  progress percentage, just a spinner.
