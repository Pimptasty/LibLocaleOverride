# LibLocaleOverride

Per-addon, runtime-switchable **UI language override** for World of Warcraft
addons, plus a **bundled-font manager** for scripts the WoW client can't render
(e.g. Thai). Embeddable via LibStub.

## Status

**v0.3.1** — runtime per-addon language override; a script-aware bundled-font
manager covering most of the world's scripts (now with Latin merged in, so embedded
brand/command text never boxes); **locale-native numerals**; full **button** and
**native-dropdown** fonting that sizes to the width a non-Latin label is actually painted
at; a **client-locale resolver** (`GetClientLocale`) for chat/print output in a
chat-renderable language; right-to-left support (Hebrew + Arabic / Persian / Urdu,
with Arabic contextual shaping); and optional AceGUI integration — a two-column language
picker and an automatic tab-font handler. First consumer: **FastGuildInvite**.

## Why not AceLocale-3.0 / AddonLocale?

- **AceLocale** keeps only the client-locale table + the default and resolves the
  language **once** at load (`GetLocale()` / `GAME_LOCALE`). It can't switch a
  language at runtime, and `GAME_LOCALE` is a single global that retargets **every**
  AceLocale addon at once — antisocial toward addons you didn't write.
- **AddonLocale** is a standalone, **global** user wrapper around `GAME_LOCALE`.
  Same global limitation; no per-addon picker; no fonts.
- Neither handles **fonts** for non-renderable scripts.

This library keeps **every** registered locale table, merges them on demand
(enUS baseline + chosen locale on top), **per addon**, switchable live — so
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
LLO:GetActiveCode(addon)                          -- resolved code; GetOverride / GetAvailable / HasLocale
LLO:UnregisterAddon(addon)                        -- forget everything for an addon

-- fonts
LLO:GetFont(addon)                                -- bundled font path for the active locale
LLO:FontForText(addon, text)                      -- font for a string by its own script
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
LLO:AttachTabGroupFont(addon, tabGroup)           -- keep a TabGroup's tabs fonted for the active locale
LLO:IsAnyPulloutOpen() / LLO:OnPulloutClose(fn)   -- defer a panel refresh while a list is open
LLO:HookCleanRelease(widget, restoreFn, key)      -- restore a pooled widget to stock on release

-- right-to-left (LibLocaleOverride-RTL-1.0)
LLO:Shape(text)                                   -- logical -> visual order (safe on any string)
LLO:IsRTL(addon) / LLO:IsRTLCode(code)            -- is the active locale / a given code right-to-left
```

## Credits

The locale-merging core is an original implementation. Bundled assets and adapted
data:

- **Fonts** — Google Noto (Latin/Greek/Cyrillic, Arabic, Hebrew, Devanagari, Bengali,
  Gurmukhi, Tamil, Telugu, Japanese, Korean, Chinese Simplified & Traditional) and
  Sarabun (Thai), all under the SIL Open Font License 1.1; each ships its `OFL.txt`
  under `fonts/<Script>/`.
- **Arabic / Persian / Urdu reshaping tables** — the base-letter → presentation-form
  mappings are generated from the Unicode Arabic Presentation Forms via
  [python-arabic-reshaper](https://github.com/mpcabd/python-arabic-reshaper) (MIT, ©
  Abdullah Diab); the reshaping/ligature approach was seeded by
  [Arabic_Reshaper_LUA](https://github.com/DiNaSoR/Arabic_Reshaper_LUA) (MIT). The
  shaping and BiDi logic in `LibLocaleOverride-RTL-1.0.lua` is our own.

## License

[MIT](LICENSE).
