# Lib: LocaleOverride

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
