# Integration setup (Phases 3–4)

Nothing here is needed for Phase 1 or 2. Each integration stays **disconnected** until it's genuinely configured — the app never shows a connection it doesn't have.

## Code signing (done — one click left)

The target signs automatically with **John Keefe (Personal Team)** (`DEVELOPMENT_TEAM = 7VXB4ZWKC7`). Stable signing keeps microphone/speech permissions and Keychain items attached to the app across rebuilds.

- [ ] Xcode › Settings › Accounts → select the Apple ID → sign in again if prompted (the command line couldn't reuse the saved session). The first ⌘R then creates the "Apple Development" certificate.
- Outgoing network access is enabled (Phase 3); incoming connections are not.

## Google Calendar (read-only) — built, needs your client ID

How it works: Google's guidance for macOS apps is an **iOS-type** OAuth client. Sign-in runs in the system sheet (`ASWebAuthenticationSession`) with PKCE and the reversed client ID as the redirect — **no client secret exists**, so there's nothing secret to protect. The only scope requested is `calendar.events.readonly`. Tokens live in the Keychain; today's events are cached locally so the schedule still shows (with its age) when offline. *Disconnect* revokes the token at Google and deletes the cache.

- [ ] [Create a Google Cloud project](https://console.cloud.google.com/projectcreate).
- [ ] [Enable the Google Calendar API](https://console.cloud.google.com/apis/library/calendar-json.googleapis.com).
- [ ] [OAuth consent screen / Audience](https://console.cloud.google.com/auth/audience): External, **Testing** (don't publish), and add **the exact Google account you'll sign in with** under *Test users* — otherwise Google shows "Access blocked … has not completed the verification process" (403 access_denied).
- [ ] [Create an OAuth client ID](https://console.cloud.google.com/auth/clients) → Application type **iOS** → Bundle ID `com.keefer.DesktopBuddy`.
- [ ] In the app: menu bar › **Connections…** › paste the client ID › **Sign in with Google**.

Notes: in Testing mode Google shows an "unverified app" screen (expected — it's your own app) and may ask you to sign in again after 7 days. The client ID is an identifier, not a secret; it's kept in the app's preferences, not in the repo.

## Notion — paused

> Out of the plan until further notice. The code is kept but switched off (`Features.notion = false` in `DesktopBuddy/App/Buddy.swift`). Notes below are for when it returns.

How it works: Notion's public OAuth requires a client secret (verified against Notion's docs), which a desktop app can't keep private — so the app uses a token you paste: an **internal integration** secret (sees only databases you share with it — least access) or a **personal access token** (sees what you can see). It's verified with Notion before being saved to the Keychain. Uses Notion API version `2025-09-03` (data sources).

- [ ] [Create an internal integration](https://www.notion.so/profile/integrations): capabilities *Read content*, plus *Update content* if you want Coco to be able to mark tasks done.
- [ ] Copy its **Internal Integration Secret**.
- [ ] In Notion, open your task database › **•••** › **Connections** › add the integration.
- [ ] In the app: **Connections…** › paste the secret › **Connect** › choose the database › confirm the column mapping (task name, done status, due date, priority) — Coco suggests one, you can change it.

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
