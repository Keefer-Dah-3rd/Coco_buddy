# Mac App Store checklist

Everything needed to get Desktop Buddy onto the Mac App Store, in order. Items marked **✓ done** were checked against the project on 2026-10-17 (a Release build, its entitlements and its Info.plist). Rules quoted are from Apple's [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) and [upcoming requirements](https://developer.apple.com/news/upcoming-requirements/); re-check both before submitting, since they change.

## 1. Blockers: fix in the app first

These would likely get the app rejected or make it unusable for people who download it.

- [x] **✓ done (2026-10-19)** **Ask before anything goes to Claude (Guideline 5.1.2(i)).** Since November 2025 Apple requires you to "clearly disclose where personal data will be shared with third parties, including with third-party AI, and obtain explicit permission before doing so". The app explains this in Connections and Settings, but there's no explicit yes/no. The Chat tab now shows **Before you chat** before anything is sent. It lists what's sent with every message, what's sent only when Coco needs it, and what's never sent; names Anthropic and links to its privacy policy; and offers **Allow** / **Not now**. The chat service itself refuses to send until you allow it, so no screen or shortcut can skip the step. You can turn it off in Settings › Privacy & data, which stops the chat and forgets the conversation. Delete all my data resets it, and raising `AIConsent.version` asks everyone again. The wording lives in `DesktopBuddy/App/AIConsent.swift`. **Still to do:** make the privacy policy say the same thing (section 4). Apps have been rejected for relying on a privacy policy alone.
- [ ] **Google Calendar can't ask users to create a Google Cloud project.** Today each user pastes their own OAuth client ID. For the store you need one of these:
  - **Ship your own OAuth client** (iOS type, your bundle ID) and get it **verified by Google**. The Calendar scopes are *sensitive*, and verification takes weeks: you need a privacy policy, a homepage on a verified domain, a written justification for each scope and usually a demo video. Until it's verified, users see an "unverified app" screen. In *Testing* mode, sign-ins expire after 7 days and only listed test users can connect.
  - **Or leave direct Google out of v1.** People can add their Google account to the macOS Calendar app and Coco reads it through Apple Calendar. Coco just can't add or change events then.
- [ ] **Notion is back on** (`Features.notion = true`, re-enabled 2026-10-17). It can ship as it is, but it needs its own test material and wording; see [section 9](#9-notion).
- [ ] **Info.plist additions** (set in the target's build settings; the Info.plist is generated):
  - [ ] `ITSAppUsesNonExemptEncryption = NO`. The app only uses Apple's HTTPS, which is exempt, so App Store Connect stops asking about export compliance on every build.
  - [ ] `NSHumanReadableCopyright`: it's currently empty. Use e.g. "© 2026 Your Name".
  - [ ] `MARKETING_VERSION` 0.1 → **1.0**. Keep `CURRENT_PROJECT_VERSION` at 1, then raise it for every upload.
- [ ] **Likely reviewer ask for AI chat (Guidelines 1.2 / 4.7).** Apps with AI-generated content are expected to filter objectionable material, offer a way to report content and publish contact details. Claude's own safety filtering covers the first part. Consider adding "Report this reply" (a mailto: or a form) under chat replies, plus a support email, before the reviewer asks.
- [ ] **Confirm you own the bark sounds** (`DesktopBuddy/Resources/Sounds/coco-bark-*.wav`). App Store Connect asks about content rights.

## 2. Already in good shape

- [x] **✓ done** App Sandbox is on. Entitlements are only `app-sandbox`, `network.client`, `device.audio-input` and `personal-information.calendars`, with no temporary exceptions (2.4.5(i)).
- [x] **✓ done** Usage descriptions exist for the microphone, speech recognition and calendars (full access).
- [x] **✓ done** A privacy manifest (`PrivacyInfo.xcprivacy`) is bundled: no tracking, UserDefaults reason CA92.1, collected data limited to "other user content" for app functionality. No other required-reason APIs were found in the code.
- [x] **✓ done** The app icon set is complete, 16 pt to 1024 px.
- [x] **✓ done** The Release build compiles. The self-tests, snapshot tools and design experiments are compiled out (`#if DEBUG`): none of their flags are in the release binary.
- [x] **✓ done** Open at login is off until the user turns it on in Settings, via `SMAppService` (2.4.5(iii)).
- [x] **✓ done** It has no Dock icon (`LSUIElement`), and Quit is in both of Coco's menus. There's no auto-updater (2.4.5(vii)), no downloaded code and no root access.
- [x] **✓ done** The held-key tricks (Right ⌥ / ⌘ / ⇧) work in a sandboxed build without Accessibility or Input Monitoring (commit d8bbd97). Re-check this in the TestFlight build (step 5).

## 3. Apple Developer account

- [ ] Join the **Apple Developer Program** (US$99/year, or the local equivalent). The free Personal Team (`7VXB4ZWKC7`) can't distribute on the store.
- [ ] Accept the agreements in App Store Connect. For a paid app: the **Paid Apps agreement**, tax forms and banking.
- [ ] **EU trader status (DSA).** Required to be on the store in the EU. You declare whether you're a trader, and traders must show an address, phone and email on the listing. The alternative is to leave the EU out under Availability.
- [ ] Register the **bundle ID** `com.keefer.DesktopBuddy` (or pick the final one now: it can't change after release) under Certificates, Identifiers & Profiles.
- [ ] In Xcode, set the target's team to the paid team (Signing & Capabilities, Automatic signing). Xcode creates the Apple Distribution certificate and App Store profile when you archive.
- [ ] Create the app record in App Store Connect: New App, platform macOS, name, primary language, bundle ID, SKU.

## 4. Pages you need on the web

- [x] **✓ drafted (2026-10-19)** The **privacy policy** is written: [docs/privacy/index.html](privacy/index.html). To finish it:
  - [ ] Replace `[Developer name]` and `[contact email]` (3 places).
  - [ ] Publish it: GitHub › Coco_buddy › Settings › Pages › Deploy from a branch › `main`, folder `/docs`. The URL will be `https://keefer-dah-3rd.github.io/Coco_buddy/privacy/`; paste it into App Store Connect › App Privacy.
  - [ ] Re-read it whenever the app starts sending something new (and raise `AIConsent.version`).

  What it covers:
  - **Stays on the Mac:** tasks, focus history and settings, plus the Partiful calendar cache.
  - **Keychain:** the Claude API key, the Google sign-in and the Partiful calendar link.
  - **Sent to Anthropic, and only when the user chats:** messages, plus the tasks, calendar days and invitation details Coco looks up.
  - **Google Calendar:** what's read, and what's written only after the user confirms.
  - **Apple Calendar:** read on this Mac only.
  - **Partiful:** the pages and calendar link the user provides.
  - **Notion:** the token is in the Keychain. Coco reads the chosen task database and changes a task's status only when the user confirms. Tasks picked from Notion are ordinary tasks after that, so they're included when the chat looks up your day.
  - **Speech:** handled by Apple, on device when supported.
  - **No analytics or tracking.**
  - **How to delete everything:** Settings › Delete all my data.
  - **A contact email.**
- [ ] **Support URL** (required): a page with a contact email or form. The README's Privacy section is a good start.
- [ ] Marketing URL (optional).
- [ ] If you ship your own Google OAuth client: a homepage on a domain you've verified in Google Search Console, plus the privacy policy on that same domain.

## 5. Build, upload and test the real thing

- [ ] Use the current Xcode release. Apple's latest minimum (April 28, 2026: Xcode 26) names iOS, iPadOS, tvOS, visionOS and watchOS but not macOS; build with the latest anyway.
- [ ] Product › Archive, then in the Organizer: **Validate App**, then **Distribute App › App Store Connect**. If you ever upload a build that wasn't made by Xcode, strip `com.apple.quarantine` first (required since February 2025).
- [ ] Install the build from **TestFlight for Mac** and test that copy, not a debug build. That way sandboxing and App Store signing are exactly what users get:
  - [ ] First launch: the welcome appears, and Coco appears and follows the cursor.
  - [ ] Right ⌥ + click (call), Right ⌘ + click (fetch), Right ⇧ + click (treat), all with no permission prompts.
  - [ ] ⌃⌥C opens the panel from another app.
  - [ ] The microphone and speech prompts appear with the right wording, and voice tasks work.
  - [ ] The Apple Calendar prompt works and events appear.
  - [ ] Google sign-in opens and returns to the app (with the client you're shipping).
  - [ ] Chat works with a key; quit and reopen, and the key and sign-ins are still there (Keychain).
  - [ ] A Partiful invite link in chat, and the Partiful calendar import.
  - [ ] Open at login: on, log out and back in, Coco is there; off, she isn't.
  - [ ] Notifications for the focus timer and meeting reminders.
  - [ ] Settings › Delete all my data clears everything.
  - [ ] Launching a second copy hands over to the running one.
  - [ ] Run docs/QA_CHECKLIST.md on this build.

## 6. App Store Connect listing

- [ ] **Name** (30 characters max), e.g. "Desktop Buddy: Coco". Check it isn't taken.
- [ ] **Subtitle** (30 max), e.g. "A corgi who plans your day".
- [ ] **Description**: say clearly that the chat needs your own Anthropic API key and that usage is billed by Anthropic. Say which features work without it (Coco, tasks, focus timer, voice, calendars).
- [ ] **Keywords** (100 characters, comma-separated): e.g. desktop pet, focus timer, pomodoro, planner, corgi, calendar.
- [ ] Promotional text (optional, can change any time) and copyright.
- [ ] **Category**: Productivity (already in the app). A secondary category is optional, e.g. Lifestyle.
- [ ] **Screenshots**: 1 to 10, **16:10** only, at 1280×800, 1440×900, 2560×1600 or 2880×1800. Show Coco on a real desktop, the Today panel, Focus, the chat (with a sample conversation), the week with calendars, and fetch. `--snapshots` renders the panels if you want clean images to composite.
- [ ] App preview video (optional, up to 30 s). docs/DEMO_SCRIPT.md is already a shot list.
- [ ] **Age rating questionnaire**. It's newer and covers capabilities as well as content. Answer the question about AI assistants / chatbots honestly. Coco can generate free text, which may raise the rating.
- [ ] **App Privacy labels** (App Store Connect › App Privacy). Match them to the privacy manifest: no tracking; "Other User Content", linked to the user, for app functionality. Decide whether calendar details sent to Anthropic count as collected (Apple's definition is data that leaves the device and is kept longer than needed to serve the request). When unsure, declare it.
- [ ] **Content rights**: "Yes, it accesses third-party content", meaning the user's own Google, Apple, Partiful and Notion data. Confirm you have the rights to everything bundled (barks, art).
- [ ] **Export compliance**: "uses only exempt encryption (HTTPS)". Skipped automatically once `ITSAppUsesNonExemptEncryption` is set.
- [ ] **Pricing and availability**: free or a price, which countries, and the EU decision from step 3.
- [ ] Choose a release option: manual (recommended for v1) or automatic after approval.

## 7. Notes for App Review

App Review can't guess how a dock-less floating corgi works. Put this in **App Review Information**:

- [ ] Contact name, phone and email.
- [ ] **How to use it:** "Desktop Buddy has no Dock icon. Coco appears on the desktop after launch. Click her for the panel, or press ⌃⌥C. Right-click her for the menu, which includes Quit."
- [ ] **Hidden features:** "Hold the right-hand Option key and click to call her over; Right Command + click throws a ball; Right Shift + click tosses a treat. No permissions are needed."
- [ ] **A Claude API key for testing**, from an Anthropic account you control with a low spending limit. Rotate it after review. Without one, reviewers can't see the chat.
- [ ] **Google:** either a test Google account (if you ship your own verified client) or "Google Calendar is optional; Apple Calendar shows the same events".
- [ ] **Partiful:** "Paste any public partiful.com/e/… link into the chat to see an invitation read." Include a link that works. If the calendar import ships, include a calendar link from a test Partiful account.
- [ ] **Notion:** a test token and a shared task database; see [section 9](#9-notion) for what to set up and what to write.
- [ ] **AI consent:** "The first time you open the Chat tab, 'Before you chat' lists what's sent to Anthropic. Nothing is sent until you choose Allow. It can be turned off in Settings › Privacy & data."

## 8. After you submit

- [ ] Watch for App Review messages in App Store Connect and answer in the Resolution Center. Rejections usually come with a guideline number; fix it or explain, then resubmit.
- [ ] Once approved: release, then check the live listing, the screenshots and that the download installs.
- [ ] Updates go through the Mac App Store only (2.4.5(vii)). Raise the build number every upload and the version for every release.
- [ ] Keep the privacy policy and the App Privacy labels in step with features. The Apple Calendar and Partiful import are recent, so re-read both before each submission.

## 9. Notion

Notion's own guidance is a public OAuth integration for an app many people install. But Notion's OAuth needs a **client secret** for every token exchange and refresh, and a Mac app can't keep that secret. So Desktop Buddy asks for a token instead: an **internal integration** secret, or a **personal access token**. That's fine for the App Store; it just needs clear steps and its own test material.

### For version 1 (paste-a-token, no server)

Already in the app:
- [x] **✓ done** The token is checked with Notion before it's saved, and kept in the Keychain.
- [x] **✓ done** Connections › Notion has setup steps.
- [x] **✓ done** A revoked or expired token turns into "needs reconnect" instead of failing silently.
- [x] **✓ done** Delete all my data forgets the Notion token and mapping.
- [x] **✓ done** Nothing joins today's plan from Notion until you pick it, and a task is marked done in Notion only if you turned that on and confirm each time.

To do:
- [ ] **Check the in-app steps against Notion's current screens**, since Notion renames things. Today they are:
  1. Go to notion.so › Settings › Connections (or *Integrations*) › **Develop or manage integrations**, then create an **internal** integration with *Read content*, plus *Update content* if Coco should mark tasks done.
  2. Copy its secret into Coco.
  3. In Notion, open the task database › **•••** › **Connections** › add the integration.
- [ ] **Explain the two kinds of token in one line each.** An internal integration sees only the databases you share with it, which is least access and recommended. A personal access token sees everything you can see, **expires** after 7 days to 1 year (one year by default), and on Free and Business plans may be limited to workspace owners. Say that when a token expires, Coco asks you to reconnect.
- [ ] **Cover the people who can't make a token.** Members of a workspace someone else owns may not be allowed to create integrations or tokens. Make sure the error text says to ask the workspace owner, or to use a personal workspace.
- [x] **✓ done** The AI consent screen names tasks picked from Notion.
- [ ] **Listing wording:** say "works with Notion". Don't use Notion's logo or suggest Notion made or endorses the app.
- [ ] **TestFlight check** (section 5):
  - [ ] Connect with an internal-integration secret.
  - [ ] Pick the database and map its fields.
  - [ ] Pick tasks for today.
  - [ ] Mark one done and confirm it changes in Notion.
  - [ ] Revoke the integration in Notion and confirm Coco shows *needs reconnect*.
  - [ ] Disconnect.

### What App Review needs for Notion

Reviewers won't create a Notion account or an integration themselves.

- [ ] Make a **separate Notion workspace for review**, not your real one.
- [ ] Add a small task database, with:
  - **Name** (title)
  - **Status**, with *To do*, *In progress* and *Done*
  - **Due** (date)
  - **Priority** (select)
  - about 5 tasks, some due today
- [ ] Create an **internal integration** with Read + Update content, and share the database with it.
- [ ] In the review notes, include:
  - the secret;
  - "In Connections › Notion, paste this token, choose 'Review tasks', and accept the suggested fields. Open the panel › Notion › Pick to add tasks to today. Marking one done asks whether to update Notion."
- [ ] After approval, **revoke that secret**, and make a new one for each later submission.

### Later: one-click "Connect Notion" (needs a small server)

Only if pasting a token turns out to be too much friction:
- [ ] Create a **public** integration. Its installation scope is either *Any workspace* or *Selected workspaces only*, and it can't be changed later. Only *Any workspace* can be listed in Notion's Marketplace.
- [ ] Set its redirect URI. Fill in the website, privacy policy, terms of use and support email that Notion shows on its sign-in screen.
- [ ] Run a **small token server**, e.g. a serverless function, that holds the client secret. It exchanges the sign-in code and refreshes tokens; Notion **rotates** refresh tokens, so always keep the newest. The app keeps only its own tokens, in the Keychain, never the secret.
- [ ] Optional: list it in the Notion Marketplace, which requires passing Notion's **security review**.
- [ ] Update the privacy policy and the App Privacy labels: data now passes through your server.
- [ ] Ship it in an app update; the token paste can stay as an "advanced" option.

## Sources

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/): 2.1 (complete builds, demo accounts), 2.4.5 (Mac App Store rules), 1.2 and 4.7 (AI content), 5.1.2(i) (third-party AI consent)
- [Upcoming requirements](https://developer.apple.com/news/upcoming-requirements/): privacy manifests, the age rating questionnaire, the quarantine attribute, the Xcode 26 minimum, EU trader status
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications)
- [TechCrunch on the November 2025 AI data rule](https://techcrunch.com/2025/11/13/apples-new-app-review-guidelines-clamp-down-on-apps-sharing-personal-data-with-third-party-ai)
- [9to5Mac on the new age ratings](https://9to5mac.com/2025/07/24/apple-notifies-developers-of-new-app-store-age-rating-system/)
- [Google OAuth testing-mode token expiry](https://newscrewdriver.com/2023/02/04/google-oauth-test-tokens-expire-weekly/)
- [Notion authorization](https://developers.notion.com/docs/authorization): public OAuth uses the client secret for the token exchange; refresh tokens rotate; installation scope can't change after creation
- [Notion personal access tokens](https://developers.notion.com/guides/get-started/personal-access-tokens): expiry choices, owner-only creation on some plans
- [Notion: refresh a token](https://developers.notion.com/reference/refresh-a-token)
