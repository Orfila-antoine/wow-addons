# wow-addons

Monorepo of WoW addons for **WoW Forever** (client `wowf` 1.60.1, `## Interface: 16001`).

- `addons/<Addon>/`: one folder per addon (TOC, `CHANGELOG.md`, sources, tests).
- `shared/games/`: game plugins common to several addons, copied into each addon at build time.
- `tools/`: build and local deployment.
- `docs/<addon>.md`: CurseForge page of each addon (summary, gallery, description).

Local install: `F:\Wow\World of Warcraft\_forever_\Interface\AddOns`. Never touch anything else in the WoW folder, except reading `WTF\...\SavedVariables`.

## Constraints

- Published addons have **no external dependency**: shared code is copied in at build time.
- Each addon has its own loading engine; games are plugins.
- Game logic is kept apart from UI so it runs outside the client (tests use a fake client, `tests/wow.lua`).
- All code lives in the addon namespace (`local _, ns = ...`): two addons embed the same shared files.
- Target Lua 5.1 (the WoW client).

## Conventions

- **SemVer**. Tags prefixed by addon: `pedibus/v1.4.0-beta.1` (beta), `pedibus/v1.4.0` (release).
- **Conventional Commits** with scope: `feat(pedibus): ...`, `fix(games): ...`.
- One `CHANGELOG.md` per addon, [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format, **in English**, written for players.
  Add to `## [Unreleased]` with every player-visible change, during development. Never generate it at release time.
- A change in `shared/` updates the changelog of every addon that embeds it.
- `docs/<addon>.md` (English) is kept up to date during development; the owner copies it to CurseForge by hand.
- The TOC `## Version` is injected at build time, never written by hand.

## Safety

- Never publish a **release** to CurseForge without the owner's explicit confirmation. Betas only when asked.
- The CurseForge token lives only in the GitHub secret `CF_API_KEY`: never in a file, never printed.
- No force push, no tag or release deletion without asking.
- If a step fails or an assumption is wrong, stop and explain instead of working around it.
- CurseForge app: auto-update must be off for our addons, or it overwrites dev builds with the published version.

## End of session

Summarize: what was done, what is deployed locally for tonight (addon + version), what went to CurseForge, what remains to test in game.
