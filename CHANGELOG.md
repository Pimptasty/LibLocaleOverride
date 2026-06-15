# Lib: LocaleOverride

## [v0.2.0] (2026-06-14) — RTL, full script coverage, AceGUI picker + tab handler, hardening

A large feature release: everything from v0.1.0 plus right-to-left support, the
rest of the world's scripts, drop-in AceGUI components, and a full robustness pass
for use as a shared foundation across the addon suite. LibStub `MINOR` 1 → 3.

### Right-to-left — new `LibLocaleOverride-RTL-1.0.lua`

- **Hebrew + Arabic / Persian / Urdu.** `lib:Shape(text)` converts logical-order
  RTL text into the visual order WoW's strictly-LTR engine needs (WoW does no BiDi
  and no Arabic shaping itself); LTR text returns unchanged, so any display string
  can be wrapped unconditionally.
- **Arabic contextual reshaping** to isolated/initial/medial/final presentation
  forms with LAM-ALEF ligatures (tables generated from python-arabic-reshaper, MIT
  — see README credits).
- **BiDi visual reordering** keeps embedded LTR runs (numbers/Latin) readable and
  **mirrors brackets** so parentheses wrap RTL content the right way round.
- API: `lib:Shape`, `lib:IsRTL(addon)`, `lib:IsRTLCode(code)`.

### Full script coverage (bundled fonts)

- Added Noto Sans **Latin-extended** (Vietnamese/Hausa/Turkish), **Cyrillic**,
  **Hebrew**, **Arabic**, **Gurmukhi** (Punjabi), **Japanese**, **Korean**,
  **Chinese Simplified** and **Chinese Traditional** — on top of v0.1.0's Thai +
  Devanagari/Bengali/Tamil/Telugu. Each ships its `OFL.txt`.
- CJK/Hangul are bundled (not left to the client) because a non-native client
  can't render them and AceGUI's raw tab restyle drops the glyph-fallback chain.
- `lib.localeScript` maps each override locale to its bundled script;
  `lib.scriptOrder` makes `FontForText` deterministic (Latin matched last).

### One font applicator

- `lib:ApplyFontToString(fs, addon, opts)` — the single site every font path now
  funnels through (frame walk, managed strings, dropdown, tab strip). Bundled
  fonts are applied as cached Font **OBJECTS** via `SetFontObject`, never raw
  `SetFont` on a live string (which disables WoW's glyph fallback and lingers on
  pooled frames). Font loads are verified with `GetFont()`, not `SetFont`'s
  unreliable boolean return.

### AceGUI integration (`LibLocaleOverride-AceGUI-1.0.lua`)

- **`lib:AttachTabGroupFont(addon, tg)`** — call once; keeps a TabGroup's tab
  buttons fonted for the active locale across SetTabs/BuildTabs/SelectTab and
  hover/select state changes (a tab is a Button whose font comes from its
  Normal/Highlight/Disabled font objects), and resets to stock fonts on a Latin
  locale or on release.
- **Two-column language picker** —
  `RegisterAceGUIDropdown(addon, { languagePicker = true })`: column 1 is each
  language's name in the *active* locale, column 2 its native endonym, each in its
  own script, sorted A-Z, RTL-shaped at render. Backed by `lib.languageNames`
  (canonical names) + `lib:LanguagePickerValues` / `lib:AllLanguageCodes`.
- **Refresh-deferral hooks** `lib:IsAnyPulloutOpen()` / `lib:OnPulloutClose(fn)` so
  a consumer can hold an AceConfig `NotifyChange` until the open list closes
  instead of yanking it shut.
- **`lib:HookCleanRelease(widget, restoreFn, key)`** — the one place pooled-widget
  cleanup routes through; restores stock state on release so the globally-shared
  AceGUI pools (items, pullout, tab buttons) never carry our fonts into another
  addon.

### Text utility

- `lib:SplitToBytes(text, maxBytes)` — byte-aware chunking (≤255 by default) at
  whitespace/punctuation; byte (not character) count is what matters for
  multi-byte scripts on the chat wire.

### Foundation hardening

- Teardown API: `lib:UnregisterManagedFontString`, `lib:UnregisterCallback`,
  `lib:UnregisterAddon` (transient frames / test resets).
- `GetActiveCode` / `GetFont` lazy-build, so they're correct before a first
  `GetLocale` / `ApplyStored`.
- Managed re-font is `pcall`-isolated so one broken consumer can't abort a switch;
  `RegisterCallback` dedups; `SetStore` asserts function-or-nil; the frame walk has
  a recursion-depth guard.
- **Satellite version stamps** (`_aceguiMinor` / `_rtlMinor` / `_namesMinor`) so an
  older embedded copy of a satellite file loading last can't regress a newer one.

## [v0.1.0] (2026-06-12) — first release

A per-addon, runtime-switchable UI language override plus a script-aware
bundled-font manager, embeddable via LibStub. Reference consumer: FastGuildInvite.

- **Per-addon locale override.** Keeps every registered locale table and merges
  them on demand (enUS baseline + the chosen language on top, so a partial
  translation still falls back), per addon and switchable live — picking a
  language for one addon never touches another. API: `RegisterLocale`,
  `GetLocale`, `GetActiveCode`, `GetOverride`, `GetAvailable`, `HasLocale`,
  `SetStore`, `ApplyStored`, `SetOverride`, `RegisterCallback`.
- **Script-aware bundled fonts** for scripts the WoW client can't render. One
  resolver, `FontForText`, fonts each string by its own script (UTF-8 detection),
  so a mixed-script surface (a language picker) never boxes. Ships static fonts
  under `fonts/<Script>/`: Thai (Sarabun) and Noto Sans Devanagari / Bengali /
  Tamil / Telugu. API: `GetFont`, `ApplyFontToFrame`, `RegisterFont`,
  `RegisterManagedFontString`.
- **Optional AceGUI-3.0 integration** (`LibLocaleOverride-AceGUI-1.0.lua`):
  `RegisterAceGUIDropdown(addon)` returns a font-aware `dialogControl` whose
  selected value and option list render non-Latin locales; leak-free via
  release-time font restore. No-op when AceGUI is absent.
- Single multi-version TOC (Vanilla / BCC / Wrath / Cata / Mists / Retail) à la
  LibDBIcon, vendored LibStub, MIT license, packaging + editor tooling.
