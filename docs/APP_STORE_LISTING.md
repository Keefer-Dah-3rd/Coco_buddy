# App Store listing drafts

Text to paste into App Store Connect. Character limits are Apple's; counts are given where they're tight. Anything in **[brackets]** waits on a decision (see the open questions at the end).

## Name and subtitle

**Name** (30 max). Pick one, then check it's free when you create the app record:

| Option | Characters |
| --- | --- |
| Desktop Buddy: Coco | 19 |
| Coco: Desktop Buddy | 19 |
| Coco – Desktop Corgi Planner | 28 |

**Subtitle** (30 max):

| Option | Characters |
| --- | --- |
| A corgi who helps plan your day | 31 (one too many) |
| A corgi who plans your day | 26 |
| Focus, plans and a desk corgi | 29 |
| Your desktop planning pal | 25 |

## Promotional text (170 max; can change any time without review)

> Meet Coco, a corgi who lives on your desktop. Plan your day, run focus sessions, see your calendars, and play fetch when you need a break.

(138 characters)

## Description (4,000 max)

> Coco is a black-and-white corgi who lives on your Mac's desktop and helps you get through the day. She sits by your work, reacts to what you do, and is always one click away.
>
> PLAN YOUR DAY
> • A quick task list for today: type "Draft homepage ~45m !!" and it understands the estimate and priority.
> • Up next: Coco suggests what to do next and tells you why: it's overdue, due today, quick, or high priority.
> • Nothing is ever marked done because time passed. You decide.
>
> FOCUS
> • A focus timer with short and long breaks, linked to the task you're working on.
> • During focus, Coco gets small and quiet, or tucks away completely.
> • When a session ends, she asks whether the task is done; she never assumes.
>
> YOUR CALENDARS
> • See today and the week from Apple Calendar[, Google Calendar] and Partiful in one place, with each event shown once.
> • Open time, what's next, and a reminder before meetings.
> • Paste a Partiful invite into the chat and Coco reads the details for you.
>
> TALK TO COCO
> • Chat with Coco to plan, brainstorm or break a big task into steps. She checks your real tasks and calendar when she needs to, and shows you each time she looks.
> • Anything that would change your list or calendar appears as a card to confirm first.
> • Voice: press the mic and say "add call Sam and draft the brief" or "start a 25-minute focus".
>
> PLAY
> • Hold the right Option key and click: Coco runs there.
> • Hold the right Command key and click: throw her ball and she fetches it.
> • Hold the right Shift key and click: toss her a treat.
>
> PRIVATE BY DESIGN
> • No account, no ads, no analytics, no tracking.
> • Everything stays on your Mac unless you connect a service or use the chat.
> • Before the chat sends anything, Coco shows you exactly what would be shared and asks first.
> • Settings › Delete all my data removes everything.
>
> GOOD TO KNOW
> • The chat uses Claude by Anthropic with your own Anthropic API key. Usage is billed by Anthropic to your account. Everything else works without a key.
> • Works with Notion: pick tasks from a Notion database (needs a Notion integration token).
> • Partiful and Notion are trademarks of their owners; Desktop Buddy isn't made or endorsed by them.
>
> Requires macOS 14 or later.

## Keywords (100 max, comma-separated, no spaces needed)

```
desktop pet,corgi,dog,focus timer,pomodoro,planner,to do,tasks,calendar,productivity,companion,AI
```

(97 characters.) Don't repeat words already in the name or subtitle; Apple counts those already. Drop "corgi" if it ends up in the name.

## What's New (for later versions)

> First release. Say hi to Coco.

## Support, privacy and marketing URLs

Live on GitHub Pages since 2026-10-19 (repository Settings › Pages › `main`, folder `/docs`):

- Support URL: `https://keefer-dah-3rd.github.io/Coco_buddy/support/`
- Privacy Policy URL: `https://keefer-dah-3rd.github.io/Coco_buddy/privacy/`
- Marketing URL: optional, leave empty for now.

## Copyright

`2026 John Keefe` (App Store Connect adds the ©).

## App Review information: notes

> Desktop Buddy has no Dock icon. After launch, Coco (a corgi) appears on the desktop. Click her, or press Control-Option-C, to open her panel. Right-click her for the menu, which includes Settings and Quit.
>
> Hidden features (no permissions needed):
> • Hold the right-hand Option key and click anywhere: Coco runs there.
> • Hold the right-hand Command key and click: throws a ball for her to fetch.
> • Hold the right-hand Shift key and click: tosses her a treat.
>
> Chat: open Connections (from the panel) › Claude and paste this test key: [TEST KEY]. The first time you open the Chat tab, "Before you chat" lists exactly what is sent to Anthropic; nothing is sent until you choose Allow. To turn it off later, go to Settings › Privacy & data. Under each reply, "Report" opens an email to support.
>
> Calendars: Connections › Apple Calendar reads the calendars on this Mac (read-only). [Google: either the test account, or "Google Calendar is optional; Apple Calendar shows the same events."]
>
> Partiful: paste this public invitation into the chat: [WORKING PARTIFUL LINK]. Ask "add this to my calendar" to see the confirmation card. [Calendar import: Connections › Partiful › paste: TEST CALENDAR LINK.]
>
> Notion: Connections › Notion › paste this token: [TEST NOTION TOKEN]. Choose the "Review tasks" database and accept the suggested fields, then open the panel › Notion › Pick.
>
> Voice: press the microphone in the panel; macOS asks for microphone and speech recognition access.

## Age rating questionnaire: suggested answers

Answer for what the app can show, not what's likely. Draft answers:

- Violence, sexual content, profanity, drugs, gambling, horror, medical/treatment information: **None** in the app's own content.
- Unrestricted web access: **No.** The app opens only Partiful invitation pages and calendar links the user gives it, plus the service APIs it connects to. There's no browser.
- User-generated content shared with others / messaging between users: **No.**
- AI assistant or chatbot: **Yes.** The chat generates free text with Claude. Apple asks you to weigh how often such content could appear. Claude refuses most mature requests, but replies aren't pre-written, so expect a higher rating than the content alone would give (likely 13+ or above). Accept what the questionnaire calculates rather than forcing it lower.
- Parental controls / age assurance: none in the app.

## App Privacy (data types)

Matches the privacy manifest (`DesktopBuddy/Resources/PrivacyInfo.xcprivacy`) and the privacy policy.

- **Do you or your third-party partners collect data from this app?** Yes. To be safe, count data that goes to Anthropic when the user chats.
- **Data type:** User Content › **Other User Content** (chat messages and the tasks, calendar details and invitations the chat looks up).
  - Linked to the user: **Yes** (it goes to Anthropic under the user's own API key).
  - Used for tracking: **No.**
  - Purpose: **App Functionality** only.
- Nothing else: no contact info, identifiers, usage data, diagnostics, location, health, financial or browsing data, because there are no analytics or crash SDKs.
- Voice: audio isn't collected; speech recognition is Apple's and on-device where supported.

## Other App Store Connect answers

- **Category:** Productivity (primary). Secondary is optional: Lifestyle.
- **Content rights:** "Yes, this app contains, shows or accesses third-party content", meaning the user's own calendar, Partiful and Notion data. You have the rights to the app's own art, plus the barks [once confirmed].
- **Export compliance:** handled in the build: `ITSAppUsesNonExemptEncryption = NO` (only Apple's HTTPS).
- **Sign-in required?** No. There's no account; App Review needs only the test key and tokens above.
- **Release:** manual release after approval, for version 1.0.

## Open questions (your call)

- Which name and subtitle.
- Price, and which countries; leaving out the EU avoids publishing trader details.
- Google Calendar in version 1 or not. This changes the description's calendar line and the review notes.
- The test material: Claude key, Partiful links, Notion workspace and token.
