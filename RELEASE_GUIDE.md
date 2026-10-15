# From this repository to the App Store — step by step

Everything that can be done without your Apple account and devices is done. What is left
needs **you**: a Mac, your Apple ID, your iPhone and Apple Watch. Follow the steps in
order. Text in `code boxes` is exactly what to type or paste.

Time needed: about 1 hour for steps 1–5 (running on your devices), plus 1–2 hours for
steps 6–9 (App Store), plus Apple's review (usually 1–2 days).

---

## What you need

| Thing | Notes |
| --- | --- |
| A Mac | With the latest macOS your Mac supports (macOS 15 Sequoia or newer). |
| Xcode | Free in the Mac App Store. CI builds this project with **Xcode 26**; install the newest version. |
| iPhone | iOS 17 or newer. Live Activities need an iPhone with iOS 17+. |
| Apple Watch | watchOS 10 or newer, paired with the iPhone. |
| Apple Developer Program | **Required** (99 USD/year): the watch complication uses an App Group, which free accounts can't sign, and you need it for TestFlight and the App Store. Enrol at <https://developer.apple.com/programs/enroll/> with your Apple ID. Approval can take up to 48 hours — start this first. |

---

## Step 1 — Merge the work into `main` (2 minutes, on github.com)

1. Open <https://github.com/Wrexist/PadelOS/compare/main...claude/padel-mvp>
2. Click **Create pull request**. Title: `PadelOS 1.0`. Click **Create pull request** again.
3. Wait until the checks are green (about 40 minutes), then click **Merge pull request** →
   **Confirm merge**.

The privacy policy and support links used in step 8 point to `main`, so do this first.

## Step 2 — Get the code on your Mac (5 minutes)

Open **Terminal** (⌘-Space, type `Terminal`, Enter) and paste these lines one at a time:

```sh
cd ~/Desktop
git clone https://github.com/Wrexist/PadelOS.git
cd PadelOS
open PadelOS.xcodeproj
```

If macOS asks to install the command line developer tools, click **Install**, wait, and
run the lines again. Xcode opens the project and downloads nothing else (there are no
third-party dependencies).

## Step 3 — Sign in to Xcode and choose your app ID (5 minutes)

**3a. Add your Apple ID to Xcode.** Xcode menu → **Settings…** → **Accounts** → **+** →
**Apple ID** → sign in. Your team appears (your name, "(Personal Team)" until your
Developer Program membership is active — wait for the membership before continuing).

**3b. Choose a unique app ID.** Bundle IDs are global, so pick one with your own name in
it, for example `com.yourname.padelos` (lowercase letters, digits, dots and hyphens only).

1. In Xcode's left sidebar, click the blue **PadelOS** icon at the very top.
2. In the middle pane, under **PROJECT** (not TARGETS), click **PadelOS**.
3. Click the **Build Settings** tab, then **All** and **Combined** at the top.
4. In the search field (top right of that pane) type `PADEL_BUNDLE_ID`.
5. Double-click the value `app.padelos.PadelOS` and type your ID, e.g.:

```
com.yourname.padelos
```

Every other identifier (watch app, widgets, App Group) is derived from this one setting
automatically.

**3c. Set your team on the four targets.** Under **TARGETS**, click each of these in turn:
`PadelOS`, `PadelOSWidgets`, `PadelOSWatch`, `PadelOSWatchWidgets`. For each:

1. Click the **Signing & Capabilities** tab.
2. Tick **Automatically manage signing**.
3. **Team** → choose your team (your name, *not* "Personal Team").

Xcode registers the app IDs and the App Group for you. A red error that mentions the App
Group usually disappears when you click **Try Again**; if it stays, see *Problems* below.

## Step 4 — Run on your iPhone and Apple Watch (10 minutes)

1. **Developer Mode on the iPhone:** connect the iPhone with a cable. On the iPhone:
   Settings → Privacy & Security → **Developer Mode** → On → Restart → confirm.
   (The option appears after the iPhone has been connected to Xcode once.)
2. **Developer Mode on the watch:** on the watch: Settings → Privacy & Security →
   **Developer Mode** → On → Restart.
3. In Xcode's top bar, choose the scheme **PadelOS** and your **iPhone** as the
   destination. Press **▶︎** (or ⌘R).
4. The first time, if the iPhone says *Untrusted Developer*: Settings → General →
   **VPN & Device Management** → your Apple ID → **Trust**. Press ▶︎ again.
5. The watch app installs together with the iPhone app. If it doesn't appear after a
   minute: open the **Watch** app on the iPhone → My Watch → scroll to **PadelOS** →
   **Install**. To run it directly from Xcode instead: scheme **PadelOSWatch**,
   destination your watch, ▶︎.

## Step 5 — Test on the real devices (30 minutes)

These are the things simulators can't prove. Tick them off:

1. Create a tournament on the iPhone → it appears on the watch within a few seconds.
2. Score points on the watch with the iPhone nearby → the iPhone updates live.
3. Put the watch in Airplane Mode, score 10 points, undo one, force-quit the watch app and
   open it again → the score is still there and it shows changes waiting to sync.
4. Turn Airplane Mode off → the waiting count goes to zero and the iPhone shows the same
   score.
5. Lock the iPhone while a match is open → the score is on the Lock Screen. Tap **+1 A**
   and **undo** there → the score changes without unlocking.
6. Add the PadelOS complication to a watch face (long-press the face → Edit →
   Complications) → it shows the active court and score.
7. Optional (Ultra): Shortcuts app → new shortcut → **Open Active Match** → assign it to
   the Action button (Watch Settings → Action Button → Shortcut).
8. Switch the iPhone language (Settings → Apps → PadelOS → Language) to Spanish and to
   Arabic and walk through create → score → standings.

If something fails, write down what you did and what happened, and send it to me — I'll
fix it.

## Step 6 — Create the app in App Store Connect (10 minutes)

1. Open <https://appstoreconnect.apple.com> → **Apps** → **+** → **New App**.
2. Fill in exactly:

| Field | What to enter |
| --- | --- |
| Platforms | ☑︎ iOS |
| Name | `PadelOS: Padel Tournaments` (if taken: `PadelOS – Americano & Mexicano`) |
| Primary Language | English (U.S.) |
| Bundle ID | Choose the one from step 3b (Xcode registered it when you ran the app) |
| SKU | `padelos-ios-1` |
| User Access | Full Access |

The Apple Watch app is part of the iPhone app — there is no separate watch record.

## Step 7 — Upload a build (15 minutes)

1. In Xcode's top bar, set the destination to **Any iOS Device (arm64)** (scheme
   **PadelOS**).
2. Menu **Product → Archive**. Wait for the Organizer window.
3. Select the new archive → **Distribute App** → **App Store Connect** → **Distribute**
   (keep the defaults: automatic signing, upload symbols). Wait for *Uploaded*.
4. After 10–30 minutes the build appears in App Store Connect → your app → **TestFlight**.
   Export compliance is already answered by the app (no encryption beyond Apple's).
5. **TestFlight on your phone:** TestFlight tab → **Internal Testing** → **+** → group name
   `Me` → add yourself → install the **TestFlight** app on the iPhone and accept the
   invite. Run a quick round of step 5 on this build.

**Every new upload needs a higher build number:** project → Build Settings → search
`CURRENT_PROJECT_VERSION` → change `1` to `2` (then `3`, …). The version shown to users is
`MARKETING_VERSION` (`1.0.0`).

## Step 8 — Fill in the App Store page (30 minutes)

In App Store Connect → your app → **Distribution** tab → **iOS App 1.0 Prepare for
Submission**. Paste these:

**Promotional Text**

```
Run Americano, Mexicano and team tournaments in a minute. Score from your Apple Watch, follow live standings and finish with playoffs.
```

**Description**

```
Run padel tournaments with friends in under a minute — and keep score from your wrist.

PadelOS creates fair schedules, keeps the score and updates the standings while you play. No account, no ads, no internet needed.

FORMATS
• Americano – rotating partners, individual ranking
• Mexicano – every round paired from the latest standings
• Mixed Americano and Mixicano – one player from each group in every team
• Team Americano, Team Mexicano and Swiss – fixed pairs
• King of the Court – winners move up a court, losers move down
• Optional final round or knockout playoffs (final, semifinals or quarterfinals) with a live bracket

SCORE YOUR WAY
• Points to a fixed total, such as 24 or 32
• Timed matches
• Games and sets: 15-30-40, golden point or advantage, tie-breaks and super tie-break

APPLE WATCH
• One tap per point, undo with a tap
• Keeps scoring when your iPhone stays in the bag — points sync when you are back in range
• Designed for Apple Watch Ultra, with a complication for the active court

LOCK SCREEN AND DYNAMIC ISLAND
• Follow the live score and add points without unlocking your iPhone

FAIR AND FLEXIBLE
• Balanced partners, opponents and rests
• Add late arrivals or withdraw players without touching rounds already played
• Correct any result — the standings update instantly
• Share the final table with the group

PRIVATE BY DESIGN
• No account, no ads, no tracking
• Everything stays on your iPhone and Apple Watch

Available in 19 languages.
```

**Keywords**

```
padel,americano,mexicano,tournament,scorer,scoreboard,league,bracket,playoffs,mixicano,rotation
```

**Support URL**

```
https://github.com/Wrexist/PadelOS/blob/main/SUPPORT.md
```

**Marketing URL** — leave empty.

**Version** `1.0` · **Copyright** — `2026 ` followed by your full name, e.g.
`2026 Your Name`.

**Screenshots** — drag in:

- *iPhone 6.9" Display*: the PNG files in `docs/app-store/iphone/` (in this order:
  `1`, `2`, `3`, `4`, `5`).
- *Apple Watch*: the PNG files in `docs/app-store/watch/`.

(Smaller iPhone sizes are generated automatically from the 6.9" set.)

**Build** — click **Add Build** and choose the build from step 7.

**App Review Information**

- Sign-in required: **No** (untick).
- Contact: your name, phone number and email (only Apple sees these).
- Notes:

```
PadelOS works fully offline and has no login or in-app purchases.

How to review:
1. Launch the app and swipe through the introduction (or tap Skip).
2. Tap "Create Tournament", tap "Add Players", type four names (press Return after each), tap Continue, then "Start Tournament".
3. On a court, tap "Start Scoring" and tap "+1" under a team to add a point; "Undo" removes the last point.
4. Apple Watch: with a paired watch, the tournament appears in PadelOS on the watch; tap a court and tap a side to score.
5. While a match is being scored, leave the app: the score is shown as a Live Activity on the Lock Screen and in the Dynamic Island.

No data is collected and nothing is sent to any server.
```

**App Information** (left sidebar, under *General*):

| Field | What to choose |
| --- | --- |
| Subtitle | `Americano & Mexicano scoring` |
| Category | Primary: **Sports**. Secondary: **Utilities** |
| Content Rights | "Does your app contain, show, or access third-party content?" → **No** |
| Age Rating | Click **Set Up Age Rating**, answer **None / No** to every question → result **4+** |
| Privacy Policy URL (under *App Privacy*) | `https://github.com/Wrexist/PadelOS/blob/main/PRIVACY.md` |

**App Privacy** (left sidebar): **Get Started** → "Do you or your third-party partners
collect data from this app?" → **No, we do not collect data from this app** → **Save** →
**Publish**.

**Pricing and Availability** (left sidebar): Price **Free (0.00)**; Availability **all
countries or regions**.

## Step 9 — Submit (2 minutes)

Back on the **iOS App 1.0** page: **Add for Review** → **Submit to App Review**. Apple
usually answers within 1–2 days by email. If they reject something, paste their message to
me and I'll tell you exactly what to change.

---

## Problems you might see

| Message | What to do |
| --- | --- |
| *Failed to register bundle identifier* / *is not available* | The ID is taken. Change `PADEL_BUNDLE_ID` (step 3b) to something more unique, e.g. add your surname. |
| *Personal development teams … do not support the App Groups capability* | Your Developer Program membership isn't active yet. Wait for Apple's confirmation email, then choose the paid team in step 3c. |
| *No profiles for '…' were found* | Signing & Capabilities → untick and tick **Automatically manage signing** again, then ▶︎. |
| *Developer Mode disabled* / *Could not launch* | Step 4.1 / 4.2. |
| *Untrusted Developer* | Step 4.4. |
| The watch app doesn't install | Watch app on iPhone → My Watch → PadelOS → **Install**; keep the watch on its charger and unlocked. |
| Upload: *The bundle version must be higher …* | Increase `CURRENT_PROJECT_VERSION` (step 7) and archive again. |
| Anything else | Copy the full error text and send it to me. |

## What I can still do for you

- Fix anything you find in step 5 or anything App Review rejects.
- Translate the App Store description and keywords into the other 18 languages
  (App Store Connect → the language menu next to the version → add localization).
- Create the pull request in step 1 for you — just ask.
