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

## The three boards -- READ THEM AT SESSION START

Each is a two-way, **append-only** conversation between sessions that never share a context window.
Nobody edits, re-titles, re-orders or moves what is already there -- not even their own earlier text.
A response is a block appended **directly under** the thing it answers. This is enforced by a
`PreToolUse` law, not merely asked for.

| File | Direction | Who raises | Who acts |
| --- | --- | --- | --- |
| [`docs/AUDIT.md`](docs/AUDIT.md) | sideways | a peer-review session | **us** |
| [`docs/LIBRARY_CONTRACTS.md`](docs/LIBRARY_CONTRACTS.md) | inbound | a consuming addon | **us** |
| [`Tests/HARNESS_CONTRACT.md`](Tests/HARNESS_CONTRACT.md) | outbound | **us** | a harness session |

- **NEVER READ STATE FROM A SUMMARY VIEW ON THESE BOARDS -- READ THE RESPONSE BLOCKS.**
  `docs/AUDIT.md`'s `Status` table `State` column and `docs/LIBRARY_CONTRACTS.md`'s `Index` table
  both **cannot be updated**: the append-only law refuses the edit, measured, twice. So every cell in
  them is the state at the moment the row was written and never after. **The same is true of the two
  lines below and of any pointer in this file.** A session read the `Index` cell saying `OPEN`, plus
  a stale line here, and reported a delivered contract as outstanding -- with both files' own
  warnings against exactly that already read in the same session. Open the blocks.
- **`docs/AUDIT.md`: findings 1 through 11 are all answered in place** as of 2026-08-25, and round 9
  is requested and unanswered. Findings 3, 4 and 5 all pointed at the auto-fit block and were **three
  different defects** fixed together; read finding 4's addendum and finding 5's opening table before
  touching that code, because the tempting one-line fix for any one leaves the other two.
- **`docs/LIBRARY_CONTRACTS.md`: request 1 is DELIVERED** (MINOR 16) -- the guarantee that fonting a
  frame never resizes what it fonts, stated in full at `:212-261` with its one exception and two
  opt-outs. **That guarantee is now a promise this library has made to consumers**: read it before
  changing anything in `ApplyFontToFrame` / `ApplyFontToButton`.
- **Ask for a review** by appending a `## Review requested -- <date> -- <round>, <why>` section to
  `docs/AUDIT.md`. That is the only trigger there is. Ask before a release, and again after
  answering a round.
- **A finding is a defect we have; a contract is something we do not do yet.** Keep them in the
  right file.

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
  assert, and why -- keep that list honest as findings 3, 4 and 5 are fixed.
- **The library loads through the harness's `env/libs.lua`**, from this working tree. Never vendor a
  copy into `Tests/`.
- **Never edit `Tests/wowapi`** -- it is a submodule checkout shared by ~20 addons and the next pull
  discards your change. Raise it in `Tests/HARNESS_CONTRACT.md` and stage a local stand-in that
  yields to the real thing.
- **Text METRICS in the harness are a deliberate fiction.** Use `frames.setStringWidth(text, w)` to
  drive width logic; never assert an absolute painted width.
