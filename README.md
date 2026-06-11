# LibLocaleOverride

Per-addon, runtime-switchable **UI language override** for World of Warcraft
addons, plus a **bundled-font manager** for scripts the WoW client can't render
(e.g. Thai). Embeddable via LibStub.

## Status

🚧 **Scaffold.** The API shape is captured in
[`LibLocaleOverride-1.0.lua`](LibLocaleOverride-1.0.lua); implementation is in
progress. First consumer: **FastGuildInvite** (its existing `activeL` /
`RebuildLocale` logic is the reference port).

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
picking Dutch for one addon never touches another. Original implementation; no
third-party code.

## Planned API

```lua
local LLO = LibStub("LibLocaleOverride-1.0")

LLO:RegisterLocale(addon, code, tbl, isDefault)   -- keeps ALL tables
LLO:SetStore(addon, getFn, setFn)                 -- bind your SavedVariable
LLO:ApplyStored(addon)                            -- restore override early at login
LLO:SetOverride(addon, code)                      -- "auto" or a locale code
LLO:GetLocale(addon)                              -- live merged table
LLO:GetAvailable(addon)                           -- codes -> language dropdown
LLO:RegisterFont(code, fontPath)                  -- bundled-font manager
LLO:RegisterManagedFontString(addon, fsOrFn)
LLO:RegisterCallback(addon, fn)                   -- refresh on switch, no /reload
```

## License

[MIT](LICENSE).
