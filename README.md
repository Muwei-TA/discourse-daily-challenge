# Discourse Daily Challenge

![Version](https://img.shields.io/badge/version-v1.5.0-blue)

A Discourse plugin for running time-limited challenges. Participants check in by posting with a challenge hashtag or uploading a photo. Admins and moderators get a real-time leaderboard dashboard, automated weekly progress posts, a final results announcement, optional badge awards for completers, and a bot user that sends personal DMs for check-in confirmations, reminders, and @mention commands.

## Screenshots

_Screenshots coming soon._

| Dashboard — active challenges | Archived challenges |
|---|---|
| _(placeholder)_ | _(placeholder)_ |

## Features

- **Hashtag or photo check-ins** — participants check in by posting with the configured hashtag (e.g. `#workout`) or by uploading any image to the challenge topic
- **Configurable check-in interval** — daily or weekly, with configurable week start day (Sunday, Monday, or Saturday); duplicate check-ins within the same period are silently ignored
- **Real-time admin dashboard** — shows all active challenges simultaneously, each with its own stats, leaderboard, and per-participant contribution grid
- **Archived challenges accordion** — past challenges collapsed into an expandable section showing final participant count, winner, and completion rate
- **Per-challenge timezone** — start/end dates, weekly post timing, and check-in windows are all evaluated in the challenge's configured timezone
- **Automated weekly leaderboard posts** — posted to the challenge topic by the system user on a configurable day and hour
- **Final results post** — automatically posted the day after the challenge ends, listing all participants who met the goal
- **Badge awards** — optionally award a custom Discourse badge to every participant who reaches the check-in goal
- **Manual leaderboard trigger** — admins can post the leaderboard at any time from the challenge management page
- **Admin check-in management** — add or remove check-ins for any user from the admin panel (for missed posts, support requests, etc.)
- **Moderator access** — full moderators can access challenge management via a dedicated sidebar section with Dashboard and Challenges tabs
- **Category Moderator Access** — category moderators can manage challenges in their assigned categories via a dedicated /challenges route, separate from the admin panel
- **Per-challenge configuration** — each challenge has its own hashtag, dates, timezone, check-in interval, check-in goal, weekly post schedule, and badge settings
- **🤖 ChallengeBot DMs** — check-in confirmation DMs with streak info and a clickable topic link, reminder DMs for participants who haven't checked in (daily: after 2+ missed days; weekly: on the last day of the week if not yet checked in), and commands for personal stats via @mention in the challenge topic or direct message — all sent as private messages from a configurable bot account
- **Edit detection** — if a participant edits a post to add the challenge hashtag or an image, a check-in is automatically recorded using the original post date (within 24 hours for daily challenges, or within the same week for weekly challenges)

## Installation

Add the plugin to your Discourse `app.yml`:

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone https://github.com/R23DPrinting/discourse-daily-challenge.git
```

Then rebuild your container:

```bash
./launcher rebuild app
```

## Configuration

### Site Settings

| Setting | Default | Description |
|---|---|---|
| `daily_challenge_enabled` | true | Master on/off switch for the plugin |
| `daily_challenge_mod_access_enabled` | true | Allow full site moderators to manage challenges |
| `daily_challenge_category_mod_access_enabled` | true | Allow category moderators to manage challenges in their categories |
| `daily_challenge_bot_username` | "" | Username of the bot account that sends check-in confirmation DMs, reminder DMs, and @mention command responses |

### Setting Up ChallengeBot

The bot features are optional. To enable them:

1. **Create the bot user account.** SSH into your server and run:
   ```bash
   cd /var/discourse
   ./launcher enter app
   rake admin:create
   ```
   When prompted, enter the bot's email, a strong password, and answer **n** to admin privileges.

2. **Approve the account and set trust level.** In **Admin → Users**, find the newly created account (it will have an auto-generated username like `user1`) and:
   - Click **Approve** to approve the account
   - Set **Trust Level** to **1**

3. **Set the username.** The account will have an auto-generated username. Go to the account's profile and update the username to `ChallengeBot` (or whatever you prefer).

4. **Optionally** set a profile picture for the bot account.

5. **Configure the plugin.** Go to **Admin → Plugins → Challenges → Settings** and enter the username in the **Bot username** field.
   > ⚠️ This field is case-sensitive — enter the username exactly as it appears in the profile.

If no bot username is configured, all bot features are silently disabled and challenges continue to work normally.

### Creating a Challenge

Go to **Admin → Plugins → Challenges → Challenges → New Challenge**.

| Field | Description |
|---|---|
| **Topic ID** | The ID of the Discourse topic where participants will post. The plugin fetches and displays the topic title as a confirmation after you enter the ID. |
| **Hashtag trigger** | The hashtag (without `#`) that triggers a check-in when included in a post. Only letters, digits, and underscores are allowed. |
| **Start date** | The first day of the challenge (inclusive). |
| **End date** | The last day of the challenge (inclusive). Check-ins are accepted through the end of this day in the challenge timezone. Must be after the start date. |
| **Challenge timezone** | Timezone used for all date boundaries, weekly post timing, and the final post trigger. Defaults to UTC. |
| **Check-in interval** | Whether participants check in daily or weekly. |
| **Week start** | For weekly challenges: which day starts the week (Sunday, Monday, or Saturday). Only shown when interval is set to Weekly. |
| **Check-ins needed** | The number of check-ins required to complete the challenge and qualify for the badge. |
| **Description** | Optional internal note about the challenge (not shown to participants). |
| **Enable weekly leaderboard post** | When enabled, the system automatically posts a leaderboard update to the challenge topic on a schedule. |
| **Post day of week** | Day the weekly post is published (Sunday–Saturday, in the challenge timezone). |
| **Post hour (0-23)** | Hour the weekly post is published, in the challenge timezone. |
| **Award completion badge** | When enabled, a Discourse badge is created and automatically granted to participants who reach the check-in goal when the challenge ends. Requires a badge name. |
| **Badge name** | Name of the badge to create (e.g. "March Fitness Champion"). Auto-populates from the topic title when a topic ID is entered. Required when "Award completion badge" is enabled. |
| **Enable reminder DMs** | When enabled (and a bot username is configured), sends reminder DMs to participants who haven't checked in recently. Defaults to enabled. |

## How Check-ins Work

A check-in is recorded automatically when a participant posts in the linked topic and their post matches either condition:

1. **Hashtag** — the post body contains the challenge hashtag (e.g. `#workout`). The match is case-insensitive and must be a whole word (preceded by a space or the start of the line).
2. **Image upload** — the post includes an image attachment (jpg, jpeg, png, gif, webp, heic, or avif).

**Rules:**
- Only one check-in is recorded per user per period: one per calendar day for daily challenges, or one per calendar week for weekly challenges (week boundaries determined by the configured week start day, evaluated in the challenge's timezone).
- Check-ins are only recorded while the challenge is active (between start date and end date, evaluated in the challenge's timezone).
- Anonymous users cannot check in.
- System posts and non-regular posts are ignored.

## ChallengeBot DMs

When a bot username is configured, the bot sends private messages for the following events:

### Check-in Confirmation
Every time a participant successfully checks in, they receive a DM with:
- A link to the challenge topic
- Their current streak (e.g. "5-day streak 🔥")

### Reminder DMs
Participants who fall behind receive a reminder DM including their current check-in count and the goal:
- **Daily challenges** — sent to participants who haven't checked in for 2 or more consecutive days
- **Weekly challenges** — sent on the last day of the challenge week to participants who haven't checked in that week

A Redis key with a 25-hour TTL prevents duplicate reminders per user per challenge per day.

## @ChallengeBot Commands

Commands can be triggered two ways:

- **@mention in a challenge topic** — mention the bot followed by the command (e.g. `@ChallengeBot streak`). The bot never replies in the topic — responses are always sent as a private message.
- **Direct message** — send a DM directly to ChallengeBot, or reply to any existing ChallengeBot DM thread. Type just the command word with no @mention needed (e.g. `streak`).

| Command | Description |
|---|---|
| `status` | Stats across all active challenges you've participated in |
| `leaderboard` | Current top-10 standings for this challenge |
| `streak` | Your current streak for this challenge |
| `checkins` | Full list of all your check-in dates for this challenge |
| `progress` | Check-ins done vs needed, time remaining, on-track status |
| `help` | List all available commands |

### Challenge picker

When using DM commands, the bot needs to know which challenge you're asking about:

- **0 active challenges** — the bot replies that you're not part of any active challenges
- **1 active challenge** — the bot responds immediately
- **2+ active challenges** — the bot presents a numbered list; reply with the number to select a challenge, or **A** to get results for all challenges. The selection prompt expires after 5 minutes.

`status` and `help` always respond immediately regardless of how many challenges you're in.

> **Rate limit:** commands are limited to 10 per user per hour across both @mention and DM triggers. If exceeded, the bot sends a single notice and ignores further commands until the window resets.

### Recommended site setting

Discourse's **Minimum personal message post length** setting (`min_personal_message_post_length`) defaults to 1 character, but if your site has raised it, short commands like `status` may be blocked. Set it to 1 or low enough to allow single-word messages in DMs with ChallengeBot.

## Admin Dashboard

The dashboard (**Admin → Plugins → Challenges → Dashboard**) shows all currently active challenges. Each challenge gets its own section with:

- **Challenge header** — hashtag, linked topic title, and day progress
- **Stats tiles** — total participants, average check-ins, and overall challenge progress percentage
- **Leaderboard table** — ranked by total check-ins, showing current streak and completion percentage per participant
- **Contribution grid** — click any row to expand a GitHub-style heatmap of that participant's check-in history for the challenge period

If there are no active challenges, a friendly message is shown with a link to create one.

### Archived Challenges

Below the active challenges, completed challenges are shown in a collapsible accordion. Each entry shows:

- Challenge hashtag and topic title
- Date range
- Total participants, winner (most check-ins), and completion rate

Expand any entry to see the details and a link to the original topic.

## Weekly Posts

When **Enable weekly leaderboard post** is turned on for a challenge, the plugin posts a markdown leaderboard table to the challenge topic every week at the configured day and hour (in the challenge's timezone). The post is made by the system user and includes:

- The week's date range
- Current day progress in the challenge
- A ranked table of all participants with their check-in count, goal, and progress percentage

You can also trigger a leaderboard post manually at any time from the challenge detail page using the **Post leaderboard now** button.

## Final Results Post

The day after a challenge ends (evaluated in the challenge's timezone), the plugin automatically posts a final results summary to the challenge topic. The post includes:

- A list of all participants who reached the check-in goal
- A summary of how many out of the total participants completed the challenge
- Congratulations to completers, or an encouraging message if no one reached the goal

The final post is sent exactly once per challenge.

## Badge Awarding

If **Award completion badge** is enabled and a **Badge name** is provided, the plugin:

1. Creates a Discourse badge (Silver tier) when the challenge is saved
2. Automatically grants the badge to every participant who reaches the check-in goal when the final results post is published
3. Updates the badge name and description if you edit the challenge settings

The badge description is automatically set to reference the linked topic title (e.g. "Awarded to participants who completed all required check-ins in March Challenge.").

## Admin Check-in Management

Admins can manually add or remove check-ins for any user from the challenge detail page (**Admin → Plugins → Challenges → Challenges → [challenge name]**). This is useful for:

- Adding check-ins for participants who posted outside the topic
- Correcting missed check-ins due to technical issues
- Removing erroneous check-ins

Manually added check-ins are marked with an "Admin" source label in the check-in list.

## Roadmap

### v1.6.0

_Planned features TBD._

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes, following the [Discourse plugin development guide](https://meta.discourse.org/t/beginners-guide-to-creating-discourse-plugins/30515)
4. Run the test suite: `bin/rspec plugins/discourse-daily-challenge`
5. Lint your changes: `bin/lint --fix --recent`
6. Open a pull request

## License

MIT License. See [LICENSE](LICENSE) for details.

## Changelog

### v1.5.0
- **Edit detection** — if a participant edits a post to add the challenge hashtag or an image, a check-in is automatically recorded using the original post's creation date; daily challenges accept edits within 24 hours, weekly challenges accept edits within the current challenge week
- **DM commands** — users can now send ChallengeBot commands by DMing the bot directly or by replying to any existing ChallengeBot DM thread, with no @mention required; commands (`status`, `leaderboard`, `streak`, `checkins`, `progress`, `help`) work identically to the @mention versions
- **Challenge picker** — when a user is in multiple active challenges, DM commands present a numbered list to select which challenge to query; reply with a number or **A** for all; single-challenge users get an immediate response; `status` and `help` always respond immediately

### v1.4.1
- **First check-in welcome DM** — members receive a special welcome message on their first check-in for a challenge
- **Completion celebration DM** — members receive a congratulations DM when they hit the required check-ins, mentioning the badge name if one is configured
- **Progress in confirmation DM** — check-in confirmation DMs now include current check-in count vs goal
- **Two-stage reminder DMs** — reminders now sent at day 2 and day 7 of missed check-ins only, not every day; each stage sends once and resets when the user checks in
- **Friendly date format** — `@ChallengeBot checkins` now shows dates as "March 24, 2026" instead of "2026-03-24"
- **Leaderboard posts from ChallengeBot** — weekly leaderboard and final results posts are now sent from ChallengeBot if configured, falling back to the system user

### v1.4.0
- **ChallengeBot check-in confirmation DMs** — participants receive a private message from the bot after each successful check-in, including a clickable link to the challenge topic and their current streak
- **Reminder DMs** — daily challenges nudge participants after 2+ missed consecutive days; weekly challenges nudge on the last day of the week if not yet checked in. Message includes current check-in count and the goal. Duplicate DMs prevented via Redis (25-hour TTL per user/challenge/day).
- **@mention commands** — members can mention the bot in any active challenge topic to receive stats via DM (`status`, `leaderboard`, `streak`, `checkins`, `progress`, `help`). Bot never replies in the topic — always DM only.
- **Rate limiting** — max 10 bot commands per user per hour; exceeded requests receive a single notice DM
- **Per-challenge reminder DMs toggle** — `reminder_dms_enabled` field on each challenge, defaults to enabled
- **Bot username site setting** — `daily_challenge_bot_username` configures the bot account; leave blank to disable all bot features

### v1.3.0
- **Category moderator access** — category mods can create, edit, delete, and manage check-ins for challenges in their assigned categories via /challenges/dashboard and /challenges/challenges
- **Badge name auto-populate** — badge name field now auto-populates from the topic title when a topic ID is entered
- **Badge name validation** — badge name is required when "Award completion badge" is toggled on; backend returns 422 instead of 500 if badge name is missing
- **Mod/category mod access toggles** — separate site settings to enable/disable access for full mods and category mods independently

### v1.2.0
- Configurable check-in interval: daily or weekly
- Week start setting for weekly challenges (Sunday, Monday, or Saturday)
- Interval-aware streak calculation and labels (day streak vs week streak)
- Full moderator access via main sidebar with Dashboard and Challenges tabs
- Plugin renamed to "Discourse Challenges" in the admin UI

### v1.1.1
- Multi-challenge dashboard showing all active challenges simultaneously
- Archived challenges accordion showing historical results

### v1.1.0
- Per-challenge timezone support
- Weekly post schedule now per-challenge (day, hour, enable/disable toggle)
- Challenge timezone used for start/end date boundaries and final post timing

### v1.0.0
- Initial release
