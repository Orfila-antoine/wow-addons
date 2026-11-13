# Changelog

All notable changes to Pedibus, written for players.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versions follow [SemVer](https://semver.org/).

## [Unreleased]

### Fixed
- A beta version no longer counts as newer than the final release: beta testers are told when the release is out, and players on the release no longer get a wrong "new version" message.

## [1.3.1]

### Added
- If someone in your group has a newer version, a message tells you once. In the panel, friends on an older version are marked "needs update".

## [1.3]

### Added
- **Translations**: English, German, Spanish, Italian, Portuguese, Russian, Korean, Simplified and Traditional Chinese. The addon follows your game client's language.
- Friends playing in different languages can share the same bus and the same games.
- New commands `/pedibus games` and `/pedibus arrow`.

### Changed
- Fewer chat messages: those repeating the panel, the badge or an alert are gone.
- When someone joins your game, you're told (sound and on-screen message), even with the games window closed.
- When a friend opens a game, a bubble with a **Join** button shows up under the Pedibus button.

## [1.2.2]

### Added
- **Request a stop**: passengers click **Stop?** on their badge. The driver gets an alert and picks **Stop** (the usual stop with "I'm done") or **Later** (the passenger is told). One request every 20 seconds at most.

## [1.2.1]

**Update the whole group to 1.2.1**: 1.2 and 1.2.1 Yahtzee games can't start together.

### Added
- **Spectator mode**: from a game's tab, watch your friends play (Yahtzee, Battleship, Connect Four, Poker). In poker, hole cards stay hidden.

### Fixed
- **Roll call**: passengers already aboard got nothing. They now get "The bus is here!" with a **Follow** button that resumes auto-follow in one click. The driver sees how many passengers were called.

## [1.2]

**Everyone in the group needs 1.2**: older versions don't recognize each other.

### Added
- **Bus games**: while the driver drives, auto-following passengers play together, mouse only: Yahtzee (1 to 4 players), Battleship (2), Connect Four (2), Texas Hold'em poker (2 to 5, with chips, no gold involved). Other group members can watch a game in progress (in poker, hole cards stay hidden). Open the games with a right-click on the Pedibus button, the dice in the panel or on the passenger badge, or a key binding (Esc > Options > Keybindings > AddOns > Pedibus). The driver can play too.
- **Stops**: the driver clicks **Stop**, every passenger gets an **I'm done** button and their games pause. The driver sees who's done and hears a signal when everyone is ready. **Leave now** skips the wait.
- **Arrow to the driver** on the passenger badge, to find your bus at a glance (outside dungeons: the game hides positions there).
- The panel shows who has Pedibus and which version. A **Send link** button helps friends who don't have it yet.
- A **Follow the driver** key binding restarts auto-follow. An alert warns you when it breaks.
- `/pedibus debug` command to troubleshoot connection issues between players.

### Changed
- The panel shows "X's bus" next to passengers. Picking a passenger puts you on their driver's bus instead of starting a second one.
- **Roll call**: passengers get a **Follow** button to resume auto-follow in one click, others get a new invitation.
- In dungeons, distance shows "in range" or "out of range" instead of "?".

### Fixed
- Cross-realm groups: WoW Forever writes names as "Name Realm", which prevented players from being recognized.
- Lua error when hovering some names in the panel.
- Clear message when the game blocks messages (boss fights, mythic keystones, PvP).
