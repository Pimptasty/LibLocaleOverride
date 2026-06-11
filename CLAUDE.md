# LibLocaleOverride — Claude Instructions

Embeddable WoW library, distributed as an **external dependency** for the TOG
addon suite (15+ addons). Lua 5.1, LibStub. Provides a **per-addon,
runtime-switchable UI language override** plus a **bundled-font manager** for
scripts WoW can't render.

## Always

- **LibStub library pattern** — `local MAJOR, MINOR = "LibLocaleOverride-1.0", N`; `local lib = LibStub:NewLibrary(MAJOR, MINOR); if not lib then return end`. All persistent state on `lib.*`, initialized `lib.x = lib.x or {}` so it survives an in-place upgrade when a consumer ships a newer copy. **Bump `MINOR` on every API/behavior change.**
- **Base library — no dependencies but LibStub** — vendored at `libs\LibStub\LibStub.lua`, loaded first in the TOC. Do not add Ace3 or other libs; consumers bring their own.
- **Keep ALL locale tables** — the whole point vs AceLocale is runtime switching, which needs every registered table retained (AceLocale discards non-active ones). Merge enUS baseline + active locale **in place**, so a captured `lib:GetLocale(addon)` table stays valid after a switch.
- **Per-addon, never global** — never touch the `GAME_LOCALE` global or anything that affects addons you didn't write. Each consumer's override is fully isolated.
- **Storage stays with the consumer** — the lib does not own a SavedVariable; consumers pass `getStore`/`setStore` via `SetStore`. Don't add a SavedVariables declaration.
- **Locale strings must be raw UTF-8** — Lua 5.1 has no `\uXXXX`; write literal UTF-8 in any test/doc strings.
- **Single multi-version TOC** — one `LibLocaleOverride.toc`, comma-separated `## Interface:` covering every flavor (like LibDBIcon). Update the numbers when clients bump; never split into per-flavor TOCs and never hand-edit `## Version` (the packager fills `@project-version@` from the tag).
- **Reference consumer** — FastGuildInvite (`..\fastguildinvite`) is consumer #1; its `FGI_Constants` `activeL` / `RebuildLocale` / `ApplyLocaleOverride` logic is the port source. Read it before changing the merge logic.
- **Docs (REQUIRED after any behavior change)** — update **`CHANGELOG.md`** (technical; prepend a version section) and **`docs/Curseforge_Description.html`** (Recent Updates, keep the last 5 patches). Keep `CHANGELOG.md` under ~120,000 chars; archive the oldest sections to `CHANGELOG_ARCHIVE.md` past that.
- **Release tags** — annotated, exact format `LibLocaleOverride-vX.Y.Z`; push the tag to trigger the BigWigs packager.
- **Comments** explain the non-obvious "why"; update stale comments in blocks you edit. **Fix lint/compile errors automatically.**
- **Minimal, direct tool use** — edit with the file tools; reserve the shell for git / build / syntax-check.
