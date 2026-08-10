# Xal's Compendium - Changelog

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
