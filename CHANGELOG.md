# Xal's Compendium - Changelog

## 1.0.7 - August 12, 2026

---

This update ended up being bigger than I expected once I got going. The whole addon now matches the look I've been rolling out across my other addons - new icons, cleaner checkboxes, a proper minimap icon instead of the placeholder, all of it. The tracker window can also fade out of sight when you're not using it and shrink down to a tiny bar if you want it out of the way without closing it. I also caught a real bug - the weekly dungeon board was showing all five possible dungeons as active every week, when really only one of them is up at a time, so that's fixed now. And the catalog itself got a lot bigger this update - a couple dozen more real quests added in, including some I only caught by watching my own account while I played. Bit by bit this thing is turning into what I actually pictured when I started it.

### 🆕 New
- **Fade when idle** - the tracker window fades to fully invisible when you're not moused over it, and snaps back to full opacity the moment you hover it. How transparent it goes while idle is adjustable in Appearance settings (defaults to fully invisible).
- **Minimize button** - collapses the tracker into a small "D / W" bar showing how many Daily and Weekly items you've got left, so it can stay tucked away without closing it entirely.
- **What's New splash** - now pops up automatically the first time you log in after an update, same as Xal's other addons.
- **Real minimap icon** - a proper custom icon (parchment scroll and quill) instead of the old placeholder look.

### 🐛 Fixed
- The weekly dungeon board was showing all 5 possible dungeons as separate weekly quests at once - it's actually one rotating slot (only one is active per week), so it now shows as a single item that tracks whichever one is actually up.

### 🗺️ Catalog
- Added Showdown on Val, Showdown on Val (Heroic), Showdown on Naigtal, and Showdown on Naigtal (Heroic) to Weekly Events.
- Added 20 more verified quests across Weekly Events, World Quests, Professions, and Legacy content.

### ⚙️ Under the hood
- Buttons, checkboxes, and divider lines across the whole addon now match the shared Xal's brand look (accent-gold borders, flat style, thicker lines) instead of Blizzard's default grey/native style.
- Background color darkened slightly to match the current brand standard.
- Checkbox checkmarks look a little cleaner/better-centered now.
- Window titles switched to a cleaner custom font instead of the old default.

## 1.0.6 - August 12, 2026

---

I think I finally got this thing to work. I've been chipping away at a way to automate pulling in real daily and weekly quest data, and this is the first version where it's actually showing up - real quests, not a placeholder sitting on your addon list looking pretty and doing nothing. Fingers crossed I got it working correctly, but I can only test so much on my own. If you're running this, please poke at it and let me know if anything looks off - you all catching the bugs I can't see is genuinely what's going to turn this into something I'm proud of. Thanks for helping me get there.

### 🆕 New
- **First real catalog content** - 8 real, current Weekly quests now show up under Current -> Weekly -> Weekly Events, instead of test placeholders or an empty list.

## 1.0.5 - August 11, 2026

---

I've been trying to get the quest data pulling fully automated, and honestly it's taken a few more tries than I expected - a couple of attempts came back broken and I had to dig into why before pushing forward. It's not fully done yet, but I'm actively on it and hopeful it'll be up and running clean in the next update. Appreciate the patience while I get this right.

### 🐛 Fixed
- The quest catalog updater now keeps everything it learns about each quest, not just the name - the next step is using that to automatically sort quests into their real spots instead of a manual sorting pass.

## 1.0.4 - August 11, 2026

---

Fixed the real reason the quest catalog updater was still finding zero real quests even after last update's fix.

### 🐛 Fixed
- The updater's login step to Blizzard's servers wasn't actually being used correctly, so every single quest lookup failed regardless of which quest it was checking. It's fixed now and should actually find real quest data on its next run.

## 1.0.3 - August 10, 2026

---

Fixed the quest catalog updater finding zero real quests on its first real run, plus brought the release tooling in line with the current standard.

### 🐛 Fixed
- The quest catalog updater was checking the oldest quests in the game first, which Blizzard's own data doesn't have records for - it now checks the newest ones first, so it actually finds real, current quests.

## 1.0.2 - August 9, 2026

---

Fixed the quest catalog updater crashing on a transient network hiccup and losing an entire run's progress.

### 🐛 Fixed
- A brief connection error while talking to Blizzard's servers used to crash the whole update instead of just retrying - now it retries automatically before giving up, so a temporary network blip doesn't waste a run.

## 1.0.1 - August 9, 2026

---

Fixed a real problem in the quest catalog update tooling before it ever ran for real.

### 🐛 Fixed
- The quest catalog updater could have run for hours on its very first pass and lost all its progress if interrupted. It now works in small, safe batches and saves as it goes.

## 1.0.0 - August 8, 2026

---

Initial release - a daily, weekly, and one-time quest & activity tracker, built to show you everything you've got left to do across your whole account, at a glance.

### 🆕 New
- **Current/Legacy tiers** - Daily, Weekly, and One-time content split by whether it's from the active expansion or older content.
- **Content categories** - Great Vault, Currencies, Weekly Events, Professions, Reputation, Story/Campaign, World Quests, and Custom.
- **Sub-task trees** - multi-step questlines show their steps nested and trackable individually.
- **Streaks** - current and best completion streaks per type, tracked per character.
- **Completion popups** - get notified the moment a tracked quest turns in, even with the window closed.
- **TomTom integration** - one-click waypoints straight to any trackable quest.
- **Diagnostics report** - a copyable report flagging catalog issues, for easy bug reporting.
- **Great Vault & currency tracking** - live progress pulled straight from the game, plus a picker for which currencies you actually care about, with optional goal alerts.
- **Reputation browser** - every faction you have standing with, right in settings.
- **Backup manager** - automatic daily snapshots of your settings and progress, restorable anytime.
- **Item level display** - your average equipped item level, right on the tracker.
- **Time-gated content support** - built to handle limited-time events automatically.
- **Escape to close** - every window closes with the Escape key, like any other panel.
- **Deep customization** - fonts, colors, transparency, frameless mode, window scale, all resettable.
- **Two ways into settings** - a real standalone popup window (`/xcp options`), or the native Blizzard Options -> AddOns list.

### 🧪 Xperimental
- **Alt roster** - check in on your other characters' progress without logging into them. Each character shares a snapshot of its own progress when you play it, so this reflects your alts as of their last login, not live while they're offline.

### 🚧 In the Works
- Custom tabs with configurable reset - add your own tracked items with their own reset schedule.
- A loot-upgrade popup, possibly tying into an existing addon like Pawn.
