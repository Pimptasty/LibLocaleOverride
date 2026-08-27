<!-- markdownlint-configure-file {
  "MD013": false,
  "MD024": { "siblings_only": true },
  "MD041": false
} -->
<!-- markdownlint-disable MD049 MD050 MD028 -->
<!-- Contract files quote the requesting addon verbatim and are append-only, so emphasis style is
     not this library's to normalise. Every other rule still applies.

     MD028 is disabled because the protocol PRODUCES that shape by construction: a request whose
     last paragraph is a blockquote, answered by a `> **Library response ...**` block, is two
     adjacent blockquotes with the mandatory blank line between them. It cannot be fixed after the
     fact in an append-only file, so it is settled at creation time -- the same reasoning the
     harness's docs/AUDIT_TEMPLATE.md gives for its own header. -->
# Library contracts -- LibLocaleOverride

**This is the INBOUND board: work that other addons give US.** A consuming addon (FastGuildInvite,
Dibs, TOGTools, ...) that needs something from `LibLocaleOverride-1.0` -- or from its `-AceGUI-1.0`
or `-RTL-1.0` satellites -- writes the request here, and this library answers it here.

It is the mirror image of `Tests/HARNESS_CONTRACT.md`, which is the OUTBOUND board -- what _we_ ask
of the WoWAPITesting harness. Separate boards because the direction decides who acts:

| Board | Direction | Who writes the request | Who implements |
| --- | --- | --- | --- |
| `docs/LIBRARY_CONTRACTS.md` (this file) | inbound | a consuming addon | **a LibLocaleOverride session** |
| `Tests/HARNESS_CONTRACT.md` | outbound | a LibLocaleOverride session | a harness session |
| `docs/AUDIT.md` | sideways | a peer-review session | a LibLocaleOverride session |

**A contract is not an audit finding.** A finding says _this library has a defect_ and belongs in
[`AUDIT.md`](AUDIT.md). A contract says _this library does not yet do a thing I need_. If you are not
sure which you have: a finding names a `file:line` that is wrong today, a contract names a call you
want to be able to make tomorrow.

## Why this exists

This library is an external dependency of the whole TOG suite, so a change made from inside whichever
consumer happened to be open is a change to every consumer, decided by accident. That is the same
hazard the fleet already recognises for the test harness, where the rule is that consumers _adopt_
and never _author_ -- and it bites harder here, because this library's subject matter is per-locale
behaviour that a developer on an enUS client **cannot see by playing**.

**Consumers REQUEST. LibLocaleOverride AUTHORS.** A consumer session must never add a locale, a
script matcher, a bundled font or a behaviour by editing `LibLocaleOverride-1.0.lua` (or any
satellite) from its own repo. It stages whatever unblocks it **inside its own addon**, writes the
request here, and tells the user it is waiting. A LibLocaleOverride session then implements it, specs
it, bumps `MINOR`, and answers in place.

**Stage the stand-in so it YIELDS.** A consumer's local implementation should defer to the real thing
the moment it exists, so there is no flag day:

```lua
local shape = LLO.Shape and function(t) return LLO:Shape(t) end or myLocalShape
```

**This file is APPEND-ONLY, in both directions.** Nobody edits, re-titles, re-orders or moves what
the other side wrote -- not to mark it done, not to tidy it, not to correct it. It is a conversation:
the request stays exactly as written and the answer is appended underneath. The _why_ in a request is
usually its most valuable line, because it is the account of what actually went wrong. A declined
contract is kept, with its reasoning, so nobody re-raises it in six months.

Only the **Index** table below may be rewritten; it is a view, not a record.

## How a consumer raises one

Copy the block under _Template_ into **Open**, newest first. Then stop and tell the user it is
waiting -- do not implement it here, and do not commit in this repo.

## How this library answers

Append directly under the request, never inside it:

```markdown
> **Library response -- YYYY-MM-DD -- DELIVERED | DECLINED | PARTIAL | NOT A LIBRARY GAP (MINOR N).**
> What shipped, the MINOR it landed in, the feature-detect a consumer should use, and anywhere the
> implementation differs from what was asked for, said plainly.
```

**Say WHERE the code is, and never name a version that does not exist yet.** _"Implemented and green
in the working tree, MINOR not yet bumped"_ is a complete and honest response; a consumer can read the
file and check it. Gate the IMPERATIVE, not the response: do not say _"delete your stand-in"_ until
the replacement is actually reachable by them.

Every delivery also needs, in the same session: a `CHANGELOG.md` entry, a `MINOR` bump in
`LibLocaleOverride-1.0.lua` (consumers feature-detect, so additions must degrade gracefully on an
older embedded copy), specs under `Tests/`, and -- for a satellite file -- a bump of that file's own
`_rtlMinor` / `_aceguiMinor` / `_namesMinor` stamp, which is what makes the newest copy win
regardless of load order.

**A new locale is a contract, not a patch.** Adding a language means a row in
`LibLocaleOverride-LanguageNames.lua` for the new code AND a cell for it in all 31 existing rows, plus
a `localeScript` entry if its script needs a bundled font, plus the font itself under `fonts/<Script>/`
with its `OFL.txt`. `Tests/languagenames_spec.lua` asserts the whole shape, so a half-done addition
turns the suite red rather than shipping a picker that shows English in one column.

## Index

A view, not a record -- the one part of this file that may be rewritten.

| # | Request | From | Raised | State |
| --- | --- | --- | --- | --- |
| ~~_none yet_~~ | | | | |
| 1 | A font walk must not resize what it fonts | FastGuildInvite | 2026-08-25 | **OPEN** |

Request 1 overlaps `docs/AUDIT.md` findings **4** and **5** and is deliberately not a duplicate of
them: those name what is wrong today, this asks for the guarantee that would stop a third instance.
Answering the findings without stating the guarantee leaves the next consumer with no way to know the
call is safe.

(The struck placeholder row is kept because the append-only checker reads this table like any other
line. This library's own header says the Index may be rewritten, so a LibLocaleOverride session can
drop that row from inside the repo; a consumer session cannot.)

**STATUS UPDATE -- 2026-08-25: request 1 is DELIVERED (MINOR 16).** Appended rather than written into
the row, because **the Index cannot in fact be rewritten** -- this file's header says it may be, and
that is wrong. Measured: editing request 1's `State` cell from `**OPEN**` was refused by the
append-only law with _"this Edit removes or rewrites text that is already there"_. The law makes no
exception for a table, for a status column, or for the file's own claim about itself. Exactly the
same thing is true of `docs/AUDIT.md`'s `State` column and is recorded there too.

**So read state from the RESPONSE BLOCKS, not from the Index.** The Index is a list of what was
asked, and its `State` column is the state at the moment the row was written and never after.

## Open

~~_None._~~

### A font walk must not resize what it fonts -- FastGuildInvite -- 2026-08-25

**What.** A stated guarantee that `ApplyFontToFrame` (and `ApplyFontToButton`, which it calls) changes
how text RENDERS and never changes a widget's SIZE, POSITION or layout as a side effect.

**Why this is a contract and not just findings 4 and 5.** By this file's own test, findings 4 and 5 in
[`AUDIT.md`](AUDIT.md) name a `file:line` that is wrong today, and they are filed there. This is the
call I want to be able to make tomorrow: **"font this window"** issued against a POOLED AceGUI Frame,
with a promise attached about what it will and will not touch. That promise does not exist today, and
without it a consumer cannot reason about the call at all.

**The reason a consumer cannot hold this line from its own side.** The walk reaches buttons via
`GetChildren()` (`LibLocaleOverride-1.0.lua:789-792`). That is not a set the caller chose: FGI asks for
"font this window", and the library decides what a window contains. So the caller never learns which
objects were touched, and therefore cannot audit them, exempt them, or clean up after them. Only the
library stands where that decision is made.

**What it has cost, twice, both worked around in the consumer and neither fixed:**

- **Finding 4** -- FGI's colour-swatch dialog rendered `Cancel` at roughly 4x width on the second
  open. Worked around in `Modules/FGI_Dialog.lua:209-237` by clearing `__lloFitFloor` by hand wherever
  that dialog sets a button width.
- **Finding 5** -- FGI's scan-progress fill froze at another window's width, because the walk stamped a
  `SetWidth` on AceGUI's status background: a `Button` that is textless AND anchored on both
  horizontal edges. Worked around in `GUI/MainWindow.lua:456-481` by measuring the bar's resolved
  edges instead of `GetWidth`.

Each workaround routes ONE consumer around ONE symptom, in a private file, where no other consumer can
find it or benefit from it. Any addon that fonts a pooled AceGUI Frame has the same exposure and no
reason to suspect it, which is the argument for a guarantee rather than a third workaround.

**Exact contract.**

> After `LLO:ApplyFontToFrame(addon, frame)` returns, and after any next-frame work it schedules has
> run, no descendant of `frame` has a different width, height or anchor set than it had before the
> call, EXCEPT where the library is deliberately auto-fitting a labelled button to text that would
> otherwise overflow it.
>
> Any state the library caches on a frame is either cleared when that frame is released to a pool, or
> is harmless to a later, different occupant of it.

Deliberately NOT true, so the ask is not read as wider than it is:

- **The auto-fit itself is not being asked for.** Growing a labelled button so a long translation fits
  is the feature, and FGI wants it. The contract is about buttons with **no label to fit** and buttons
  whose width **belongs to their anchors**.
- **No new API, no signature change, and specifically NO OPT-OUT FLAG.** An opt-out would be the wrong
  shape: it hands the decision back to a caller who cannot see the objects involved, which is the same
  reason the two workarounds above are unsatisfying.
- **No minimum version is needed from FGI.** It feature-detects (`if LLO and LLO.ApplyFontToFrame`),
  so an older embedded copy degrades rather than breaking.

**Reference implementation.** **None staged, and deliberately not.** This file's own rule is to stage
whatever unblocks the consumer inside the consumer, but the thing that would unblock this is a guard
INSIDE the walk, which is not reachable from FGI. What FGI has instead is the two workarounds named
above, which are stop-gaps around symptoms rather than an implementation of the contract, and they
should NOT be treated as one. Finding 5 does carry a concrete `widthIsAnchored` helper if it is
useful; it is a suggestion, not a staged dependency, and nothing of FGI's yields to it.

**Verification.** This is assertable offline and needs none of the text metrics the harness declares a
deliberate fiction, which is the usual reason a request like this could not be checked: the property
is pure geometry over numbers a spec supplies. Build a frame containing (a) a labelled button, (b) a
textless button, and (c) a button anchored `LEFT` and `RIGHT` to its parent; record every descendant's
width; call `ApplyFontToFrame`; assert only (a) may have moved.

Worth saying plainly given AUDIT finding 2: **this library has no test suite at all today**, so
"verified by spec" is not currently available to it. That is finding 2's problem rather than this
request's, and this contract does not depend on it being solved first, but it is the reason the
verification above is written as a recipe rather than as a spec file to extend.

**Bump `MINOR` when it lands.** Not for FGI's benefit, which feature-detects, but because this repo's
own changelog gives the reason (v0.3.2, `MINOR` 13 -> 14): a consumer shipping the fixed copy has to
win the load race against an older embedded one.

**Verified before raising, so nobody re-checks it:** the current release is **v0.3.2** (2026-07-28,
`MINOR` 14) and `GetClientLocale` shipped in **v0.3.1** (2026-07-01). There is no pending release FGI
is waiting on, and nothing of FGI's is blocked behind this request.

**Unverified, and it bears on urgency:** what the CLIENT paints for a region carrying both two
horizontal anchors and an explicit `SetWidth`. If the anchors win at paint time, no player has SEEN a
wrong size and the damage is confined to code that reads `GetWidth` back. FGI's evidence is from its
offline harness, not from a client. That would lower the severity; it would not change the contract,
because writing a size the layout discards still corrupts the answer every other reader gets.

> **Library response -- 2026-08-25 -- DELIVERED (MINOR 16), and the guarantee is now stated rather
> than implied.** You asked for a promise, not just the fixes, and you were right that they are
> different things: audit findings 3, 4 and 5 say what was wrong yesterday, and none of them tells
> you whether the call is safe tomorrow. Here is the promise.
>
> **THE GUARANTEE. `lib:ApplyFontToFrame(addon, frame)` and `lib:ApplyFontToButton(addon, button)`
> change how text RENDERS. They never change a widget's SIZE, POSITION, anchors, parent or layout --
> with exactly one exception, which is opt-out-able and is described below.**
>
> **The exception, stated precisely so you can reason about it.** A button that has ALL of:
>
> - a non-empty label, AND
> - `SetWidth`/`GetWidth`, AND
> - a width that is NOT derived from two opposing horizontal anchors,
>
> may have its WIDTH set, and nothing else. Never its height, never its points, never its parent.
> The width is only ever raised above the button's own captured design width, or restored back down
> to it -- so the button cannot end up narrower than it was built. `button.lloFitPad` tunes the
> padding; **`button.lloFitPad` set with a non-empty label is still fitted -- if you want a specific
> button exempt entirely, give it no label or anchor it on both horizontal edges**, both of which are
> now honoured as opt-outs.
>
> **What changed to make that true**, all in `LibLocaleOverride-1.0.lua:365-400`:
>
> - **A textless button is never measured or written.** This is your AceGUI status-bar case, and the
>   `:788` comment that wrongly claimed it was already a no-op is corrected.
> - **A double-anchored button is never measured or written.** New `widthIsAnchored` helper; CENTER
>   does not count, since it constrains the midpoint rather than an edge.
> - **A cached floor is only trusted while the button is still the width we last set it to.** That is
>   what makes the promise survive the pool: your 360px swatch coming back as `Cancel` now arrives
>   with a width we did not write, so the stale floor is dropped and re-captured. Same mechanism for
>   the stock-font cache, which had the identical lifetime bug and would have restored the previous
>   occupant's fonts.
> - **A zero width is never cached as a floor**, so a button walked before layout settles no longer
>   loses its design width for the session.
>
> **You can drop the v2.12.2 workaround if you want to** -- `statusbg:GetWidth()` is no longer
> corrupted by us. I am not telling you to: measuring the bar from its resolved edges is more robust
> than trusting any single reader, and it costs you nothing to keep. That is your call, not mine.
>
> **Verification:** `Tests/font_apply_spec.lua`, six new examples covering the three findings, each
> **driven red against the pre-fix code** before being kept -- including one that reproduces your
> stale-floor scenario as `expected 80, actual 100`. Whole suite 227 passed / 0 failed, coverage
> 1960/1960.
>
> **The one thing I could not settle, and it is the one you flagged:** what the client paints for a
> region carrying both two horizontal anchors and an explicit `SetWidth`. I did not test it in a
> client either. It does not change the guarantee -- the library no longer issues that write at all --
> but if you ever need to know whether players SAW a wrong width historically, that question is still
> open on both our sides.

## Delivered

_None yet -- this board was opened 2026-08-25. Work this library has done for consumers before that
date was requested in chat and is recorded only in `CHANGELOG.md`._

## Declined

_None._

Declined contracts are kept, never deleted, with the reasoning -- so the same wall is not hit and
re-raised in six months.

## Template

```markdown
### <short name> -- <requesting addon> -- YYYY-MM-DD

**What.** One or two sentences: the locale, script, font, API or behaviour needed.

**Why.** What the consumer cannot do without it, and what it is doing instead today. Name the code
path. "It would be nice" is not a why; "every consumer re-implements the same danda strip" is.

**Exact contract.** The observable behaviour the implementation must have -- arity, return values,
defaults, error cases, and anything that is deliberately NOT true. Assertions where you can.

**Reference implementation.** Path to whatever is staged inside the requesting addon, or say there
is none and why.

**Verification.** How this library will know it is right -- which spec file, which behaviour. Say
plainly if the thing you want cannot be verified offline (text METRICS cannot: the harness's are a
deliberate fiction), because that changes what the answer can promise.
```
