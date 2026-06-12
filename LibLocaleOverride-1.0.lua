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

USAGE (consumer side):
    local LLO = LibStub("LibLocaleOverride-1.0")
    LLO:RegisterLocale("MyAddon", "enUS", enUStable, true)   -- baseline
    LLO:RegisterLocale("MyAddon", "deDE", deDEtable)
    LLO:SetStore("MyAddon", getOverrideFn, setOverrideFn)    -- your SavedVariable
    LLO:ApplyStored("MyAddon")                               -- as early as the store reads
    local L = LLO:GetLocale("MyAddon")                       -- read L[key] at BUILD time
    -- in Settings, on change:  LLO:SetOverride("MyAddon", code)  ("auto" or a code)

Original implementation -- contains no third-party code beyond the public-domain
LibStub. License: MIT (see LICENSE).
------------------------------------------------------------------------------]]

local MAJOR, MINOR = "LibLocaleOverride-1.0", 1
assert(LibStub, MAJOR .. " requires LibStub")

local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end   -- an equal or newer copy is already loaded

-- Persistent state, preserved across an in-place library upgrade.
-- registry[addon] = {
--   locales   = { [code] = stringTable },  -- ALL registered tables, never discarded
--   default   = code,                       -- baseline for key fallback (default "enUS")
--   active    = mergedTable,                -- the live table GetLocale() returns
--   override  = "auto" | code,              -- the user's choice (what SetOverride sets)
--   code      = resolvedActiveCode,         -- override resolved to a real locale
--   built     = bool,                       -- has active been merged at least once
--   getStore  = function() return savedCode end,
--   setStore  = function(savedCode) end,
--   fonts     = { [code] = "Interface\\AddOns\\<addon>\\fonts\\X.ttf" },
--   managed   = { { item = fontStringOrFn, origFont = path }, ... },
--   callbacks = { fn, ... },
-- }
lib.registry = lib.registry or {}

-- Bundled fonts for scripts the WoW client can't render on non-native builds,
-- organized by SCRIPT and shipped under fonts/<Script>/. A consumer gets these
-- automatically for a matching locale (no per-addon setup), so the whole addon
-- family covers Thai / Devanagari / Bengali / Tamil / Telugu from one place. Each
-- font also carries Latin + digits, so a fontstring mixing its script with
-- numbers/English renders fully (a script-only font would box the Latin half). A
-- per-addon RegisterFont(addon, code, path) overrides these. Reassigned each load
-- so a newer library version's map always wins.
--
-- `match(text)` returns true only when the text contains the script's characters
-- (UTF-8 byte test). It exists because each font carries ONLY its own script:
-- forcing e.g. the Thai font onto Cyrillic / CJK / Hangul / another Indic script
-- boxes that text. So a bundled font is applied only to text in its own script;
-- everything else keeps the client default font (Latin / Cyrillic / CJK / Hangul).
-- Each block below is a contiguous run of U+0xxx whose 3-byte UTF-8 form starts
-- E0 <b2>: Devanagari E0 A4/A5, Bengali E0 A6/A7, Tamil E0 AE/AF, Telugu E0 B0/B1,
-- Thai E0 B8/B9. To add a script: drop its static .ttf under fonts/<Script>/, add a
-- row here, and (if it's an override locale) a localeScript row below.
local FONT_DIR = "Interface\\AddOns\\LibLocaleOverride\\fonts\\"
local function bytes(a, b)   -- matcher: true if the string contains either 2-byte UTF-8 lead prefix
	return function(s) return s ~= nil and (s:find(a, 1, true) or s:find(b, 1, true)) and true or false end
end
lib.scripts = {
	Thai       = { font = FONT_DIR .. "Thai\\Sarabun-Regular.ttf",                  match = bytes("\224\184", "\224\185") },
	Devanagari = { font = FONT_DIR .. "Devanagari\\NotoSansDevanagari-Regular.ttf", match = bytes("\224\164", "\224\165") },
	Bengali    = { font = FONT_DIR .. "Bengali\\NotoSansBengali-Regular.ttf",       match = bytes("\224\166", "\224\167") },
	Tamil      = { font = FONT_DIR .. "Tamil\\NotoSansTamil-Regular.ttf",           match = bytes("\224\174", "\224\175") },
	Telugu     = { font = FONT_DIR .. "Telugu\\NotoSansTelugu-Regular.ttf",         match = bytes("\224\176", "\224\177") },
}

-- Which bundled script an override LOCALE renders in -- used when that locale is
-- the active UI language. Locales whose script the client already renders (Latin /
-- Cyrillic / CJK / Hangul) are intentionally absent (they need no bundled font).
lib.localeScript = {
	thTH = "Thai",
	hiIN = "Devanagari", mrIN = "Devanagari",
	bnIN = "Bengali",    bnBD = "Bengali",
	taIN = "Tamil",
	teIN = "Telugu",
}

-- The bundled font for an ACTIVE locale code (nil when the locale needs none).
-- This backs lib:GetFont ("what font does the active locale use"). All per-text
-- fonting routes through lib:FontForText instead -- the single resolver every font
-- site funnels through.
local function localeFont(code)
	local name = code and lib.localeScript[code]
	local s    = name and lib.scripts[name]
	return s and s.font or nil
end

-- ===========================================================================
-- internals
-- ===========================================================================

local function ensureReg(self, addon)
	local reg = self.registry[addon]
	if not reg then
		reg = { locales = {}, active = {} }
		self.registry[addon] = reg
	end
	return reg
end

-- Resolve the override ("auto"/nil -> client locale) down to a code we actually
-- have a table for, falling back to the baseline, then to anything registered.
local function resolveActiveCode(reg)
	local code = reg.override
	if not code or code == "auto" then code = GetLocale() end
	if not reg.locales[code] then code = reg.default or "enUS" end
	if not reg.locales[code] then code = next(reg.locales) end   -- last resort
	return code
end

-- Re-font one managed item on a locale switch. A FontString is fonted by its own
-- text's script (lib:FontForText, the single resolver); a callback is handed the
-- active-locale font. When neither applies, the original font is restored (Thai ->
-- English drops back to the Latin face).
local function applyOne(self, addon, entry)
	local item = entry.item
	if type(item) == "function" then
		-- Callback form: hand it the active-locale font (or the original when none).
		local reg = self.registry[addon]
		item(self:GetFont(addon) or entry.origFont, reg and reg.code)
		return
	end
	if not item.GetFont or not item.SetFont then return end
	local _, size, flags = item:GetFont()
	size = size or 12
	local font = self:FontForText(addon, item.GetText and item:GetText())
	if font then
		item:SetFont(font, size, flags)
	elseif entry.origFont then
		item:SetFont(entry.origFont, size, flags)
	end
end

local function applyFonts(self, addon)
	local reg = self.registry[addon]
	if not reg or not reg.managed then return end
	for i = 1, #reg.managed do
		applyOne(self, addon, reg.managed[i])
	end
end

local function fireCallbacks(self, addon)
	local reg = self.registry[addon]
	if not reg or not reg.callbacks then return end
	for i = 1, #reg.callbacks do
		-- A broken consumer callback must not abort the switch for the others.
		pcall(reg.callbacks[i], addon, reg.code)
	end
end

-- Rebuild reg.active IN PLACE = baseline + active locale on top. In place so a
-- captured `local L = lib:GetLocale(addon)` stays valid after a switch.
local function rebuild(self, addon)
	local reg = self.registry[addon]
	if not reg then return end
	local code     = resolveActiveCode(reg)
	local baseCode = reg.default or "enUS"
	local base     = reg.locales[baseCode] or {}
	local target   = (code and reg.locales[code]) or base
	local active   = reg.active
	for k in pairs(active) do active[k] = nil end
	for k, v in pairs(base) do active[k] = v end           -- English fallback
	if target ~= base then
		for k, v in pairs(target) do active[k] = v end     -- chosen locale on top
	end
	reg.code  = code
	reg.built = true
	applyFonts(self, addon)
	fireCallbacks(self, addon)
end

-- ===========================================================================
-- public API
-- ===========================================================================

--- Register one locale table for an addon. KEEPS every table (the core
--- difference from AceLocale) so the language can switch at runtime. Mark the
--- enUS baseline with isDefault=true -- its keys are the partial-translation
--- fallback. Returns the table for convenience.
function lib:RegisterLocale(addon, code, tbl, isDefault)
	assert(type(addon) == "string", MAJOR .. ":RegisterLocale - addon must be a string")
	assert(type(code)  == "string", MAJOR .. ":RegisterLocale - code must be a string")
	assert(type(tbl)   == "table",  MAJOR .. ":RegisterLocale - tbl must be a table")
	local reg = ensureReg(self, addon)
	reg.locales[code] = tbl
	if isDefault then reg.default = code end      -- else rebuild() falls back to "enUS"
	if reg.built then rebuild(self, addon) end    -- fold a late registration in
	return tbl
end

--- Bind the addon's SavedVariable accessor for its chosen override code so the
--- library can persist/restore the selection without owning your DB.
function lib:SetStore(addon, getFn, setFn)
	local reg = ensureReg(self, addon)
	reg.getStore = getFn
	reg.setStore = setFn
end

--- Read the stored override (or "auto") and (re)build the active table. Call as
--- EARLY as the store is readable -- before your modules read GetLocale(addon)
--- at build time -- so the override is active before the UI is built.
function lib:ApplyStored(addon)
	local reg = ensureReg(self, addon)
	local stored = reg.getStore and reg.getStore() or nil
	reg.override = stored or "auto"
	rebuild(self, addon)
end

--- Set the active override ("auto" = follow the client). Persists via the bound
--- setStore, rebuilds the merged table in place, re-applies fonts, and fires the
--- change callback so live widgets can refresh.
function lib:SetOverride(addon, code)
	local reg = ensureReg(self, addon)
	reg.override = code or "auto"
	if reg.setStore then reg.setStore(reg.override) end
	rebuild(self, addon)
end

--- The live merged table (enUS baseline + active locale). The SAME table object
--- is mutated in place on a switch, so capture it once -- but read L[key] at
--- build time, never freeze it at load.
function lib:GetLocale(addon)
	local reg = ensureReg(self, addon)
	if not reg.built then rebuild(self, addon) end
	return reg.active
end

--- The resolved active locale code (never "auto"; "auto" resolves to the client).
function lib:GetActiveCode(addon)
	local reg = self.registry[addon]
	return reg and reg.code or nil
end

--- The current override SETTING ("auto" or a code) -- what the dropdown shows.
function lib:GetOverride(addon)
	local reg = self.registry[addon]
	return reg and reg.override or "auto"
end

--- Sorted list of registered locale codes -- feed a language dropdown.
function lib:GetAvailable(addon)
	local reg = self.registry[addon]
	local out = {}
	if reg then
		for code in pairs(reg.locales) do out[#out + 1] = code end
		table.sort(out)
	end
	return out
end

--- True if the addon has a table registered for `code`. Useful to coerce a
--- saved-but-no-longer-offered locale back to "auto" in a dropdown's getter.
function lib:HasLocale(addon, code)
	local reg = self.registry[addon]
	return (reg and reg.locales[code]) ~= nil
end

--- The bundled font path for the addon's ACTIVE locale (per-addon override, then
--- the library's built-in default), or nil when the locale renders with the
--- client's default font. Apply this to text the managed-FontString hook can't
--- reach (e.g. AceGUI tab buttons), right after you (re)build those widgets.
function lib:GetFont(addon)
	local reg  = self.registry[addon]
	local code = reg and reg.code
	if not code then return nil end
	return (reg.fonts and reg.fonts[code]) or localeFont(code) or nil
end

--- The bundled font that renders `text` based on its SCRIPT, independent of the
--- active locale -- e.g. "ไทย" resolves to the Thai font even when the UI locale is
--- English. THIS IS THE SINGLE RESOLVER every font site routes through: the frame
--- walk (lib:ApplyFontToFrame), managed fontstrings, and the AceGUI dropdown all
--- call it. For mixed-script content (a language picker) each entry renders in its
--- own script regardless of the chosen UI language. Returns nil when no bundled
--- script matches (the client's default font already renders the text).
function lib:FontForText(addon, text)
	if not text or text == "" then return nil end
	local reg = self.registry[addon]
	for name, s in pairs(lib.scripts) do
		if s.match(text) then
			-- A per-addon RegisterFont override (keyed by locale) wins over built-in.
			if reg and reg.fonts then
				for code, scr in pairs(lib.localeScript) do
					if scr == name and reg.fonts[code] then return reg.fonts[code] end
				end
			end
			return s.font
		end
	end
	return nil
end

-- Recursively re-font every FontString under a frame (regions + children). Each
-- FontString is fonted by `resolve(its text)` -- the per-text resolver -- so a
-- bundled font lands only on text in its own script and mixed-script surfaces (a
-- language picker) keep Cyrillic / CJK / Hangul on the client font. Returns the
-- number of FontStrings re-fonted.
local function walkFonts(frame, resolve)
	if not frame then return 0 end
	local n = 0
	if frame.GetRegions then
		for _, r in ipairs({ frame:GetRegions() }) do
			if r.GetObjectType and r:GetObjectType() == "FontString" and r.SetFont and r.GetFont then
				local font = resolve(r.GetText and r:GetText())
				if font then
					local _, size, flags = r:GetFont()
					if size then r:SetFont(font, size, flags); n = n + 1 end
				end
			end
		end
	end
	if frame.GetChildren then
		for _, child in ipairs({ frame:GetChildren() }) do
			n = n + walkFonts(child, resolve)
		end
	end
	return n
end

--- Re-font every FontString under `frame` (recursively) by each string's own
--- script, via lib:FontForText. For scripts the WoW default can't render (Thai,
--- Devanagari, ...); text the client already renders is left untouched. Call AFTER
--- (re)building content -- a rebuild resets fonts to default, so switching back to
--- a Latin locale needs no restore.
function lib:ApplyFontToFrame(addon, frame)
	if not frame then return end
	walkFonts(frame, function(text) return self:FontForText(addon, text) end)
end

-- ===========================================================================
-- font manager
-- ===========================================================================

--- Map a locale code to a bundled font file (for scripts the client can't
--- render on non-native clients, e.g. Thai). The font ships with the consumer;
--- pass its full Interface path.
function lib:RegisterFont(addon, code, fontPath)
	local reg = ensureReg(self, addon)
	reg.fonts = reg.fonts or {}
	reg.fonts[code] = fontPath
	if reg.built then applyFonts(self, addon) end
end

--- Register a FontString (or a callback fn(fontPath, code)) to receive the
--- active locale's font on every switch. For a FontString its current font is
--- snapshotted as the "default" to restore when a locale has no bundled font.
function lib:RegisterManagedFontString(addon, fontStringOrFn)
	local reg = ensureReg(self, addon)
	reg.managed = reg.managed or {}
	local entry = { item = fontStringOrFn }
	if type(fontStringOrFn) ~= "function" and fontStringOrFn.GetFont then
		entry.origFont = select(1, fontStringOrFn:GetFont())
	end
	reg.managed[#reg.managed + 1] = entry
	applyOne(self, addon, entry)   -- apply current locale immediately
	return entry
end

-- ===========================================================================
-- change notification
-- ===========================================================================

--- Register fn(addon, activeCode) to run after a locale switch (refresh widgets;
--- no /reload needed).
function lib:RegisterCallback(addon, fn)
	assert(type(fn) == "function", MAJOR .. ":RegisterCallback - fn must be a function")
	local reg = ensureReg(self, addon)
	reg.callbacks = reg.callbacks or {}
	reg.callbacks[#reg.callbacks + 1] = fn
end
