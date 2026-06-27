# Lib: LocaleOverride

## [v0.3.1] (2026-06-27) — non-Latin width measurement: buttons and tabs size to the painted width

v0.3.0 introduced button auto-fit and tab fonting; this corrects how their WIDTH is
measured for complex scripts. WoW does no shaping, so `GetStringWidth` on a bundled-font
string collapses the matra/mark advances and reports far less than the width the client
actually paints — which left non-Latin button labels overflowing and the AceGUI tab strip
spilling past the window edge. LibStub `MINOR` 10 → 12; AceGUI satellite `_aceguiMinor`
2 → 4.

### Button auto-fit measures the base font too — `lib:ApplyFontToButton`

- The label width is now measured in the button's BASE (client) font as well as the
  bundled font, and the button is sized to the LARGER of the two. The base font advances
  every codepoint — a close proxy for the no-shaping painted width — whereas the bundled
  font's `GetStringWidth` under-reports it (often by ~half), so the button grew too narrow
  and the label overflowed. A Latin label measures the same in both fonts, so Latin buttons
  are never inflated. Measurement uses a dedicated UIParent-parented fontstring (font set
  before text, so the width is correct synchronously) and the fit is re-asserted on the
  next frame once the button's own label has been realized.

### Bare `.label` buttons now auto-fit — `lib:ApplyFontToButton`

- Recognises the common consumer pattern of a bare `CreateFrame("Button")` with a separate
  child `.label` fontstring and no `GetFontString()`: that label is used for the text, the
  font, and the width measurement, so those buttons grow to fit a translated label instead
  of letting it overflow. The base-font proxy falls back to the label's own font object,
  then `GameFontNormal`, when the button has no Normal font object of its own.

### Tab strip measured in the base font — `lib:AttachTabGroupFont` (`_aceguiMinor` 2 → 4)

- AceGUI sizes each tab and assigns it to a row from `GetFontString():GetStringWidth()`
  during `BuildTabs`. Measured in the bundled font it under-reported, so AceGUI over-packed
  the first row and the justified tabs overflowed the window. The tabs are now forced into
  the base font for the DURATION of AceGUI's measurement (it advances every codepoint, a
  close proxy for the painted width), then swapped back to the bundled font for display
  once the widths and rows are set — on every build (initial, AceGUI's own next-frame
  re-layout, and `SetTabs`). This supersedes v0.3.0's deferred-relayout approach.

## [v0.3.0] (2026-06-25) — native numerals, button + dropdown fonting, Latin-in-bundled-fonts

A localisation-completeness release: the pieces a fully-translated UI needs beyond
strings — locale-native numbers, buttons and native dropdowns that font (and fit)
correctly, and embedded Latin that no longer boxes. Driven by a deep Bengali pass on
the reference consumer. LibStub `MINOR` 3 → 10; AceGUI satellite `_aceguiMinor` 1 → 2.

### Native numerals — new `lib:LocalizeDigits(addon, text)`

- Converts the Western digits 0-9 in a DISPLAY string to the active locale's own
  digits, driven by the locale table itself (`L["0"]`..`L["9"]`). The backend/data
  stays Western (math, `%d`, comparisons) — only the rendered string is rewritten.
- **Markup-aware**: never touches the characters inside WoW escapes — the 8 hex bytes
  of a colour code `|cAARRGGBB`, the body of a texture `|T...|t`, an atlas `|A...|a`,
  or the data portion of a hyperlink `|H...|h` — so colours, icons and links can't be
  corrupted. Returns the string unchanged for locales with no native digits.

### Button fonting — new `lib:ApplyFontToButton(addon, button)`

- Fonts a templated button (UIPanelButtonTemplate, AceGUI, etc.) across **every**
  visual state — Normal / Highlight / Pushed / Disabled. A plain fontstring re-font
  can't survive a state change: the button swaps in a per-state font OBJECT on
  hover/push, so a non-Latin label reverts to the glyph-less default and boxes the
  moment the pointer touches it. The button's stock per-state fonts are cached once so
  a Latin locale restores them exactly.
- **Auto-fit width** (built in, no opt-in): grows the button when its now-fonted label
  is wider than the width it was designed for — so a longer translation can't overflow
  — and restores the design width for a shorter one. The original width is captured as
  a floor and it only acts when the text actually exceeds it, so square icon buttons
  and already-fitting labels are left exactly as-is. `lloFitPad` tunes the padding.

### Frame walk now fonts buttons — `lib:ApplyFontToFrame`

- The recursive font walk applies `ApplyFontToButton` to every Button child it
  encounters, so a single `ApplyFontToFrame` fonts **every** button under a frame (all
  states, plus the width auto-fit) automatically — no per-button call sites. A textless
  (icon) button is a no-op.

### Dropdown list fonting — new `lib:AttachDropDownFont(addon, dropdown)`

- Fonts the OPEN list of a Blizzard `UIDropDownMenu`. The list lives in the SHARED
  global `DropDownList1` / `DropDownList2` frames (parented to UIParent, not the
  consumer's window), so a normal frame walk never reaches it — which is why a
  dropdown's collapsed/selected text fonted but its open items boxed.
- Register each dropdown once; a single global hook on `ToggleDropDownMenu`
  (taint-safe `hooksecurefunc`) fonts the open list — routing each item through
  `ApplyFontToButton` so it renders in every state. Scoped via
  `UIDROPDOWNMENU_OPEN_MENU` so the hook only fonts a list when a REGISTERED dropdown
  is the one open; other addons' dropdowns (and the shared list buttons) are untouched.

### Script-detection fix — `FontForText` (the danda)

- Strip the danda (U+0964 "।") and double danda (U+0965 "॥") BEFORE script detection.
  They're sentence punctuation SHARED across Bengali / Gurmukhi / Devanagari and other
  North-Indic scripts, yet Unicode files them in the Devanagari block — so a Bengali or
  Punjabi line ending in "।" matched Devanagari (checked first in `scriptOrder`) and
  rendered in the Devanagari font, which has no Bengali glyphs → every letter boxed.

### Bundled fonts now carry Latin

- Merged the Latin range into the seven non-Latin script fonts (Bengali, Devanagari,
  Arabic, Gurmukhi, Hebrew, Tamil, Telugu). Without it, English brand names,
  slash-commands and any other embedded Latin inside a translated string rendered as
  boxes — the script-only subsets had no Latin glyphs. Each font keeps its own OFL.

### AceGUI tab colours (`LibLocaleOverride-AceGUI-1.0.lua`, `_aceguiMinor` 1 → 2)

- Tabs fonted with a bundled (Indic / CJK / Arabic) font kept the **gold** (unselected)
  / **white** (selected) distinction. AceGUI drives that entirely through the per-state
  font OBJECTS — an enabled tab paints in its Normal object (gold), the selected tab is
  disabled with its Disabled object forced to `GameFontHighlightSmall` (white).
  Collapsing all states to one colourless bundled object made a deselected tab stay
  white; now two colour-matched bundled objects (gold + white) are applied and
  re-asserted after every `SelectTab`.

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
