# LibLocaleOverride — Copilot Instructions

Embeddable WoW library (LibStub). Lua 5.1. Per-addon, runtime-switchable UI
language override + bundled-font manager.

## Always

- **LibStub registration** — `local lib = LibStub:NewLibrary(MAJOR, MINOR); if not lib then return end`. Keep all state on `lib.*` tables initialized with `lib.x = lib.x or {}` so it survives an in-place library upgrade. Bump `MINOR` on every API/behavior change.
- **Base library — no deps but LibStub** — vendored at `libs\LibStub\LibStub.lua` and loaded first in the TOC. Don't add Ace3 or other libraries; consumers bring their own.
- **Keep EVERY registered locale table** — the whole point vs AceLocale is runtime switching, which needs all tables retained. Merge the enUS baseline + active locale on demand, in place.
- **Per-addon, never global** — never touch `GAME_LOCALE` or anything that affects other addons; each consumer's override is isolated.
- **Locale strings must be raw UTF-8** — Lua 5.1 has no `\uXXXX`. Any non-ASCII is literal UTF-8.
- **Single multi-version TOC** — one `LibLocaleOverride.toc` with a comma-separated `## Interface:` line for every flavor (like LibDBIcon). Never split into per-flavor TOCs; never hand-edit `## Version` (the packager fills `@project-version@` from the tag).
- **Comments** explain the non-obvious "why"; update stale comments in any block you edit. Fix lint/compile errors automatically.
- **Docs** — after a behavior change, update `CHANGELOG.md` (technical) and `docs/Curseforge_Description.html` (Recent Updates, last 5 patches).
- **Release tag** — annotated `LibLocaleOverride-vX.Y.Z`.
