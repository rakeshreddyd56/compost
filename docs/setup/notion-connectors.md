# Connect Gmail + Google Calendar to Notion

The Compost notch app does not handle any Gmail or Calendar OAuth on its own.
Both go through **Notion's native connectors**, which means Notion owns the
auth dance and our app + Worker never see a refresh token.

After this one-time setup, the **Today Brief** Custom Agent inside Notion will
be able to read your inbox and your calendar and write summaries into the
existing `cueCards` database. The notch already renders those rows as the
☀️ Up next section, so no app code changes are required.

## Steps

### 1. Open Notion in the browser
The connectors UI is in the desktop / web app, not the Notion API console.

### 2. Add the Gmail connection
1. Click your workspace name (top left) → **Settings & members**.
2. In the left sidebar, click **My connections**.
3. Click **+ Add connection**.
4. Search for **Gmail** and click it.
5. Follow Google's OAuth screen. Grant Notion read access to your inbox.
6. Back in Notion, confirm Gmail now shows **Connected** in **My connections**.

### 3. Add the Google Calendar connection
1. Same path: **Settings & members → My connections → + Add connection**.
2. Search for **Google Calendar** and click it.
3. Finish Google's OAuth flow.
4. Confirm **Google Calendar** also shows **Connected**.

### 4. Share the Compost Demo Workspace with both connections
Notion's Custom Agents can only access pages that are explicitly shared with
the connection.

1. Open **📦 Compost Demo Workspace**.
2. Click **Share** (top right).
3. Add **Gmail (Notion connection)** with **Can read** access.
4. Add **Google Calendar (Notion connection)** with **Can read** access.

### 5. Verify
Open the Compost Demo Workspace → click the connection avatars at the top of
the share dialog. Both Gmail and Calendar should be listed.

## What happens next

- The **Today Brief** Custom Agent (see [`docs/custom-agents/today-brief.md`](../custom-agents/today-brief.md))
  will query your inbox + calendar through Notion every 30 minutes and write
  a single row into the `cueCards` database with the next event, urgent
  email count, and a short headline.
- The Compost notch will render that row in the ☀️ **Up next** section.

## Notes

- The connectors are read-only by default. The Today Brief agent won't draft
  emails or create calendar events.
- If you change which calendars Notion can see, you'll be re-prompted by
  Google. No code change needed.
- If you're on a Notion plan that doesn't include Gmail/Calendar connectors,
  the section will stay empty — nothing breaks; the rest of the notch
  continues to work.
