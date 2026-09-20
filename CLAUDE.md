# LibLocaleOverride -- Claude Instructions

Embeddable WoW library, distributed as an **external dependency** for the TOG
addon suite (15+ addons). Lua 5.1, LibStub. Provides a **per-addon,
runtime-switchable UI language override** plus a **bundled-font manager** for
scripts WoW can't render.

## Always

- **LibStub library pattern** -- `local MAJOR, MINOR = "LibLocaleOverride-1.0", N`; `local lib = LibStub:NewLibrary(MAJOR, MINOR); if not lib then return end`. All persistent state on `lib.*`, initialized `lib.x = lib.x or {}` so it survives an in-place upgrade when a consumer ships a newer copy. **Bump `MINOR` on every API/behavior change.**
- **Base library -- no dependencies but LibStub** -- vendored at `libs\LibStub\LibStub.lua`, loaded first in the TOC. Do not add Ace3 or other libs; consumers bring their own.
- **Keep ALL locale tables** -- the whole point vs AceLocale is runtime switching, which needs every registered table retained (AceLocale discards non-active ones). Merge enUS baseline + active locale **in place**, so a captured `lib:GetLocale(addon)` table stays valid after a switch.
- **Per-addon, never global** -- never touch the `GAME_LOCALE` global or anything that affects addons you didn't write. Each consumer's override is fully isolated.
- **Storage stays with the consumer** -- the lib does not own a SavedVariable; consumers pass `getStore`/`setStore` via `SetStore`. Don't add a SavedVariables declaration.
- **Locale strings must be raw UTF-8** -- Lua 5.1 has no `\uXXXX`; write literal UTF-8 in any test/doc strings.
- **Single multi-version TOC** -- one `LibLocaleOverride.toc`, comma-separated `## Interface:` covering every flavor (like LibDBIcon). Update the numbers when clients bump; never split into per-flavor TOCs and never hand-edit `## Version` (the packager fills `@project-version@` from the tag).
- **Reference consumer** -- FastGuildInvite (`..\fastguildinvite`) is consumer #1; its `FGI_Constants` `activeL` / `RebuildLocale` / `ApplyLocaleOverride` logic is the port source. Read it before changing the merge logic.
- **Docs (REQUIRED after any behavior change)** -- update **`CHANGELOG.md`** (technical; prepend a version section) and **`docs/Curseforge_Description.html`** (Recent Updates, keep the last 5 patches). Keep `CHANGELOG.md` under ~120,000 chars; archive the oldest sections to `CHANGELOG_ARCHIVE.md` past that.
- **Release tags** -- annotated, exact format `LibLocaleOverride-vX.Y.Z`; push the tag to trigger the BigWigs packager.
- **Comments** explain the non-obvious "why"; update stale comments in blocks you edit. **Fix lint/compile errors automatically.**
- **Minimal, direct tool use** -- edit with the file tools; reserve the shell for git / build / syntax-check.

## The inbox is the channel -- there are no boards

This workspace is onboarded to **writ** (`LibLocaleOverride@classic_era`). Peer-review findings,
consumer contracts and harness requests all travel as writ inbox documents, and writ lists what is
waiting on every prompt. Read them with `{"tool":"review"}` on the desk (`writ desk path`), reply
with `action:"reply"`, close your side with `action:"state"`.

- **The three markdown boards (`docs/AUDIT.md`, `docs/LIBRARY_CONTRACTS.md`,
  `Tests/HARNESS_CONTRACT.md`) were imported into the inbox and deleted on 2026-09-20.** Their text
  is in git history (last present at `3bebfe1`); the reasoning that still governs code is in the code
  comments, `README.md` (the Guarantees section) and the bank. Do not recreate them.
- **Ask for a review** by sending on the `audit` channel to `Peer Review`. Ask before a release, and
  again after answering a round.
- **Raise a harness gap** by sending on the `harness` channel to `WoWAPITesting`, with a local
  stand-in staged so the suite runs green today.
- **A finding is a defect we have; a contract is something we do not do yet.** Say which.
- **The auto-fit block (`ApplyFontToButton`) had THREE different defects fixed together** (audit
  findings 3, 4 and 5: a zero floor cached forever, two caches on a pooled frame never cleared, and
  fitting textless / double-anchored buttons). The tempting one-line fix for any one leaves the other
  two; `Tests/font_apply_spec.lua` pins all three.
- **The guarantee that fonting never resizes what it fonts** (README, Guarantees; delivered to
  FastGuildInvite at MINOR 16) is a promise consumers build on. Read it before changing anything in
  `ApplyFontToFrame` / `ApplyFontToButton`.
- **The `## Interface` list is asserted, not transcribed.** `Tests/toc_spec.lua` fails when the list
  lacks a value shipped by an installed consumer that hard-depends on us, or the interface of an
  active product in `.build.info`. Add the value and let the spec confirm it.

## Offline test suite

```sh
lua Tests/wowapi/run.lua                                  # whole suite, from the addon root
lua Tests/wowapi/coverage.lua LibLocaleOverride-1.0.lua LibLocaleOverride-LanguageNames.lua \
    LibLocaleOverride-AceGUI-1.0.lua LibLocaleOverride-RTL-1.0.lua
```

- **Do NOT install or run `busted`.** `.busted` is a shim kept only so an accidental `busted` cannot
  collect the harness's own specs. The runner above needs nothing but Lua 5.1.
- **100% line coverage, and it stays there.** Coverage means every line ran; it says nothing about
  whether the behaviour is right.
- **Write the spec for how the code SHOULD behave**, then fix the code where it diverges. A spec that
  ratifies current behaviour is worth less than none, because it makes the eventual fix look like the
  regression. `Tests/font_apply_spec.lua`'s header names the auto-fit cases it deliberately does not
  assert, and why -- keep that list honest.
- **`Tests/toc_spec.lua` reads OUTSIDE the repo on purpose** -- sibling consumer TOCs and the WoW
  root's `.build.info` -- and fails if either set is empty. It runs from the installed addon folder,
  which is the only place this suite is ever run.
- **The library loads through the harness's `env/libs.lua`**, from this working tree. Never vendor a
  copy into `Tests/`.
- **Never edit `Tests/wowapi`** -- it is a submodule checkout shared by ~20 addons and the next pull
  discards your change. Raise it on the inbox (`harness` channel, to `WoWAPITesting`) and stage a
  local stand-in that yields to the real thing.
- **Text METRICS in the harness are a deliberate fiction.** Use `frames.setStringWidth(text, w)` to
  drive width logic; never assert an absolute painted width.
