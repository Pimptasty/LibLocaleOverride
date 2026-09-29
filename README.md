# LibLocaleOverride

Per-addon, runtime-switchable **UI language override** for World of Warcraft
addons, plus a **bundled-font manager** for scripts the WoW client can't render
(e.g. Thai). Embeddable via LibStub.

## Status

**v0.3.5** -- runtime per-addon language override; a script-aware bundled-font
manager covering most of the world's scripts (with Latin merged in, so embedded
brand/command text never boxes); **locale-native numerals**; full **button** and
**native-dropdown** fonting that sizes to the width a non-Latin label is actually painted
at; a **client-locale resolver** (`GetClientLocale`) for chat/print output in a
chat-renderable language; right-to-left support (Hebrew + Arabic / Persian / Urdu,
with Arabic contextual shaping); and optional AceGUI integration -- a two-column language
picker and an automatic tab-font handler. Consumers that hard-depend on it: **FastGuildInvite**
(the first) and **Dibs**, on every client each one ships for, WoW: Forever included.

LibStub `MINOR` **17**. The three satellite files carry their own version stamps and
upgrade independently of the core: `_aceguiMinor` 4, `_rtlMinor` 3, `_namesMinor` 1.

**v0.3.5 is a fix for WoW Forever and Retail.** Those clients hand addons _secret_ strings
for some Blizzard text (tooltip lines, for example), and tainted code errors on comparing
one. Every entry point that reads text now asks `issecretvalue` first and leaves a secret
untouched; Classic clients have no such function and behave exactly as before. No API
change.

v0.3.4 added no API and changed no behaviour. It widened the TOC's `## Interface` list to
cover World of Warcraft: Forever (`16001`) and Retail 12.1 (`120100`) -- a hard dependency
the client flags out of date stops the consumer loading -- and adds a spec that asserts
the list against the installed consumers and client rather than transcribing it. v0.3.3
was the correctness release before it: an offline test suite at 100% line coverage and
three behaviour fixes (retail's `|cn<NAME>:` colour tokens, Urdu `NOON GHUNNA` shaping,
and the button auto-fit no longer writing widths onto buttons it has no business sizing).

Supported clients (one TOC, comma-separated): Classic Era, Anniversary / TBC, Wrath,
Cataclysm, Mists of Pandaria Classic, Retail (Midnight), and WoW: Forever.

## Why not AceLocale-3.0 / AddonLocale?

- **AceLocale** keeps only the client-locale table + the default and resolves the
  language **once** at load (`GetLocale()` / `GAME_LOCALE`). It can't switch a
  language at runtime, and `GAME_LOCALE` is a single global that retargets **every**
  AceLocale addon at once -- antisocial toward addons you didn't write.
- **AddonLocale** is a standalone, **global** user wrapper around `GAME_LOCALE`.
  Same global limitation; no per-addon picker; no fonts.
- Neither handles **fonts** for non-renderable scripts.

This library keeps **every** registered locale table, merges them on demand
(enUS baseline + chosen locale on top), **per addon**, switchable live -- so
picking Dutch for one addon never touches another. The locale-merging engine is an
original implementation.

## API

```lua
local LLO = LibStub("LibLocaleOverride-1.0")

-- locale
LLO:RegisterLocale(addon, code, tbl, isDefault)   -- keeps ALL tables
LLO:SetStore(addon, getFn, setFn)                 -- bind your SavedVariable
LLO:ApplyStored(addon)                            -- restore override early at login
LLO:SetOverride(addon, code)                      -- "auto" or a locale code
LLO:GetLocale(addon)                              -- live merged table (read L[key] at build time)
LLO:GetClientLocale(addon)                        -- merged table for the CLIENT locale, ignoring the override
LLO:GetActiveCode(addon)                          -- resolved code; GetOverride / GetAvailable / HasLocale
LLO:UnregisterAddon(addon)                        -- forget everything for an addon

-- fonts
LLO:GetFont(addon)                                -- bundled font path for the active locale
LLO:FontForText(addon, text)                      -- font for a string by its own script
LLO:FontObject(path, size, flags)                 -- cached Font OBJECT for a path (nil if the file fails)
LLO:ApplyFontToString(fs, addon, opts)            -- the single font applicator
LLO:ApplyFontToFrame(addon, frame)                -- re-font a frame's strings + buttons by script
LLO:ApplyFontToButton(addon, button)              -- font a button across all states (+ auto-fit width)
LLO:AttachDropDownFont(addon, dropdown)           -- font a Blizzard UIDropDownMenu's open list
LLO:LocalizeDigits(addon, text)                   -- Western digits -> the locale's own (markup-aware)
LLO:RegisterFont(addon, code, fontPath)           -- per-addon bundled-font override
LLO:RegisterManagedFontString(addon, fsOrFn)      -- auto-refont on switch; UnregisterManagedFontString to drop

-- events / text
LLO:RegisterCallback(addon, fn)                   -- refresh on switch, no /reload; UnregisterCallback to drop
LLO:SplitToBytes(text, maxBytes)                  -- byte-aware chat chunking (≤255 default)

-- AceGUI integration (LibLocaleOverride-AceGUI-1.0)
LLO:RegisterAceGUIDropdown(addon, opts)           -- font-aware dropdown / two-column language picker
LLO:AttachTabGroupFont(addon, tabGroup, opts)     -- keep a TabGroup's tabs fonted for the active locale
LLO:AllLanguageCodes()                            -- every code the library has names for, incl. "auto"
LLO:LanguagePickerValues(codes)                   -- code -> native endonym, for a picker's value table
LLO:IsAnyPulloutOpen() / LLO:OnPulloutClose(fn)   -- defer a panel refresh while a list is open
LLO:HookCleanRelease(widget, restoreFn, key)      -- restore a pooled widget to stock on release

-- right-to-left (LibLocaleOverride-RTL-1.0)
LLO:Shape(text)                                   -- logical -> visual order; no-op on non-RTL text (see limit below)
LLO:IsRTL(addon) / LLO:IsRTLCode(code)            -- is the active locale / a given code right-to-left
```

## Guarantees

Promises the library has made to consumers. These are contracts, not implementation
details -- they are safe to build on, and changing one is a breaking change.

### Fonting never resizes what it fonts

`ApplyFontToFrame` and `ApplyFontToButton` change how text **renders**. They never change
a widget's **size, position, anchors, parent or layout** -- with exactly one exception.

**The exception:** a button with **all** of a non-empty label, `SetWidth`/`GetWidth`, and a
width **not** derived from two opposing horizontal anchors may have its **width** set, and
nothing else. Never its height, points or parent. The width is only ever raised above the
button's own captured design width or restored back down to it, so a button can never end
up narrower than it was built.

**Two opt-outs, both honoured:** give the button no label, or anchor it on both horizontal
edges. (`button.lloFitPad` tunes the padding but does **not** exempt it.)

### Other invariants

- **`GetLocale(addon)` merges in place.** Capture the table once; it stays valid across a
  runtime switch. Read `L[key]` at build time, not at file scope.
- **Per addon, never global.** The library never touches `GAME_LOCALE` or anything
  affecting addons you did not write.
- **The library owns no SavedVariable.** Storage stays with the consumer via `SetStore`.
- **An in-place upgrade is safe.** All state hangs off `lib.*` and is initialised
  `lib.x = lib.x or {}`, so a consumer shipping a newer copy takes over without loss.

## Easy to get wrong

- **`Shape` goes AFTER `format()`, never on the raw template.** Reversing `%d` yields `d%`,
  which no longer formats. Shape the filled string.
- **`Shape` costs nothing on non-RTL text.** Text with no RTL character is returned
  byte-identical, so wrap every display string rather than branching on locale. **One known
  limit:** brackets are always treated as RTL-context, so a Latin phrase that _contains_ a
  bracket pair next to RTL text -- `Foo (Bar) <hebrew>` -- comes back with its pieces
  re-ordered. A lone parenthetical (`<hebrew> (Beta)`) is fine. This is the UI-label subset
  of BiDi, not the embedding-level algorithm.
- **`LocalizeDigits` is markup-aware** and will not rewrite digits inside `|cAARRGGBB`,
  retail's `|cn<NAME>:` named colour tokens, `|T..|t`, `|A..|a` or `|H..|h`. Pass it whole
  display strings; do not pre-split around escapes.
- **`ApplyStored` early at login** restores the override before your first `GetLocale`.
- **Secret text is skipped, not fonted.** On WoW Forever / Retail, a FontString whose text
  is a secret value (Blizzard's tooltip lines, for example) is left untouched by
  `ApplyFontToFrame` / `ApplyFontToString` / `ApplyFontToButton`, and `FontForText`,
  `LocalizeDigits`, `Shape` and `SplitToBytes` hand a secret back without reading it. Walking
  a Blizzard-owned frame is therefore safe, but nothing on it gets re-fonted.

## Development

Offline test suite, run locally by hand -- there is no CI, by design:

```sh
lua Tests/wowapi/run.lua
lua Tests/wowapi/coverage.lua LibLocaleOverride-1.0.lua LibLocaleOverride-LanguageNames.lua \
    LibLocaleOverride-AceGUI-1.0.lua LibLocaleOverride-RTL-1.0.lua
```

242 specs, **100% line coverage on all four shipped files**. It needs nothing
but a Lua 5.1 interpreter; `Tests/wowapi` is the shared
[WoWAPITesting](https://github.com/Pimptasty/WoWAPITesting) harness as a submodule, and
`Tests` is excluded from the packaged zip. The library is loaded from this working tree
through the harness, never vendored, so the bytes under test are the bytes that ship.

The `## Interface` list in the TOC is asserted rather than transcribed: `Tests/toc_spec.lua`
fails if the list lacks any value shipped by an installed consumer that hard-depends on this
library, or the interface number of any active product in the WoW install's `.build.info`.

Peer-review findings, consumer contracts and harness requests travel through the writ inbox
(see `CLAUDE.md`). The markdown boards that carried them until 2026-09-20 live in git history.

## Credits

The locale-merging core is an original implementation. Bundled assets and adapted
data:

- **Fonts** -- Google Noto (Latin/Greek/Cyrillic, Arabic, Hebrew, Devanagari, Bengali,
  Gurmukhi, Tamil, Telugu, Japanese, Korean, Chinese Simplified & Traditional) and
  Sarabun (Thai), all under the SIL Open Font License 1.1; each ships its `OFL.txt`
  under `fonts/<Script>/`.
- **Arabic / Persian / Urdu reshaping tables** -- the base-letter -> presentation-form
  mappings are generated from the Unicode Arabic Presentation Forms via
  [python-arabic-reshaper](https://github.com/mpcabd/python-arabic-reshaper) (MIT, ©
  Abdullah Diab); the reshaping/ligature approach was seeded by
  [Arabic_Reshaper_LUA](https://github.com/DiNaSoR/Arabic_Reshaper_LUA) (MIT). The
  shaping and BiDi logic in `LibLocaleOverride-RTL-1.0.lua` is our own.

## License

[MIT](LICENSE).
