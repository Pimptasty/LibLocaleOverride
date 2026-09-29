# Lib: LocaleOverride

## [v0.3.5] (2026-09-29) -- secret strings are left untouched on WoW Forever and retail (MINOR 17)

### `FontForText` compared a secret string and raised on every tooltip a consumer's walk reached

- **The report** (FastGuildInvite, inbox `e1003283`, 19x on WoW Forever):
  `LibLocaleOverride-1.0.lua:757: attempt to compare local 'text' (a secret string value, while
  execution tainted by 'LibLocaleOverride')`, via `ApplyFontToFrame` -> `walkFonts` ->
  `ApplyFontToString` -> `FontForText`. FGI's `GameTooltip:Show` hook walked Blizzard's world-cursor
  tooltip, whose lines are secret values, and I compared the text (`text == ""`) without asking first.
  FGI has fixed its side; the library is still the one place any consumer's walk funnels through, so
  it guards once for all of them.
- **The fix:** a file-local `isSecret(v)` calls `issecretvalue` -- documented in the Forever tree's
  `FrameScriptDocumentation.lua` ("Returns true if a supplied value is a secret value"), and the
  wiki's Secret Values page confirms it is the test tainted code is meant to branch on. It is looked
  up at CALL time and feature-detected, so on Classic clients without it the check is a constant
  false and nothing changes. Every entry point that reads text now asks it first:
  - `ApplyFontToString` returns before touching the FontString at all -- not even `opts.base` -- when
    its text is secret. The text is Blizzard's, not the consumer's.
  - `ApplyFontToButton` returns before caching stock fonts, swapping state fonts or auto-fitting
    when the button's label (its fontstring, `.label`, or `GetText`) is secret. All three would
    compare or measure the text.
  - `FontForText` returns nil, `LocalizeDigits` and `lib:Shape` (RTL) return the value unchanged,
    and `SplitToBytes` returns `{}` ("won't send") for a secret.
- **Specs:** four in `Tests/font_apply_spec.lua` ("secret text"), using the harness's
  `wow.secretValue`, which raises on index / method call / concatenation. **Driven red first** with
  the guard disabled: all four raised. Note the harness cannot intercept `==` against a plain
  string, so offline the red comes from the `text:gsub` one line after the comparison the client
  refused -- same path, one operation on.
- **Version stamps:** core `MINOR` 16 -> 17, and the RTL satellite's `_rtlMinor` 2 -> 3 because
  `lib:Shape` changed. Without the second bump, an older embedded RTL copy stamped 2 that loaded
  first would win, and `Shape` would still touch a secret.
- **Suite:** 242 specs, 100% line coverage on all four shipped files.

### Dev tooling: `wow-version-replication.ps1` no longer deletes a replica whose source still exists

- Peer review from TOGProfessionMaster: an editor that saves by REPLACING a file can make it briefly
  absent, and `Sync-File`'s `Deleted` branch then removed it from every replica install. This copy
  of the script polls every 2 s rather than using `Register-ObjectEvent`, so the file came back on the
  next poll. The guard is added anyway: `Deleted` becomes `Changed` when `Test-Path` still finds the
  source. The script is dev-only (`*.ps1` is in `.pkgmeta` ignore) and does not ship.

## [v0.3.4] (2026-09-20) -- WoW Forever and Midnight 12.1 in the interface list, asserted not transcribed

No Lua behaviour changes and no `MINOR` bump: the shipped `.lua` files differ from v0.3.3 only in
comments. What changed is the TOC, the test suite, and where the project's review conversations live.

### `## Interface:` gains `16001` (WoW Forever) and `120100` (Midnight 12.1), and a spec now guards the list

- **The list is now** `11508, 11509, 16001, 20505, 20506, 30405, 38002, 40402, 50503, 50504, 110207,
  120005, 120007, 120100` -- Ace3's list plus `110207`, character-for-character LibAceGUIWidgets',
  plus `16001`. The two that matter: **`120100`** is the installed Retail client (`.build.info`:
  `12.1.0.69875`), and a hard dependency the client flags out of date stops the CONSUMER loading;
  **`16001`** is World of Warcraft: Forever (Battle.net `wow_classic_beta`, TOC suffix `_Camelot`,
  confirmed on the wiki's TOC-format page), which FastGuildInvite v2.14.0 ships a TOC for while
  hard-depending on this library. The other four (`11508`, `20505`, `38002`, `50503`) are the
  test/PTR values Ace3 carries; listing them costs nothing and keeps this list a superset of the one
  library every consumer here also loads.
- **Requested three times on the inbox** -- by the harness and LibAceGUIWidgets on 2026-09-10
  (`120100`), and by FastGuildInvite on 2026-09-20 (`16001`). Both peer-review threads made the same
  point: this list was fixed by transcription in August and was stale again within a month, so
  transcribing it again is not the fix.
- **New `Tests/toc_spec.lua` asserts the invariant instead of the values.** It reads every `*.toc`
  under the sibling AddOns folder that names `LibLocaleOverride` in `## Dependencies` /
  `## RequiredDeps` (FastGuildInvite's seven, Dibs' two) and fails if any of their interface values is
  missing from ours; and it reads the WoW root's `.build.info`, converts every ACTIVE product's
  version (`12.1.0` -> `120100`), and fails if any is missing. Both assert the source set is non-empty
  before comparing, so neither can pass by finding nothing. The version arithmetic is pinned by its
  own example. **Driven red first** by removing the two new values: both failures named the value
  and the file it came from. This library declares no `## Dependencies` (Ace3 is optional -- the
  AceGUI satellite feature-detects it), so the "superset of your own dependency" rule other libraries
  use has no floor here; the installed consumers and the client artefact are the anchor instead.

### `lib:Shape` -- the docstring said "safe to wrap around ANY string"; it now states the real limit (finding 12)

- **The finding was right that two comments in `LibLocaleOverride-RTL-1.0.lua` disagreed** -- `:296`
  promised safety for any string while `:98-99` conceded a Latin parenthetical inside RTL "would
  mirror wrong". **Measured before rewriting either, and the conceded case does not fail.**
  `<hebrew> (Beta)` shapes to `(Beta) <hebrew reversed>`, which is correct: `visualOrder` mirrors the
  bracket glyph before reversing its position, so the two cancel, and UAX#9 resolves those brackets
  to the RTL embedding direction anyway.
- **The actual limit is one step over:** brackets ALWAYS break an LTR run, so a Latin phrase that
  contains a bracket pair -- `Foo (Bar) <hebrew>` -- is split at the brackets and comes back as
  `<hebrew reversed> (Bar)Foo` plus a trailing space. Real BiDi resolves brackets between two Latin
  words to Latin and
  keeps the phrase whole. Both comments now say this; the algorithm is unchanged (the header's
  "UI-label subset of BiDi" scope stands), and `README.md`'s "safe on any string" bullet says the
  same.
- **Two new examples in `Tests/rtl_spec.lua`** pin both cases: the correct one so the finding's
  scenario cannot be re-raised from a reading, and the failing one labelled `PROBE` so that fixing the
  algorithm turns it red and that is the signal to rewrite the docstring.

### Review conversations moved from three markdown boards to the writ inbox

- **`docs/AUDIT.md`, `docs/LIBRARY_CONTRACTS.md` and `Tests/HARNESS_CONTRACT.md` are deleted.**
  Every item on them was imported into writ's inbox (peer-review to `Peer Review`, contracts to
  `fastguildinvite@classic_era`, harness to `WoWAPITesting`), the ones settled in prose on the boards
  were closed there with the reason, and the files removed. Their text is in git history at
  `3bebfe1`. The reasoning that still governs code -- the three auto-fit defects, the
  fonting-never-resizes guarantee, the absent `SetPushedFontObject` -- was already in the code
  comments, `README.md`'s Guarantees section and `Tests/llo_helpers.lua`, and `CLAUDE.md` now points
  there instead of at the boards.
- **Suite: 238 passed, 0 failed**, 100% line coverage on all four shipped files.

## [v0.3.3] (2026-08-25) -- offline test suite, 100% coverage, and the three review boards

Mostly a development-infrastructure release -- an offline test suite, three review boards, and a
dev-tooling fix -- with **two behaviour changes a player can see**: `lib:LocalizeDigits` no longer
corrupts retail's named colour tokens (finding 6), and Arabic-script text following an Urdu
`NOON GHUNNA` is now shaped correctly on every flavour (finding 11). The first is retail-only --
Classic Era, BCC and MoP are byte-for-byte unaffected, because the input it mishandles does not
exist on those clients. The second applies wherever `lib:Shape` runs.

Everything else touching a shipped file is housekeeping: two stale `## Interface:` numbers for
clients that no longer exist. Satellite stamps: `_rtlMinor` **1 -> 2**; `_aceguiMinor` 4 and
`_namesMinor` 1 unchanged.

**Every review finding on the board is now answered.** Findings 3, 4 and 5 -- the button auto-fit
block, three separate defects on one line -- are fixed below, along with 6, 7, 8, 9, 10 and 11.

### Wrath and Cata interface numbers, and why this fixes nothing you can see

- `## Interface:` Wrath `30403` -> `30405` and Cata `40400` -> `40402`. LibStub `MINOR` 14 -> 15, so
  a consumer shipping this copy still wins the load race against an embedded v0.3.2 copy.
- **Read from ten third-party addons installed on this machine, not transcribed from a changelog.**
  Cata `40402` is unanimous across DBM-Core, DBM-GUI, DBM-Azeroth, Details, Details_DataStorage,
  WeakAuras, BasicMinimap, SexyMap, ProfessionMaster and Bagnon_GuildBank. Wrath `30405` is eight of
  nine -- Bagnon_GuildBank says `30404` and is presumably a patch behind, which is recorded rather
  than smoothed over.
- **Neither client exists any more, so nobody was affected and nobody is fixed.** The four installed
  flavours are Classic Era, Anniversary, Classic Progression and Retail; the progression client is
  on MoP, already covered by `50504` since v0.3.2, and Wrath and Cata are past stops on that same
  product. The reason to make the change is not the clients -- it is that this list and its sibling
  library's were once byte-identical and had drifted apart, and drift between two files nothing
  compares is a maintenance hazard regardless of what the values mean.

### Offline test suite -- 2,809 lines of shipped Lua went from zero coverage to 100%

- **Adopted the shared [WoWAPITesting](https://github.com/Pimptasty/WoWAPITesting) harness** as the
  `Tests/wowapi` submodule, at `1f8fe09` (adoption landed on `fccefa3`; the checkout has since moved
  forward to pick up `b87c89f`, which makes `after_each` run when an example fails, and the addon's
  recorded gitlink still needs the pointer move committed). Standard fleet layout: a `.busted` shim,
  bare `Tests` in `.pkgmeta`'s `ignore:`, a new `.luacheckrc` with a `files["Tests"]` block, and spec
  globals plus `Tests/wowapi` in `.luarc.json`. Run it with `lua Tests/wowapi/run.lua` from the addon
  root; it needs nothing but a Lua 5.1 interpreter. **No CI workflow, by design** -- these run
  locally, by hand, where a failure can stop the change before it lands.
- **232 specs, 0 failed. 100% line coverage on all four shipped files** (1965/1965), measured with
  the harness's `coverage.lua` rather than estimated: `LibLocaleOverride-1.0.lua` 469/469,
  `-AceGUI-1.0.lua` 249/249, `-LanguageNames.lua` 1061/1061, `-RTL-1.0.lua` 186/186. Adoption landed
  at 215 specs and 1935 lines; the rest are the finding fixes below. Seven spec files
  covering the merge and override resolution, script routing and font application, the RTL reshaper
  and BiDi ordering, `LocalizeDigits` and `SplitToBytes`, the AceGUI dropdown / pullout / tab-group
  integration, and the shape of the 1,000-line language-name table.
- **The library is loaded through the harness's `env/libs.lua`, from this working tree -- never
  vendored**, so the bytes under test are the bytes that ship. The AceGUI specs drive the **real**
  Ace3 from the sibling install, which matters more here than usual: every defect that integration
  has ever shipped came from AceGUI's shared, global widget pools, and a model of AceGUI has no pool
  to leak through.
- **What the suite deliberately did NOT assert at adoption, and why.** Review findings 3, 4, 5 and 6
  were open at that point, so the specs drove the auto-fit only for a labelled button with a real
  design width -- the case the code gets right -- and covered only the fixed-length `|cAARRGGBB`
  form. Pinning current behaviour there would have ratified the defects and made the eventual fix
  look like the regression. **All four are now fixed below and specced**, each driven red against the
  code it fixes first.
- **An honest limit that does not go away.** A meaningful slice of this library is text MEASUREMENT,
  and the harness's text metrics are a deliberate fiction. Width logic is driven through its
  steerable oracle, so the ARITHMETIC is assertable; no spec here asserts an absolute painted width,
  and none can.

### `lib:ApplyFontToButton` no longer resizes buttons it has no business resizing (findings 3, 4, 5)

Three separate defects lived on one line of the auto-fit block, and fixing any one of them left the
other two. All three are fixed together, and the library now carries a **stated guarantee** for
consumers (`docs/LIBRARY_CONTRACTS.md` request 1): fonting a frame changes how text RENDERS and
never changes a widget's size, position, anchors or parent -- with one narrow, opt-out-able
exception for the width of a labelled, non-anchor-sized button.

- **A textless button is never measured or written.** "Fit the button to its label" is undefined with
  no label; the block used to run anyway and force such buttons back to a width captured at an
  unrelated moment. AceGUI's window status bar is a textless Button, which is how this reached
  frames no consumer ever opted in.
- **A button sized by two opposing horizontal anchors is never written.** Its width belongs to those
  edges; `SetWidth` is a conflicting instruction and corrupts the answer `GetWidth` gives every other
  reader even where the anchors win at paint time. CENTER does not count -- it constrains the
  midpoint, not an edge, so a CENTER-anchored button still owns its width.
- **A zero floor is never cached.** `GetWidth()` is 0 before layout settles and 0 is TRUTHY in Lua,
  so the old `floor or GetWidth() or 0` froze that zero for the session -- after which every label
  grew the button and it had no minimum at all. The floor is now captured lazily, only when positive,
  by whichever pass first sees a real width.
- **A cached floor is only trusted while the button is still the width we last set it to.** These
  frames are pooled: FastGuildInvite's 360px colour swatch came back as `Cancel` and was forced to
  the swatch's width. The library cannot see the owning widget, so instead of asking AceGUI it asks
  whether the button still carries what we left on it. The stock per-state font cache had the
  identical lifetime bug -- it would restore the previous occupant's fonts -- and gets the same
  treatment.
- Six specs in `Tests/font_apply_spec.lua`, **each driven red against the pre-fix code**, including
  the stale-floor scenario reproducing as `expected 80, actual 100`.

### `lib:LocalizeDigits` parses retail's named colour tokens correctly (audit finding 6)

- `|c` was parsed by FIXED LENGTH -- `|c` plus 8 hex bytes -- while every other escape in the
  function (`|T`..`|t`, `|A`..`|a`, `|H`..`|h`) is parsed to its terminator. Retail has a **second**
  `|c` form that is terminator-delimited: `|cn<NAME>:` named colour tokens
  (`Blizzard_Colors/Mainline/ColorManager.lua`), whose names are arbitrary length and may contain
  digits. `|c` now matches the others: a `n` after `|c` means "skip to the colon".
- **Two things were wrong, not one.** A name longer than the 10-byte window had **its own digits
  rewritten** to native numerals, breaking the token -- reproduced before the fix as
  `|cnLONGNAME<native 9><native 9>:`. And for a short name like `|cnIQ4:5`, the fixed skip ate ten
  bytes from the `|`, which swallowed the **visible digit after the colon** so it was never
  localized at all.
- **Classic is byte-for-byte unaffected.** The new branch keys on the byte after `|c`, and `|cn`
  does not occur anywhere in the Classic Era client, so no Classic consumer sees any change. This is
  the shape that hides from a developer whose own flavour never produces the input.
- **The name must be well-formed, not merely followed by a colon** (audit finding 10, raised against
  the first version of this fix). An unbounded search for `:` reaches a colon in ordinary prose, so
  `"|cnBROKEN Level 60: 5 items"` swallowed up to the colon after `60` and left those digits Western
  while the rest of the string was localized. `|T`, `|A` and `|H` get away with an unbounded search
  because their terminators are two bytes and never occur in prose; a bare colon is one of the
  commonest characters in UI text. The name is now matched as `^%w+:` anchored immediately after
  `|cn`.
- Four specs in `Tests/text_spec.lua`, **each driven red against the code it fixes**: the short named
  token, a 12-character name whose digits fall past the old window, an unterminated `|cn`, and the
  malformed-token-meets-prose case. LibStub `MINOR` 15 -> 16.

### Arabic shaping: `NOON GHUNNA` joins forward again (audit finding 11, `_rtlMinor` 1 -> 2)

- **The library decided "does this letter join to the next one" from the SHAPE of its form row** --
  distinct initial and medial glyphs. That is an ENCODING fact standing in for a LINGUISTIC one, and
  the comment above it claimed the two were equivalent (`iff`). They are not. Urdu's
  `U+06BA NOON GHUNNA` is joining type **D** in Unicode's `ArabicShaping.txt`, but Unicode encodes
  only its isolated and final forms -- so the row cannot show what the letter does, and the library
  read it as right-joining.
- **The corrupted letter is the NEXT one, and its correct forms all exist.** `U+06BA U+0628` emitted
  `BEH ISOLATED` where `BEH FINAL` is correct; a `LAM+ALEF` ligature after it took its unjoined glyph.
  Both call sites are fixed by one explicit override table (`FORCE_DUAL`), so the predicate now says
  which of the two properties it is measuring instead of conflating them.
- **`FORCE_DUAL` is the complete set, not a sample.** All 76 rows were checked against
  `ArabicShaping.txt` -- fetched to disk, not read through a summariser -- and exactly one disagrees
  with the inference. The full 312-codepoint verification of the form tables themselves (76 letters
  x 4 forms, plus 8 ligatures) came back **correct and complete**, with no letter missing.
- Five specs in `Tests/rtl_spec.lua`, driven red first. They assert against **Unicode's** joining
  types rather than the library's own tables, sweep the whole `U+0600-U+06FF` block so a letter added
  to the form table without a joining type turns the suite red, and probe through `lib:Shape` alone
  -- no library internal was exposed to make the test possible.

### The dev-sync script skips ALL dotfiles now (audit finding 7)

- `wow-version-replication.ps1`'s `$AlwaysSkip` had **no general dotfile rule** -- only four
  enumerated git paths -- so the two dotfiles this release adds, `.busted` and `.luacheckrc`,
  replicated into the other three flavour installs. Measured with `-DryRun` before the fix, three
  `WOULD` lines each. One pattern, `'(^|\\)\.'`, replaces the four git entries and mirrors what the
  BigWigs packager itself does (`copy_directory_tree()`: `-name ".*" -prune`), so the script and the
  released zip now agree about dotfiles instead of each deciding separately.
- **`.pkgmeta` cannot express this**, which is why it went unnoticed: dot-entries in an `ignore:`
  list are no-ops to the packager, so nobody adding a dotfile thinks to list one -- and until now an
  unlisted dotfile silently replicated.
- **The seven dot-entries in `.pkgmeta` were the only thing protecting those paths**, which is the
  opposite of what I had written about them a day earlier. `.vscode/tasks.json` is the one that
  matters: it launches the dev-sync watcher on folder open, so replicating it would install a second
  watcher into another flavour's install. They are kept.
- Verified after the fix: every dotfile `[skip]`s, and everything in the released zip -- the four
  Lua files, the `.toc`, `LICENSE`, `README.md`, `CHANGELOG.md`, `fonts/**` and
  `libs/LibStub/LibStub.lua` -- still copies.

### Three review boards, and pointers to them from `CLAUDE.md`

Each is a two-way, append-only conversation between sessions that never share a context window.

- **`docs/LIBRARY_CONTRACTS.md`** -- new. The INBOUND board: what a consuming addon asks of this
  library. Opened with the rule this library needed stating, because it is an external dependency of
  the whole suite: **consumers request, LibLocaleOverride authors.** A consumer must never add a
  locale, a script matcher or a bundled font by editing this library from its own repo. It also
  records that adding a language is a contract and not a patch -- a new code needs a row of its own
  AND a cell in all 31 existing rows, which `Tests/languagenames_spec.lua` now asserts, so a
  half-done addition turns the suite red instead of shipping a picker showing English in one column.
- **`Tests/HARNESS_CONTRACT.md`** -- new. The OUTBOUND board. No open requests: adoption needed no
  stand-ins, because the harness already covered everything this library touches.
- **`docs/AUDIT.md`** -- adopted the harness's audit template and requested review round 6, which
  drew rounds 6, 7 and 8 from two independent review seats. **Findings 1 through 11 are all answered
  in place**; nothing on the board is open at the time of writing.

### Verified, and worth recording because the absence is silent

- **`Set/GetPushedFontObject` does not exist in any WoW client.** `PushedFontObject` appears **zero
  times** across the whole of the offline Blizzard source -- every flavour tree, `GlobalAPI.lua` and
  `Blizzard_APIDocumentationGenerated` -- while `SetNormalFontObject` / `SetDisabledFontObject` /
  `SetPushedTextOffset` appear 337 times across 132 files in that same tree, which is the control
  that makes the zero meaningful. The pushed state is a text OFFSET, not a font swap. So the
  `button.SetPushedFontObject and ...` guards in `lib:ApplyFontToButton` are branches the client
  never takes, and `__lloOrigFonts[3]` is always `false`. **Kept, and that is now a decision rather
  than a deferral** -- the cache is read positionally, so dropping the slot renumbers Disabled for no
  observable gain, and `if button.SetX then` is the right multi-version shape if a client ever grows
  the pair. The reasoning is now at the code as well as here, so a reader meeting the dead branch does
  not have to go looking for it.

## [v0.3.2] (2026-07-28) -- Classic Era / BCC / MoP interface bumps

Client-compatibility release. No API or behavior change.

### TOC interface versions

- The single multi-version `## Interface:` line is re-targeted at the current live builds:
  Classic Era `11508` -> `11509` (1.15.9), BCC/Anniversary `20505` -> `20506` (2.5.6), and
  MoP Classic `50503` -> `50504` (5.5.4). The library no longer reports as out-of-date on
  any of those clients.
- Verified against the installed client builds in `.build.info`, not assumed from patch
  notes. Retail stays at `120007` -- 12.0.7 is still current, there is no 12.0.8. The Wrath
  (`30403`) and Cata (`40400`) entries are for retired clients and are left as-is, as is the
  legacy retail `110207` / `120005` pair.
- LibStub `MINOR` 13 -> 14 so a consumer shipping this copy still wins the load race against
  an embedded v0.3.1 copy. The Lua is otherwise byte-identical to v0.3.1; the satellite
  files (`_aceguiMinor` 4, `_rtlMinor` 1, `_namesMinor` 1) are unchanged.

## [v0.3.1] (2026-07-01) -- non-Latin width measurement + `GetClientLocale` for chat output

v0.3.0 introduced button auto-fit and tab fonting; this corrects how their WIDTH is
measured for complex scripts, and adds `GetClientLocale` so consumers can print to the
chat frame in a renderable language. WoW does no shaping, so `GetStringWidth` on a
bundled-font string collapses the matra/mark advances and reports far less than the width
the client actually paints -- which left non-Latin button labels overflowing and the AceGUI
tab strip spilling past the window edge. LibStub `MINOR` 10 -> 13; AceGUI satellite
`_aceguiMinor` 2 -> 4.

### Button auto-fit measures the base font too -- `lib:ApplyFontToButton`

- The label width is now measured in the button's BASE (client) font as well as the
  bundled font, and the button is sized to the LARGER of the two. The base font advances
  every codepoint -- a close proxy for the no-shaping painted width -- whereas the bundled
  font's `GetStringWidth` under-reports it (often by ~half), so the button grew too narrow
  and the label overflowed. A Latin label measures the same in both fonts, so Latin buttons
  are never inflated. Measurement uses a dedicated UIParent-parented fontstring (font set
  before text, so the width is correct synchronously) and the fit is re-asserted on the
  next frame once the button's own label has been realized.

### Bare `.label` buttons now auto-fit -- `lib:ApplyFontToButton`

- Recognises the common consumer pattern of a bare `CreateFrame("Button")` with a separate
  child `.label` fontstring and no `GetFontString()`: that label is used for the text, the
  font, and the width measurement, so those buttons grow to fit a translated label instead
  of letting it overflow. The base-font proxy falls back to the label's own font object,
  then `GameFontNormal`, when the button has no Normal font object of its own.

### Tab strip measured in the base font -- `lib:AttachTabGroupFont` (`_aceguiMinor` 2 -> 4)

- AceGUI sizes each tab and assigns it to a row from `GetFontString():GetStringWidth()`
  during `BuildTabs`. Measured in the bundled font it under-reported, so AceGUI over-packed
  the first row and the justified tabs overflowed the window. The tabs are now forced into
  the base font for the DURATION of AceGUI's measurement (it advances every codepoint, a
  close proxy for the painted width), then swapped back to the bundled font for display
  once the widths and rows are set -- on every build (initial, AceGUI's own next-frame
  re-layout, and `SetTabs`). This supersedes v0.3.0's deferred-relayout approach.

### Client-locale table for chat/print output -- `lib:GetClientLocale` (`MINOR` -> 13)

- New `lib:GetClientLocale(addon)` returns a merged table (enUS baseline + the WoW **client**
  locale from `GetLocale()` on top) that **ignores the UI-language override**. It's the resolver
  for anything printed to the default chat frame: the override can select a language WoW doesn't
  ship (Bengali, Dutch, Filipino...) whose glyphs the shared chat font can't render -- and a library
  can't re-font Blizzard's chat frame for one addon without bleeding its font into every addon's
  chat. `GetLocale()` is always a WoW-supported, chat-renderable script (or the enUS baseline),
  so chat lines render correctly while the override keeps driving the in-addon UI (where the
  library controls the font). Built in place like `active`, re-folds late `RegisterLocale` calls,
  and falls back to enUS when the client locale has no registered table.

## [v0.3.0] (2026-06-25) -- native numerals, button + dropdown fonting, Latin-in-bundled-fonts

A localisation-completeness release: the pieces a fully-translated UI needs beyond
strings -- locale-native numbers, buttons and native dropdowns that font (and fit)
correctly, and embedded Latin that no longer boxes. Driven by a deep Bengali pass on
the reference consumer. LibStub `MINOR` 3 -> 10; AceGUI satellite `_aceguiMinor` 1 -> 2.

### Native numerals -- new `lib:LocalizeDigits(addon, text)`

- Converts the Western digits 0-9 in a DISPLAY string to the active locale's own
  digits, driven by the locale table itself (`L["0"]`..`L["9"]`). The backend/data
  stays Western (math, `%d`, comparisons) -- only the rendered string is rewritten.
- **Markup-aware**: never touches the characters inside WoW escapes -- the 8 hex bytes
  of a colour code `|cAARRGGBB`, the body of a texture `|T...|t`, an atlas `|A...|a`,
  or the data portion of a hyperlink `|H...|h` -- so colours, icons and links can't be
  corrupted. Returns the string unchanged for locales with no native digits.

### Button fonting -- new `lib:ApplyFontToButton(addon, button)`

- Fonts a templated button (UIPanelButtonTemplate, AceGUI, etc.) across **every**
  visual state -- Normal / Highlight / Pushed / Disabled. A plain fontstring re-font
  can't survive a state change: the button swaps in a per-state font OBJECT on
  hover/push, so a non-Latin label reverts to the glyph-less default and boxes the
  moment the pointer touches it. The button's stock per-state fonts are cached once so
  a Latin locale restores them exactly.
- **Auto-fit width** (built in, no opt-in): grows the button when its now-fonted label
  is wider than the width it was designed for -- so a longer translation can't overflow
  -- and restores the design width for a shorter one. The original width is captured as
  a floor and it only acts when the text actually exceeds it, so square icon buttons
  and already-fitting labels are left exactly as-is. `lloFitPad` tunes the padding.

### Frame walk now fonts buttons -- `lib:ApplyFontToFrame`

- The recursive font walk applies `ApplyFontToButton` to every Button child it
  encounters, so a single `ApplyFontToFrame` fonts **every** button under a frame (all
  states, plus the width auto-fit) automatically -- no per-button call sites. A textless
  (icon) button is a no-op.

### Dropdown list fonting -- new `lib:AttachDropDownFont(addon, dropdown)`

- Fonts the OPEN list of a Blizzard `UIDropDownMenu`. The list lives in the SHARED
  global `DropDownList1` / `DropDownList2` frames (parented to UIParent, not the
  consumer's window), so a normal frame walk never reaches it -- which is why a
  dropdown's collapsed/selected text fonted but its open items boxed.
- Register each dropdown once; a single global hook on `ToggleDropDownMenu`
  (taint-safe `hooksecurefunc`) fonts the open list -- routing each item through
  `ApplyFontToButton` so it renders in every state. Scoped via
  `UIDROPDOWNMENU_OPEN_MENU` so the hook only fonts a list when a REGISTERED dropdown
  is the one open; other addons' dropdowns (and the shared list buttons) are untouched.

### Script-detection fix -- `FontForText` (the danda)

- Strip the danda (U+0964 `।`) and double danda (U+0965 `॥`) BEFORE script detection.
  They're sentence punctuation SHARED across Bengali / Gurmukhi / Devanagari and other
  North-Indic scripts, yet Unicode files them in the Devanagari block -- so a Bengali or
  Punjabi line ending in `।` matched Devanagari (checked first in `scriptOrder`) and
  rendered in the Devanagari font, which has no Bengali glyphs -> every letter boxed.

### Bundled fonts now carry Latin

- Merged the Latin range into the seven non-Latin script fonts (Bengali, Devanagari,
  Arabic, Gurmukhi, Hebrew, Tamil, Telugu). Without it, English brand names,
  slash-commands and any other embedded Latin inside a translated string rendered as
  boxes -- the script-only subsets had no Latin glyphs. Each font keeps its own OFL.

### AceGUI tab colours (`LibLocaleOverride-AceGUI-1.0.lua`, `_aceguiMinor` 1 -> 2)

- Tabs fonted with a bundled (Indic / CJK / Arabic) font kept the **gold** (unselected)
  / **white** (selected) distinction. AceGUI drives that entirely through the per-state
  font OBJECTS -- an enabled tab paints in its Normal object (gold), the selected tab is
  disabled with its Disabled object forced to `GameFontHighlightSmall` (white).
  Collapsing all states to one colourless bundled object made a deselected tab stay
  white; now two colour-matched bundled objects (gold + white) are applied and
  re-asserted after every `SelectTab`.

## [v0.2.0] (2026-06-14) -- RTL, full script coverage, AceGUI picker + tab handler, hardening

A large feature release: everything from v0.1.0 plus right-to-left support, the
rest of the world's scripts, drop-in AceGUI components, and a full robustness pass
for use as a shared foundation across the addon suite. LibStub `MINOR` 1 -> 3.

### Right-to-left -- new `LibLocaleOverride-RTL-1.0.lua`

- **Hebrew + Arabic / Persian / Urdu.** `lib:Shape(text)` converts logical-order
  RTL text into the visual order WoW's strictly-LTR engine needs (WoW does no BiDi
  and no Arabic shaping itself); LTR text returns unchanged, so any display string
  can be wrapped unconditionally.
- **Arabic contextual reshaping** to isolated/initial/medial/final presentation
  forms with LAM-ALEF ligatures (tables generated from python-arabic-reshaper, MIT
  -- see README credits).
- **BiDi visual reordering** keeps embedded LTR runs (numbers/Latin) readable and
  **mirrors brackets** so parentheses wrap RTL content the right way round.
- API: `lib:Shape`, `lib:IsRTL(addon)`, `lib:IsRTLCode(code)`.

### Full script coverage (bundled fonts)

- Added Noto Sans **Latin-extended** (Vietnamese/Hausa/Turkish), **Cyrillic**,
  **Hebrew**, **Arabic**, **Gurmukhi** (Punjabi), **Japanese**, **Korean**,
  **Chinese Simplified** and **Chinese Traditional** -- on top of v0.1.0's Thai +
  Devanagari/Bengali/Tamil/Telugu. Each ships its `OFL.txt`.
- CJK/Hangul are bundled (not left to the client) because a non-native client
  can't render them and AceGUI's raw tab restyle drops the glyph-fallback chain.
- `lib.localeScript` maps each override locale to its bundled script;
  `lib.scriptOrder` makes `FontForText` deterministic (Latin matched last).

### One font applicator

- `lib:ApplyFontToString(fs, addon, opts)` -- the single site every font path now
  funnels through (frame walk, managed strings, dropdown, tab strip). Bundled
  fonts are applied as cached Font **OBJECTS** via `SetFontObject`, never raw
  `SetFont` on a live string (which disables WoW's glyph fallback and lingers on
  pooled frames). Font loads are verified with `GetFont()`, not `SetFont`'s
  unreliable boolean return.

### AceGUI integration (`LibLocaleOverride-AceGUI-1.0.lua`)

- **`lib:AttachTabGroupFont(addon, tg)`** -- call once; keeps a TabGroup's tab
  buttons fonted for the active locale across SetTabs/BuildTabs/SelectTab and
  hover/select state changes (a tab is a Button whose font comes from its
  Normal/Highlight/Disabled font objects), and resets to stock fonts on a Latin
  locale or on release.
- **Two-column language picker** --
  `RegisterAceGUIDropdown(addon, { languagePicker = true })`: column 1 is each
  language's name in the *active* locale, column 2 its native endonym, each in its
  own script, sorted A-Z, RTL-shaped at render. Backed by `lib.languageNames`
  (canonical names) + `lib:LanguagePickerValues` / `lib:AllLanguageCodes`.
- **Refresh-deferral hooks** `lib:IsAnyPulloutOpen()` / `lib:OnPulloutClose(fn)` so
  a consumer can hold an AceConfig `NotifyChange` until the open list closes
  instead of yanking it shut.
- **`lib:HookCleanRelease(widget, restoreFn, key)`** -- the one place pooled-widget
  cleanup routes through; restores stock state on release so the globally-shared
  AceGUI pools (items, pullout, tab buttons) never carry our fonts into another
  addon.

### Text utility

- `lib:SplitToBytes(text, maxBytes)` -- byte-aware chunking (<=255 by default) at
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

## [v0.1.0] (2026-06-12) -- first release

A per-addon, runtime-switchable UI language override plus a script-aware
bundled-font manager, embeddable via LibStub. Reference consumer: FastGuildInvite.

- **Per-addon locale override.** Keeps every registered locale table and merges
  them on demand (enUS baseline + the chosen language on top, so a partial
  translation still falls back), per addon and switchable live -- picking a
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
