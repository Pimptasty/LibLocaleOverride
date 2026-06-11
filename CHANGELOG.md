# Lib: LocaleOverride

## [v0.1.0] (2026-06-11) — initial scaffold

Project skeleton for `LibLocaleOverride-1.0` — a per-addon, runtime-switchable UI
language override plus a bundled-font manager, embeddable via LibStub.

- LibStub registration boilerplate + upgrade-safe persistent state
  (`registry` / `fonts` / `managed` / `callbacks`).
- API surface defined: `RegisterLocale`, `GetLocale`, `GetActiveCode`,
  `GetAvailable`, `SetStore`, `ApplyStored`, `SetOverride`, `RegisterFont`,
  `RegisterManagedFontString`, `RegisterCallback` — bodies pending, ported from
  FastGuildInvite's proven `activeL` / `RebuildLocale` merge (consumer #1).
- Single multi-version TOC (Vanilla / BCC / Wrath / Cata / Mists / Retail) à la
  LibDBIcon, vendored LibStub, MIT license, and packaging + editor tooling.
