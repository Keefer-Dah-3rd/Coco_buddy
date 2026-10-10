# Integration setup checklist (Phases 3–4)

Nothing here is needed for Phase 1 or 2. Each integration stays **disconnected** until it's genuinely configured — the app never shows a connection it doesn't have.

## Code signing (done — one click left)

The target signs automatically with **John Keefe (Personal Team)** (`DEVELOPMENT_TEAM = 7VXB4ZWKC7`). Stable signing keeps microphone/speech permissions and Keychain items attached to the app across rebuilds.

- [ ] Xcode › Settings › Accounts → select the Apple ID → sign in again if prompted (the command line couldn't reuse the saved session). The first ⌘R then creates the "Apple Development" certificate.
- [ ] When Phase 3 starts: add the **Outgoing Connections (Client)** capability (`ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES`). Today the app deliberately has no network access.

## Google Calendar (read-only)

Approach: OAuth 2.0 Authorization Code + PKCE through `ASWebAuthenticationSession` (the system sign-in sheet). No client secret is involved, so nothing secret ships in the app.

- [ ] Create a project at <https://console.cloud.google.com/>.
- [ ] Enable the **Google Calendar API**.
- [ ] OAuth consent screen: External, Testing mode, add your Google account as a test user.
- [ ] Credentials → Create OAuth client ID → type **iOS** (Google's recommended type for native Apple apps; it uses a custom-scheme redirect and needs no secret). Bundle ID: `com.keefer.DesktopBuddy` (or your own, matching the target).
- [ ] Copy the client ID into `Secrets.xcconfig` (git-ignored) as `GOOGLE_CLIENT_ID = …`. The redirect scheme is the reversed client ID.
- Scope requested: `https://www.googleapis.com/auth/calendar.events.readonly` (+ `calendar.calendarlist.readonly` if choosing calendars). Nothing that can write.
- Tokens: refresh token in the Keychain; access tokens in memory only.
- Handled cases: expired/revoked token (prompt to reconnect), offline (show last-fetched state with its timestamp), empty calendar, API errors.
- In Testing mode Google shows an "unverified app" screen and refresh tokens expire after 7 days. Fine for personal use; publishing would require Google's verification.

**Alternative worth knowing:** if your Google account is already added to macOS Calendar, EventKit can read it locally with one system permission and no Google Cloud setup. It could be offered as a second source later.

## Notion

To my knowledge, Notion's public-integration OAuth exchanges the code with a **client secret**, which can't be kept secret inside a desktop app. I'll re-check Notion's current docs at the start of Phase 3.

Recommended path:

- [ ] Create an **internal integration** at <https://www.notion.so/profile/integrations>; capabilities: Read content, and Update content only if you want completion sync.
- [ ] In Notion, share the task database(s) with the integration (••• → Connections).
- [ ] Paste the integration token into the app's Notion setup. It's stored in the Keychain, never in files or logs.
- In-app setup will let you pick a database and map its properties (title, status, done value, due date, priority, URL). No schema is assumed.
- Writing completion back to Notion happens only when you've mapped a status property, turned sync on, and confirmed.

A public OAuth integration would need a small token-exchange backend; we can add that later if you want one-click connection.

## AI provider (Phase 4)

- [ ] An API key for your chosen provider (the provider layer is pluggable; Claude is the planned default).
- Key entered in Settings, stored in the Keychain; never logged.
- Calendar or task data is only included in a request when you ask for something that needs it, and the panel shows when it was shared.
- Voice already works without it (on-device transcription + a rule-based command parser); the assistant will plug into the same transcript pipeline.
- The assistant can only act through explicit, typed operations (add task, mark done with confirmation, start focus). It never executes generated shell commands, and only reports an action as done after it actually succeeded.
