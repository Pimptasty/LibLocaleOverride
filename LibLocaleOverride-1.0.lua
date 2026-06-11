--[[----------------------------------------------------------------------------
LibLocaleOverride-1.0

Per-addon, runtime-switchable UI language override for World of Warcraft addons,
plus a bundled-font manager for scripts the WoW client can't render.

WHY THIS EXISTS (vs AceLocale-3.0 + GAME_LOCALE / AddonLocale):
  * AceLocale keeps only the client-locale table + the default and resolves the
    language ONCE at load via GetLocale()/GAME_LOCALE. It cannot switch an addon's
    language at runtime, and GAME_LOCALE is a single global that changes EVERY
    AceLocale addon at once -- ill-behaved toward addons you didn't write.
  * This library keeps EVERY registered locale table and merges them on demand
    (enUS baseline + the chosen locale on top, so a missing key falls back to
    English), PER ADDON, switchable live. Picking Dutch for your addon never
    touches anyone else's.
  * It also maps locales to bundled fonts (e.g. Thai), which nothing in the
    ecosystem does, and fires a change callback so widgets can refresh without a
    /reload.

Original implementation -- contains no third-party code. License: MIT (see LICENSE).

STATUS: scaffold. The API below is the agreed shape; bodies marked TODO(build)
are filled in during the implementation pass (ported from FastGuildInvite's
proven activeL / RebuildLocale / ApplyLocaleOverride logic, which is consumer #1).
------------------------------------------------------------------------------]]

local MAJOR, MINOR = "LibLocaleOverride-1.0", 1
assert(LibStub, MAJOR .. " requires LibStub")

local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end   -- an equal or newer copy is already loaded

--==[ persistent state (survives a library upgrade) ]=========================
-- registry[addon] = {
--   locales  = { [code] = stringTable },   -- ALL registered tables, never discarded
--   default  = code,                        -- baseline for key fallback (usually "enUS")
--   active   = mergedTable,                 -- live table returned by GetLocale()
--   code     = activeCode,                  -- resolved active code ("auto" -> client locale)
--   getStore = function() return savedCode end,   -- consumer-owned persistence (read)
--   setStore = function(savedCode) end,           -- consumer-owned persistence (write)
-- }
lib.registry  = lib.registry  or {}
lib.fonts     = lib.fonts     or {}   -- [code]  = "Interface\\AddOns\\<addon>\\fonts\\Font.ttf"
lib.managed   = lib.managed   or {}   -- [addon] = { fontStringOrApplyFn, ... }
lib.callbacks = lib.callbacks or {}   -- [addon] = { fn, ... }

--==[ API -- signatures + contracts; implementations land in the build step ]==

--- Register one locale table for an addon. Unlike AceLocale this KEEPS every
--- table so the language can be switched at runtime. Mark the enUS baseline with
--- isDefault=true -- its keys are the fallback for partial translations.
function lib:RegisterLocale(addon, code, tbl, isDefault)
    -- TODO(build): store tbl under registry[addon].locales[code]; track default.
end

--- Bind the addon's SavedVariable accessor for its chosen override code, so the
--- library can persist/restore the selection without owning your DB.
function lib:SetStore(addon, getFn, setFn)
    -- TODO(build)
end

--- Read the stored override (or "auto") and (re)build the active table. Call this
--- EARLY at login -- before your modules capture GetLocale(addon) -- mirroring how
--- FGI reads the override straight from its SavedVariable ahead of module load.
function lib:ApplyStored(addon)
    -- TODO(build)
end

--- Set the active override ("auto" = follow the client). Persists via SetStore,
--- rebuilds the merged table IN PLACE, applies the locale's font, and fires the
--- change callback so live widgets can refresh.
function lib:SetOverride(addon, code)
    -- TODO(build)
end

--- The live merged table (enUS baseline + active locale). The SAME table object is
--- mutated in place on a switch, so a captured `local L = lib:GetLocale(addon)`
--- stays valid -- but read L[key] at build time, never freeze it at load.
function lib:GetLocale(addon)
    -- TODO(build): return registry[addon] and registry[addon].active
end

--- The resolved active locale code (never "auto"; "auto" resolves to the client).
function lib:GetActiveCode(addon)
    -- TODO(build)
end

--- Sorted list of registered locale codes -- feed a language dropdown.
function lib:GetAvailable(addon)
    -- TODO(build)
end

--==[ font manager -- the piece the ecosystem is missing ]====================

--- Map a locale code to a bundled font file, for scripts the WoW client can't
--- render on non-native clients (e.g. Thai). The font ships with the consumer.
function lib:RegisterFont(code, fontPath)
    -- TODO(build)
end

--- Register a FontString (or an apply-callback fn(fontPath)) to receive the active
--- locale's font whenever the language changes.
function lib:RegisterManagedFontString(addon, fontStringOrFn)
    -- TODO(build)
end

--==[ change notification ]===================================================

--- Register fn to run after a locale switch (refresh widgets; no /reload needed).
function lib:RegisterCallback(addon, fn)
    -- TODO(build)
end
