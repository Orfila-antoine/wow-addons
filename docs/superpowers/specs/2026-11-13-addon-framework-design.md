# Addon framework: shared core, separate addons

Status: draft, awaiting owner approval.

## Intent

Publish one addon without redeploying the others, each with its own version, while sharing a common core (games engine, group messaging, locales helpers).

## Goals

- Each addon has its own version, tag (`<addon>/vX.Y.Z`), changelog, CurseForge project and release run.
- Shared code is written once, in `shared/`, and copied into each addon at build time.
- Two addons loaded together never collide (everything goes through `local _, ns = ...`).

## Non-goals

- Separate GitHub repositories per addon.
- A shared library addon that players install separately (violates "no external dependency").
- Automatic re-release of every addon when `shared/` changes.

## Approaches

| | Approach | Trade-off | Decision |
|---|---|---|---|
| A | One repo, one tag per addon, `shared/` copied at build | No sync between repos; a `shared/` change ships with each addon's next release | **Chosen** |
| B | One repo per addon + core repo as submodule/subtree | Every core fix is propagated by hand to each repo | Rejected: more work, no gain |
| C | Core published as its own library addon | Players install two addons | Rejected: external dependency |

## Design

- `addons/<Addon>/` holds what is specific to the addon; `shared/<module>/` holds the core.
- Each addon declares the shared modules it embeds in a build list (e.g. `addons/<Addon>/build.txt`); the build copies them into the addon folder and inserts them into the TOC before the addon's own files.
- The build is the same script locally (`tools/deploy.ps1`) and in CI (release): same files, only `## Version` differs (`X.Y.Z-dev+<sha>` locally, tag version in release).
- A `shared/` change adds an entry to the `[Unreleased]` section of every addon that embeds it.

## Left to the builder

- Exact boundary between core and Pedibus (`Games.lua`, messaging, `charName`), decided when the second addon (WaitingGames) starts.
- Splitting shared game strings out of `Locales/*.lua`.
