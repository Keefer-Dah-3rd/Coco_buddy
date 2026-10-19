# Integration setup (Phases 3–4)

Nothing here is needed for Phase 1 or 2. Each integration stays **disconnected** until it's genuinely configured — the app never shows a connection it doesn't have.

## Code signing (done — one click left)

The target signs automatically with **John Keefe (Personal Team)** (`DEVELOPMENT_TEAM = 7VXB4ZWKC7`). Stable signing keeps microphone/speech permissions and Keychain items attached to the app across rebuilds.

- [ ] Xcode › Settings › Accounts → select the Apple ID → sign in again if prompted (the command line couldn't reuse the saved session). The first ⌘R then creates the "Apple Development" certificate.
- Outgoing network access is enabled (Phase 3); incoming connections are not.

## Google Calendar — built, needs your client ID

How it works: Google's guidance for macOS apps is an **iOS-type** OAuth client. Sign-in runs in the system sheet (`ASWebAuthenticationSession`) with PKCE and the reversed client ID as the redirect — **no client secret exists**, so there's nothing secret to protect. Sign-in asks only for `calendar.events.readonly`. The first time you confirm adding, moving or deleting an event, the same sheet asks once more for `calendar.events` (events only — never the broader `calendar` scope), added to what you'd already granted (`include_granted_scopes`). Decline it and Coco stays read-only. Tokens live in the Keychain; the weeks you've looked at (last week to four weeks ahead) are cached locally so the schedule still shows, with its age, when offline. *Disconnect* revokes the token at Google and deletes the cache.

If Google's sheet ever says the app isn't allowed to ask for event changes, add `.../auth/calendar.events` under [Data access](https://console.cloud.google.com/auth/scopes) in your Google Cloud project — in Testing mode that isn't normally needed.

- [ ] [Create a Google Cloud project](https://console.cloud.google.com/projectcreate).
- [ ] [Enable the Google Calendar API](https://console.cloud.google.com/apis/library/calendar-json.googleapis.com).
- [ ] [OAuth consent screen / Audience](https://console.cloud.google.com/auth/audience): External, **Testing** (don't publish), and add **the exact Google account you'll sign in with** under *Test users* — otherwise Google shows "Access blocked … has not completed the verification process" (403 access_denied).
- [ ] [Create an OAuth client ID](https://console.cloud.google.com/auth/clients) → Application type **iOS** → Bundle ID `com.keefer.DesktopBuddy`.
- [ ] In the app: menu bar › **Connections…** › paste the client ID › **Sign in with Google**.

Notes: in Testing mode Google shows an "unverified app" screen (expected — it's your own app) and may ask you to sign in again after 7 days. The client ID is an identifier, not a secret; it's kept in the app's preferences, not in the repo.

## Apple Calendar — built, one click

How it works: Coco reads the calendars in the Calendar app (iCloud, Google or Exchange accounts added in *System Settings › Internet Accounts*, and On My Mac) through EventKit. It's read-only — Coco never adds, changes or deletes an Apple Calendar event — and nothing to set up beyond allowing access. The app has the sandbox's calendars entitlement and a usage description; macOS asks the first time you click **Connect**, never at launch.

- [ ] Menu bar › **Connections…** › **Apple Calendar** › **Connect Apple Calendar** › choose **Allow Full Access**.
- [ ] Check the list of calendars: your own are on; birthdays, subscribed calendars (holidays) and read-only calendars (usually other people's) start off. Switch any on or off.

If your Google account is also added to Calendar.app, the same meetings arrive from both sides. Coco shows each once: synced copies share an iCalendar UID with the Google event, and separate copies are matched by identical times and (nearly) identical titles — anything less certain stays as two rows. Edits from the chat still go only to Google Calendar.

- **Denied by mistake?** *System Settings › Privacy & Security › Calendars › Desktop Buddy* → **Full Access**, then **Check again** on the card. ("Add Only" isn't enough to read.)
- **Revoke:** turn it off in that same System Settings pane. *Stop using Apple Calendar* in Connections stops Coco reading it without changing the permission.
- Apple events are read when shown and re-read whenever Calendar.app reports a change; Coco keeps no copy of them on disk.

## Notion — built, needs your token

> Paused 2026-10-11, back on 2026-10-17. `Features.notion` in `DesktopBuddy/App/Buddy.swift` switches it off again if needed.

How it works: Notion's public OAuth requires a client secret (verified against Notion's docs), which a desktop app can't keep private — so the app uses a token you paste: an **internal connection** API token (Notion's new name for an internal integration; sees only databases you give it — least access) or a **personal access token** (sees what you can see). It's verified with Notion before being saved to the Keychain. Uses Notion API version `2025-09-03` (data sources).

- [ ] In Notion's [developer portal](https://app.notion.com/developers/connections) › **Internal connections** › create one (workspace owners only): capabilities *Read content*, plus *Update content* if you want Coco to be able to mark tasks done.
- [ ] Copy its **API token** from the **Configuration** tab.
- [ ] Give it your task database: **Content access** › **Edit access** in the portal, or in Notion open the database › **•••** › **Connections** › **Add connection**.
- [ ] In the app: **Connections…** › paste the token › **Connect** › choose the database › confirm the column mapping (task name, done status, due date, priority) — Coco suggests one, you can change it.

Behaviour: open tasks are offered in the panel under *Notion › Pick*; nothing joins today's plan until you pick it. Picked tasks stay linked (titles, due dates and done state follow Notion; a matching local task is linked rather than duplicated). Marking one done asks, every time, whether to update Notion too — and only if you turned that on in the mapping. *Disconnect* forgets the token and mapping; tasks already on your list stay as local tasks.

## Claude chat (Phase 4) — built, needs your API key

- [ ] Create a key at the [Anthropic Console](https://console.anthropic.com/settings/keys).
- [ ] In the app: **Connections…** › **Claude (chat)** › paste the key › **Connect**. It's checked with a free request (`GET /v1/models`) and saved to the Keychain — never to files, logs or the repo.

How it works:
- Model `claude-opus-5-5` at `low` effort (thinking is always on for this model; effort is the control), streamed over raw HTTP (no official Swift SDK).
- Server-side refusal fallback is **on** (`fallbacks: "default"`, beta `server-side-fallback-2026-07-01`): if a safety classifier wrongly declines a benign message, Anthropic re-runs it on another Claude model. Remove it in `ClaudeAPI.messagesRequest` if you'd rather not.
- Your day is shared only through the `get_today` tool, when the model needs it for your request; the chat marks each time.
- Four tools, validated strictly before running: `get_today`, `propose_tasks` (drafts you review), `start_focus`, `request_task_completion` (you confirm). No shell, no web, nothing outside the app.
- History is append-only and in memory only; **New chat** forgets it. Costs are estimated at list prices and shown under the input.
- Provider is behind `AssistantService`/`ClaudeAPI`; another provider would be a sibling of `ClaudeAPI` with the same tools.
