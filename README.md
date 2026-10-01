# Anid

For saving reels you'd otherwise never get back to: Anid turns a saved reel
into a learning plan aimed at what you're actually working toward — what
you need to know first, then detailed steps — and helps you follow through,
with a chat for getting unstuck and reminders sent to your
[Remind Me](https://github.com/hasinithakkallapelly/remind-me) app.

## How it works

- **Capture**: tap `+`, type the idea, optionally attach the reel's actual
  video (picked from your Photos library) and/or paste a link for your own
  reference, save. No network call at this step — this is the "quickly and
  easily" part, and it works with zero setup.
- **Goals** (second tab): add what you're working toward — "Learn guitar",
  "Ship an iOS app" — with optional details like your current level or a
  deadline. Link reels to a goal when saving them (or later, from the
  reel's page, or by adding a reel straight from the goal's page). Each
  goal shows every reel saved toward it.
- **Break down**: open a saved idea and tap "Break This Down". If a video
  is attached, Anid uploads it to the Gemini Files API and Gemini genuinely
  watches and listens to it. Gemini acts as a learning coach rather than
  summarizing, and returns:
  - **What this reel teaches** — a short summary.
  - **Why it helps** — how the reel moves you toward the linked goal (or a
    plain "it's only loosely related" when that's the truth).
  - **Before you start** — the prerequisites the reel quietly assumes:
    knowledge, skills, tools, accounts. Reels skip the foundations; this
    surfaces them.
  - **Your plan** — 4-10 numbered steps in learning-path order: close
    prerequisite gaps, do the core of the reel, practice it on something
    real, check the result, extend toward the goal. Each step has several
    sentences of real detail — exactly what to do, why, how you'll know
    it's done, and a common mistake — so you can follow it without
    rewatching the reel.
  - Each step can carry one reminder trigger: a **time** for real
    deadlines, or a **place** (e.g. a laptop step → "Room") matched against
    the Remind Me place names in Settings. Most steps get neither; override
    any of Gemini's choices per step.
- **Regenerate Plan**: redo the breakdown — e.g. after linking a goal, or
  for ideas broken down before the plan got more detailed. The old plan is
  only replaced once the new one arrives.
- **Get help with these steps**: a chat that already knows the reel, your
  goal, the prerequisites, and the plan — ask it to explain a step for a
  beginner, teach a prerequisite you're missing, or what to do next. All of
  that context (plus the video, if attached) is resent on every message,
  since the API itself has no memory between requests.
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
    Idea.swift                # SwiftData model: note, link, video ref, goal, summary, prerequisites
    Goal.swift                 # SwiftData model: what the user is working toward
    TodoItem.swift             # SwiftData model: step title, detail, due date/place trigger
    ChatMessage.swift          # SwiftData model: one chat turn (role, text)
  Services/
    GeminiService.swift        # Gemini generateContent API client (breakdown + chat, raw HTTPS)
    GeminiFilesService.swift   # Gemini Files API client (resumable video upload)
    SharedModelContainer.swift # ModelContainer backed by the shared App Group, used by both targets
    VideoStorage.swift         # Persists a video into the shared App Group container
    KeychainService.swift      # Secure storage for the Gemini API key
    RemindMeBridge.swift       # Builds/opens the remindme:// handoff URL
  Views/
    ContentView.swift          # Tab bar (Ideas, Goals) + idea list
    IdeaCaptureView.swift      # Fast-capture sheet (note, video picker, goal, link)
    IdeaDetailView.swift       # Learning plan, chat entry point, regenerate, send-to-Remind-Me
    IdeaChatView.swift         # Per-idea coaching chat
    TodoRowView.swift          # Numbered, detailed step + reminder menu
    GoalsListView.swift        # Goals tab
    GoalDetailView.swift       # One goal and the reels saved toward it
    GoalEditView.swift         # Create/edit a goal
    GoalPicker.swift           # Goal picker shared by capture, detail, and the Share Extension
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
- If Anid is already open in the background when you share a reel from
  Photos, the new idea may not appear until you close and reopen Anid —
  SwiftData doesn't reliably pick up writes from an extension into an
  already-running app on iOS 17.
- No goal-level chat or roadmap across all of a goal's reels yet — chat is
  per reel. A goal-wide "what should I do next across everything I've
  saved" view would be the natural next step.
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
