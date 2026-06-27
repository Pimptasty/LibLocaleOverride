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

API INDEX (all keyed by your addon name unless noted):
  locale   RegisterLocale, SetStore, ApplyStored, SetOverride, GetLocale, GetActiveCode,
           GetOverride, GetAvailable, HasLocale, UnregisterAddon
  font     GetFont, FontForText, FontObject, ApplyFontToString, ApplyFontToFrame,
           RegisterFont, RegisterManagedFontString, UnregisterManagedFontString
  events   RegisterCallback, UnregisterCallback
  text     SplitToBytes (byte-aware chat-chunking; not addon-keyed)
  AceGUI (LibLocaleOverride-AceGUI-1.0): RegisterAceGUIDropdown, AttachTabGroupFont,
           IsAnyPulloutOpen, OnPulloutClose, HookCleanRelease
  RTL    (LibLocaleOverride-RTL-1.0):    Shape, IsRTL, IsRTLCode

NOTES for consumers:
  * GetFont/GetActiveCode lazily build on first call, so they're safe before GetLocale --
    but still prefer calling ApplyStored early so the stored override is live before build.
  * The shared tables lib.scripts / lib.scriptOrder / lib.localeScript / lib.rtlLocales /
    lib.languageNames are READ-ONLY: mutating them breaks font routing for every consumer.
  * Teardown (transient frames / test resets): UnregisterManagedFontString, UnregisterCallback,
    UnregisterAddon. Pooled/persistent strings need no unregister.

Original implementation -- contains no third-party code beyond the public-domain
LibStub. License: MIT (see LICENSE).
------------------------------------------------------------------------------]]

-- Bump MINOR on every code change so the newest copy wins LibStub's load race over any
-- older embedded copy (fonts, RTL, AceGUI picker, tab handler, SplitToBytes were all
-- added after the initial MINOR=1).
local MAJOR, MINOR = "LibLocaleOverride-1.0", 12
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
	Gurmukhi   = { font = FONT_DIR .. "Gurmukhi\\NotoSansGurmukhi-Regular.ttf",     match = bytes("\224\168", "\224\169") },
	-- Hebrew is 2-byte UTF-8 (lead D6/D7), not 3-byte like the blocks above; the
	-- single-byte matchers find any D6/D7 lead (Cyrillic is D0/D1, so no clash).
	Hebrew     = { font = FONT_DIR .. "Hebrew\\NotoSansHebrew-Regular.ttf",         match = bytes("\214", "\215") },
	-- Arabic: base block is 2-byte (lead D8-DB); lib:Shape reshapes letters to
	-- 3-byte presentation forms (EF AD..BB), so the matcher must catch both. The
	-- reshaping itself lives in LibLocaleOverride-RTL-1.0.
	Arabic     = { font = FONT_DIR .. "Arabic\\NotoSansArabic-Regular.ttf",
		match = function(s) return s ~= nil and (s:find("[\216-\219]") or s:find("\239[\173-\187]")) and true or false end },
	-- Latin-extended fallback: the WoW client font renders Latin-1 but BOXES Latin
	-- Extended-A/B (Vietnamese đ/ư/ơ/ĩ, Hausa ƙ/ɓ/ɗ, Turkish ğ/ş/İ) and Latin
	-- Extended Additional (Vietnamese tone marks). Matches lead C4-C9 (U+0100-027F)
	-- and E1 B8-BB (U+1E00-1EFF). Latin-1 accents (C3) are left to the client font,
	-- so German/French/Spanish never switch fonts. Noto Sans covers all of these.
	Latin      = { font = FONT_DIR .. "Latin\\NotoSans-Regular.ttf",
		match = function(s) return s ~= nil and (s:find("[\196-\201]") or s:find("\225[\184-\187]")) and true or false end },
	-- Japanese: bundled because the client's CJK fallback covers Han but is unreliable
	-- for kana on non-JP clients (and AceGUI's tab restyle kills the fallback anyway).
	-- The matcher catches Hiragana + Katakana (E3 81-83 = U+3040-30FF), which are
	-- Japanese-specific; pure-Han text (shared with Chinese) is left to the client font
	-- so we don't hijack Chinese. The active jaJP locale gets this font via localeScript.
	Japanese   = { font = FONT_DIR .. "Japanese\\NotoSansJP-Regular.ttf",
		match = function(s) return s ~= nil and s:find("\227[\129-\131]") and true or false end },
	-- Korean: Hangul syllables (lead EA-ED = U+AC00-D7A3) are Korean-specific, so the
	-- matcher is unambiguous. Bundled because the client can't render Hangul off a KR client.
	Korean     = { font = FONT_DIR .. "Korean\\NotoSansKR-Regular.ttf",
		match = function(s) return s ~= nil and s:find("[\234-\237]") and true or false end },
	-- Chinese (Simplified / Traditional): Han ideographs are shared between them AND with
	-- Japanese kanji, so they CAN'T be told apart by codepoint -- a per-text matcher would
	-- misroute (and could box a variant-only glyph). So these never match in FontForText;
	-- the tab strip picks the right one via the ACTIVE locale (localeScript zhCN/zhTW), and
	-- per-text Han is left to the client font. Both fonts carry the full Han range.
	ChineseSimplified  = { font = FONT_DIR .. "ChineseSimplified\\NotoSansSC-Regular.ttf",  match = function() return false end },
	ChineseTraditional = { font = FONT_DIR .. "ChineseTraditional\\NotoSansTC-Regular.ttf", match = function() return false end },
	-- Cyrillic: lead D0/D1 (U+0400-04FF), distinct from Hebrew D6/D7 and Arabic D8-DB.
	-- Reuses the bundled Noto Sans (the latin-greek-cyrillic build carries Cyrillic too).
	Cyrillic   = { font = FONT_DIR .. "Latin\\NotoSans-Regular.ttf", match = bytes("\208", "\209") },
}

-- Deterministic match order for lib:FontForText. pairs(lib.scripts) has UNDEFINED
-- order, so a string that matches two scripts (e.g. a name mixing Latin-extended and
-- Arabic) could resolve to either font run-to-run. Fixed order: specific scripts first,
-- Latin (the broadest fallback) LAST, so a mixed name resolves to its non-Latin script.
-- Reassigned each load alongside lib.scripts so a newer library version's order wins.
lib.scriptOrder = {
	"Thai", "Devanagari", "Bengali", "Gurmukhi", "Tamil", "Telugu",
	"Japanese", "Korean", "Hebrew", "Arabic", "Cyrillic",
	"ChineseSimplified", "ChineseTraditional", "Latin",
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
	heIL = "Hebrew",
	arSA = "Arabic", urPK = "Arabic", faIR = "Arabic",
	-- Latin-script override locales whose letters reach beyond Latin-1 (so the tab
	-- strip's GetFont returns Noto Sans). Swahili / Nigerian Pidgin stay on the
	-- client font (ASCII-only) and need no entry.
	viVN = "Latin", haNG = "Latin", trTR = "Latin",
	paIN = "Gurmukhi",
	jaJP = "Japanese",
	-- CJK + Cyrillic are WoW-native locales, but as OVERRIDES on a non-native client
	-- their scripts box (the client font lacks them + AceGUI's raw SetFont kills the
	-- fallback), so they get a bundled font like every other non-Latin script.
	koKR = "Korean",
	zhCN = "ChineseSimplified", zhTW = "ChineseTraditional",
	ruRU = "Cyrillic",
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
-- font application  --  the ONE place that decides HOW a font reaches a string
-- ===========================================================================

-- Bundled fonts are applied as cached Font OBJECTS, never via a raw
-- FontString:SetFont. A raw SetFont to a script-only TTF turns OFF WoW's
-- glyph-fallback chain, and that "off" state lingers on a recycled/pooled frame
-- even after a later SetFontObject -- so a string that once showed Thai would then
-- box CJK / Cyrillic / Hangul. Driving every site through font objects keeps
-- fallback intact. Objects are cached per (path,size,flags) and created lazily.
local fontObjects, fontObjN = {}, 0
local function bundledObject(path, size, flags)
	local key = path .. "|" .. tostring(size or 0) .. "|" .. tostring(flags or "")
	local obj = fontObjects[key]
	if obj == nil then   -- nil = not tried yet; false = tried, the font file failed to load
		fontObjN = fontObjN + 1
		local o = _G.CreateFont("LibLocaleOverrideFont" .. fontObjN)
		o:SetFont(path, size or 12, flags or "")
		-- Verify the load via GetFont, NOT SetFont's return value: on a Font OBJECT (as
		-- opposed to a FontString) that boolean is unreliable across client versions, and
		-- gating on it fails CLOSED -- every bundled font would fall back to the base and
		-- all non-Latin text would box. GetFont returns the path on success, nil when the
		-- .ttf was missing/invalid; cache that failure (false) so we fall back cleanly
		-- instead of rebuilding a dead object.
		obj = o:GetFont() and o or false
		fontObjects[key] = obj
	end
	return obj or nil
end

--- A cached Font OBJECT for a bundled font PATH (size/flags optional) -- lets a
--- consumer build a fallback object from a bundled font (e.g. the Latin Noto, so a
--- mixed list renders Latin rows in our font too). Returns nil for a nil path.
function lib:FontObject(path, size, flags)
	if not path then return nil end
	return bundledObject(path, size, flags)
end

--- Apply the correct font to a single FontString -- the ONE applicator every font
--- site funnels through (the frame walk, managed strings, the AceGUI dropdown and a
--- consumer's own tab strip), so a fix here fixes them all. A bundled font goes on a
--- cached Font OBJECT; text with no bundled font goes on `opts.base` (a
--- fallback-capable object so the client's per-script fallback survives), or is left
--- untouched when no base is given.
---   opts.localeCode resolve by an EXPLICIT locale code (its bundled font), regardless
---                  of the active locale or the text -- used to font each row of a
---                  language picker in its OWN language's font (the only unambiguous
---                  way for shared-Han scripts: zhCN vs zhTW vs jaJP).
---   opts.byLocale  resolve via the addon's ACTIVE locale (GetFont) instead of the
---                  string's own text (FontForText, the default -- best for mixed
---                  lists where each row is its own language).
---   opts.base      Font OBJECT to fall back to (e.g. GameFontNormalSmall); MUST be
---                  fallback-capable. Omit to leave non-bundled strings as-is.
---   opts.scale     multiply the bundled font's point size (default 1; dropdowns 0.90).
---   opts.size/flags force the bundled font's size/flags (default: from base, else fs).
function lib:ApplyFontToString(fs, addon, opts)
	if not (fs and fs.SetFontObject and fs.GetFont) then return end
	opts = opts or {}
	local path
	if opts.localeCode then
		path = localeFont(opts.localeCode)
	elseif opts.byLocale then
		path = addon and self:GetFont(addon)
	else
		path = addon and self:FontForText(addon, fs.GetText and fs:GetText())
	end
	local obj
	if path then
		local size, flags = opts.size, opts.flags
		if not size then
			local _, s, f = (opts.base or fs):GetFont()
			size = s or 12
			if flags == nil then flags = f end
		end
		obj = bundledObject(path, size * (opts.scale or 1), flags)
	end
	-- A bundled font that failed to load (obj nil) falls back to the base object,
	-- exactly as a string with no bundled script does.
	if obj then
		fs:SetFontObject(obj)
	elseif opts.base then
		fs:SetFontObject(opts.base)
	end
end

--- Apply the correct script font to a BUTTON across ALL of its visual states. A plain
--- :SetFont / ApplyFontToString on the label is not enough for a templated button
--- (UIPanelButtonTemplate, AceGUI buttons, etc.): the button swaps in a PER-STATE font
--- OBJECT on hover / push / disable, so a non-Latin label reverts to the default
--- glyph-less font and renders as boxes the moment the pointer touches it. This points
--- the Normal / Highlight / Pushed / Disabled font objects at the bundled script font
--- (a shared, fallback-safe cached object -- same machinery as ApplyFontToString), and
--- restores the button's own stock font objects when the active locale needs no bundled
--- font (Latin / Cyrillic / CJK). Reusable for any button in any consumer addon.
---
--- Resolves the script from the button's CURRENT label text, so call it AFTER setting
--- the (already-localized) label. Stock per-state fonts are cached on the button the
--- first time through, so the Latin-restore path is exact rather than guessed.
-- A dedicated hidden fontstring used only to measure label width. Measuring the button's
-- OWN fontstring right after swapping its font object is unreliable -- the string's metrics
-- do not always refresh in the same frame, so a non-Latin label was measured in the old
-- (boxy default) font and the button grew to the wrong, too-narrow width. Here we set the
-- bundled font object FIRST and the text SECOND, so GetStringWidth is correct synchronously.
local measureFS
local function measuredWidth(obj, text)
	if not obj or not text or text == "" then return 0 end
	if not measureFS then
		-- Parented to UIParent (not a hidden frame): GetStringWidth can report 0 for a
		-- string on a frame that has never been drawn. It stays invisible because it is
		-- never anchored/sized.
		local f = CreateFrame("Frame", nil, UIParent)
		measureFS = f:CreateFontString(nil, "ARTWORK")
	end
	measureFS:SetFontObject(obj)
	measureFS:SetText(text)
	return measureFS:GetStringWidth() or 0
end

function lib:ApplyFontToButton(addon, button)
	if type(button) ~= "table" or type(button.GetNormalFontObject) ~= "function" then return end
	if button.__lloOrigFonts == nil then            -- cache stock per-state fonts once
		button.__lloOrigFonts = {
			button:GetNormalFontObject(),
			button.GetHighlightFontObject and button:GetHighlightFontObject() or false,
			button.GetPushedFontObject   and button:GetPushedFontObject()   or false,
			button.GetDisabledFontObject and button:GetDisabledFontObject() or false,
		}
	end
	local fs = button.GetFontString and button:GetFontString()
	-- Common consumer pattern: a bare CreateFrame button with a separate child `.label`
	-- fontstring (not the button's own GetFontString, which is nil here). Use that label for
	-- the text, the font, and the width measurement, so these buttons auto-fit too.
	if not fs and type(button.label) == "table" and button.label.GetStringWidth then
		fs = button.label
	end
	local text = (fs and fs.GetText and fs:GetText()) or (button.GetText and button:GetText()) or ""
	local path = self:FontForText(addon, text)
	-- Base (client) font for the no-shaping width proxy. A bare button has no Normal font
	-- object, so fall back to the label's own font object, then to GameFontNormal.
	local baseObj = button.__lloOrigFonts[1]
		or (button.GetNormalFontObject and button:GetNormalFontObject())
		or (fs and fs.GetFontObject and fs:GetFontObject())
		or _G.GameFontNormal
	local obj
	if path then
		local _, size, flags
		if baseObj and baseObj.GetFont then _, size, flags = baseObj:GetFont() end
		obj = bundledObject(path, size or 12, flags)
		if obj then
			button:SetNormalFontObject(obj)
			if button.SetHighlightFontObject then button:SetHighlightFontObject(obj) end
			if button.SetPushedFontObject   then button:SetPushedFontObject(obj)   end
			if button.SetDisabledFontObject then button:SetDisabledFontObject(obj) end
			-- Also set the fontstring's object directly, so the width measured below reflects
			-- the bundled font in THIS frame (the per-state objects may not update the
			-- string's metrics synchronously, which left the auto-fit measuring the old font).
			if fs and fs.SetFontObject then fs:SetFontObject(obj) end
		end
	else
		local o = button.__lloOrigFonts
		if o[1] then button:SetNormalFontObject(o[1]) end
		if o[2] and button.SetHighlightFontObject then button:SetHighlightFontObject(o[2]) end
		if o[3] and button.SetPushedFontObject   then button:SetPushedFontObject(o[3]) end
		if o[4] and button.SetDisabledFontObject then button:SetDisabledFontObject(o[4]) end
	end
	-- Auto-fit width (EVERY button -- no opt-in): grow the button when its now-fonted label
	-- is wider than the width it was designed for, so a longer translation can't overflow,
	-- and restore the design width for a shorter label. The original width is captured ONCE
	-- as the floor, so this is idempotent and reverses cleanly on a locale switch. Crucially
	-- it only acts when the text EXCEEDS the floor: a button whose label already fits -- a
	-- square icon button with a short symbol, an English label that fits its box -- is left
	-- exactly as-is. The button keeps its anchor, so a right-anchored action button just
	-- extends leftward into its neighbour's slack. lloFitPad tunes the horizontal padding.
	if button.SetWidth and button.GetWidth then
		button.__lloFitFloor = button.__lloFitFloor or button:GetWidth() or 0
		local floor, pad = button.__lloFitFloor, (button.lloFitPad or 26)
		local function fit(w)
			w = w or 0
			local target = (w > floor) and (w + pad) or floor
			if target > 0 and math.abs(target - button:GetWidth()) > 0.5 then
				button:SetWidth(target)
			end
		end
		-- WoW does not shape complex scripts. For Indic / Arabic the bundled font's matra and
		-- mark advances collapse under GetStringWidth, so it reports far LESS than the width the
		-- client actually paints. Measuring the SAME text in the button's BASE (client) font --
		-- which advances every codepoint -- is a much closer proxy for the painted width, so
		-- take the larger of the two. (A Latin label measures the same in both, so this never
		-- inflates Latin buttons.)
		local mW = obj and measuredWidth(obj, text) or 0
		local bW = (obj and baseObj) and measuredWidth(baseObj, text) or 0
		local w  = math.max(mW, bW)
		fit(w ~= 0 and w or (fs and fs.GetStringWidth and fs:GetStringWidth()) or 0)
		-- Re-assert on the next frame, after the strip's layout settles, using the same
		-- (better) estimate rather than the under-reporting realized string.
		if C_Timer and C_Timer.After then
			C_Timer.After(0, function() fit(w) end)
		end
	end
end

-- Registered consumer dropdowns -> addon, and a one-time global hook guard.
local ddFontAddon, ddFontHooked = {}, false

--- Font the OPEN list of a Blizzard UIDropDownMenu (UIDropDownMenuTemplate) per the
--- addon's script, so non-Latin menu items don't render as boxes. The dropdown's list
--- lives in the SHARED global frames DropDownList1 / DropDownList2 (parented to UIParent,
--- NOT the consumer's window), so a normal frame-walk never reaches it -- this is why a
--- dropdown's collapsed/selected text fonts correctly but its open items don't.
---
--- Register each dropdown once. A single global hook on ToggleDropDownMenu (taint-safe
--- hooksecurefunc) fonts the open list -- routing each visible item through
--- ApplyFontToButton so it renders the script in EVERY state (normal + highlight), not
--- just until the pointer touches it. Scoped through UIDROPDOWNMENU_OPEN_MENU so the hook
--- only fonts the list when a REGISTERED dropdown is the one open: other addons' dropdowns
--- (and their shared list buttons) are never touched. Reusable by any consumer addon.
function lib:AttachDropDownFont(addon, dropdown)
	if type(dropdown) ~= "table" then return end
	ddFontAddon[dropdown] = addon
	if ddFontHooked then return end
	ddFontHooked = true
	local function fontOpenLists()
		local open = _G.UIDROPDOWNMENU_OPEN_MENU
		local a = open and ddFontAddon[open]
		if not a then return end                       -- not one of ours -> leave it alone
		for lvl = 1, 2 do
			local name = "DropDownList" .. lvl
			local lf = _G[name]
			if lf and lf.IsShown and lf:IsShown() then
				local i = 1
				while true do
					local b = _G[name .. "Button" .. i]
					if not b then break end
					if b.IsShown and b:IsShown() then self:ApplyFontToButton(a, b) end
					i = i + 1
				end
			end
		end
	end
	if _G.hooksecurefunc and _G.ToggleDropDownMenu then
		hooksecurefunc("ToggleDropDownMenu", fontOpenLists)
	end
	-- Backstop for submenus / re-shows that don't re-enter ToggleDropDownMenu.
	for lvl = 1, 2 do
		local lf = _G["DropDownList" .. lvl]
		if lf and lf.HookScript then lf:HookScript("OnShow", fontOpenLists) end
	end
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
	if entry.origObj then
		-- Object-based path: keeps WoW's glyph fallback intact (see ApplyFontToString).
		self:ApplyFontToString(item, addon, { base = entry.origObj })
	else
		-- The string's original font was a raw path (no Font object to restore to);
		-- keep the legacy path-based behaviour for it.
		local _, size, flags = item:GetFont()
		size = size or 12
		local font = self:FontForText(addon, item.GetText and item:GetText())
		if font then
			item:SetFont(font, size, flags)
		elseif entry.origFont then
			item:SetFont(entry.origFont, size, flags)
		end
	end
end

local function applyFonts(self, addon)
	local reg = self.registry[addon]
	if not reg or not reg.managed then return end
	for i = 1, #reg.managed do
		-- pcall per item: a broken managed FontString/callback must not abort the switch
		-- for the others, nor block the change callbacks that follow (matches fireCallbacks).
		pcall(applyOne, self, addon, reg.managed[i])
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
	-- Assert here so a wrong arg points at the consumer's call, not a later ApplyStored/
	-- SetOverride that would otherwise error trying to call a non-function store.
	assert(getFn == nil or type(getFn) == "function", MAJOR .. ":SetStore - getFn must be a function or nil")
	assert(setFn == nil or type(setFn) == "function", MAJOR .. ":SetStore - setFn must be a function or nil")
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
	-- Lazy-build so a consumer reading this before its first GetLocale/ApplyStored still
	-- gets the resolved code. Don't ensureReg -- a getter shouldn't create a registry entry.
	if reg and not reg.built then rebuild(self, addon) end
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
	if reg and not reg.built then rebuild(self, addon) end   -- lazy-build, like GetActiveCode
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
	-- The danda (U+0964 "।") and double danda (U+0965 "॥") are sentence punctuation
	-- SHARED across Bengali / Gurmukhi / Devanagari and other North-Indic scripts, yet
	-- Unicode files them in the Devanagari block. Strip them BEFORE script detection:
	-- otherwise a Bengali (or Punjabi) line ending in "।" matches the Devanagari range
	-- (checked before Bengali in scriptOrder) and the whole line gets the Devanagari
	-- font — which has no Bengali glyphs, so every Bengali letter renders as a box.
	-- Real Devanagari text keeps its own consonants/vowels and still matches Devanagari;
	-- the danda itself renders fine from whichever Indic font is ultimately chosen.
	local probe = text:gsub("\224\165[\164\165]", "")
	if probe == "" then return nil end
	local reg = self.registry[addon]
	for _, name in ipairs(lib.scriptOrder) do
		local s = lib.scripts[name]
		if s and s.match(probe) then
			-- A per-addon RegisterFont override (keyed by locale) wins over built-in. Prefer
			-- the ACTIVE locale's override (deterministic when several codes share a script,
			-- e.g. arSA/urPK/faIR all Arabic); else any registered override for this script.
			if reg and reg.fonts then
				if reg.code and lib.localeScript[reg.code] == name and reg.fonts[reg.code] then
					return reg.fonts[reg.code]
				end
				for code, scr in pairs(lib.localeScript) do
					if scr == name and reg.fonts[code] then return reg.fonts[code] end
				end
			end
			return s.font
		end
	end
	return nil
end

--- Convert the WESTERN digits 0-9 in `text` to the addon's active-locale digits, driven
--- by the locale table itself: L["0"]..L["9"]. The backend/data stays Western (%d, math);
--- only the DISPLAY string is rewritten. MARKUP-AWARE — it never touches the characters
--- inside WoW escapes, so colours/icons/links can't be corrupted: the 8 hex bytes of a
--- colour code |cAARRGGBB, the body of a texture |T...|t, an atlas |A...|a, and the data
--- portion of a hyperlink |H...|h are all skipped. Returns `text` unchanged when the
--- active locale defines no digit override (Latin/Cyrillic/CJK locales — L["0"]=="0").
function lib:LocalizeDigits(addon, text)
	if type(text) ~= "string" or text == "" then return text end
	local reg = self.registry[addon]
	local L = reg and reg.active
	if not L then return text end
	local map, any = {}, false
	for d = 0, 9 do
		local k = tostring(d)
		local v = L[k]
		if v and v ~= k then any = true end
		map[k] = (v ~= nil and v) or k
	end
	if not any then return text end                       -- locale has no native digits
	local out, i, n = {}, 1, #text
	while i <= n do
		local two = text:sub(i, i + 1)
		if two == "|c" then
			out[#out + 1] = text:sub(i, i + 9)            -- |c + 8 hex colour bytes
			i = i + 10
		elseif two == "|T" then
			local e = text:find("|t", i + 2, true)
			if e then out[#out + 1] = text:sub(i, e + 1); i = e + 2
			else out[#out + 1] = two; i = i + 2 end
		elseif two == "|A" then
			local e = text:find("|a", i + 2, true)
			if e then out[#out + 1] = text:sub(i, e + 1); i = e + 2
			else out[#out + 1] = two; i = i + 2 end
		elseif two == "|H" then
			local e = text:find("|h", i + 2, true)        -- skip the link DATA (ids/numbers)
			if e then out[#out + 1] = text:sub(i, e + 1); i = e + 2
			else out[#out + 1] = two; i = i + 2 end
		else
			local c = text:sub(i, i)
			out[#out + 1] = map[c] or c
			i = i + 1
		end
	end
	return table.concat(out)
end

-- Recursively re-font every FontString under a frame (regions + children) by each
-- string's own script, through lib:ApplyFontToString (the shared applicator -- so the
-- object-based, fallback-safe rule applies here too). A bundled font lands only on
-- text in its own script; mixed-script surfaces keep Cyrillic / CJK / Hangul on the
-- client font, and non-bundled strings are left as-is.
local function walkFonts(self, addon, frame, depth)
	if not frame then return end
	depth = depth or 0
	if depth > 30 then return end   -- guard against pathologically deep / cyclic consumer frames
	if frame.GetRegions then
		for _, r in ipairs({ frame:GetRegions() }) do
			if r.GetObjectType and r:GetObjectType() == "FontString" then
				self:ApplyFontToString(r, addon, nil)
			end
		end
	end
	if frame.GetChildren then
		for _, child in ipairs({ frame:GetChildren() }) do
			-- A templated button (UIPanelButtonTemplate, etc.) renders its label through
			-- per-state font OBJECTS, so a plain FontString re-font can't stop it boxing the
			-- moment it's hovered/pushed. Font those states too -- this makes EVERY button
			-- under a walked frame correct automatically, with no per-button call sites.
			-- ApplyFontToButton is a no-op for a textless (icon) button.
			if child.GetObjectType and child:GetObjectType() == "Button"
			   and child.GetNormalFontObject then
				self:ApplyFontToButton(addon, child)
			end
			walkFonts(self, addon, child, depth + 1)
		end
	end
end

--- Re-font every FontString under `frame` (recursively) by each string's own
--- script, via lib:ApplyFontToString. For scripts the WoW default can't render
--- (Thai, Devanagari, ...); text the client already renders is left untouched. Call
--- AFTER (re)building content -- a rebuild resets fonts to default, so switching back
--- to a Latin locale needs no restore.
function lib:ApplyFontToFrame(addon, frame)
	if not frame then return end
	walkFonts(self, addon, frame)
end

-- ===========================================================================
-- text utilities
-- ===========================================================================

--- Split `text` into chunks each at most `maxBytes` BYTES (default 255 -- WoW's
--- SendChatMessage limit), breaking at whitespace/punctuation so words stay whole.
--- Byte-aware (#s), which is the whole point in a locale library: Cyrillic is 2
--- bytes/char and Thai/Indic/CJK 3, so a character count would lie about the wire
--- size. Returns an array of chunks; an EMPTY array signals an unsplittable token
--- longer than maxBytes (the caller should treat that as "won't send").
function lib:SplitToBytes(text, maxBytes)
	maxBytes = tonumber(maxBytes) or 255
	if maxBytes < 1 then maxBytes = 255 end
	if not text or text == "" then return {} end   -- nothing to send (no empty chunk)
	local out = { "" }
	while #text > 0 do
		local _, e = text:find("[%s%.%,]")
		local piece
		if e then
			piece = text:sub(1, e); text = text:sub(e + 1)
		else
			piece = text; text = ""
		end
		if #out[#out] + #piece <= maxBytes then
			out[#out] = out[#out] .. piece
		else
			out[#out + 1] = piece
		end
	end
	for i = 1, #out do
		if #out[i] > maxBytes then return {} end
	end
	return out
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
	-- Dedup FontStrings (not callbacks): AceGUI recycles widgets from a pool, so a
	-- consumer that re-registers the same FontString on every rebuild would otherwise
	-- grow reg.managed without bound (and re-font stale recycled strings on each switch).
	-- Re-registering an already-managed string just re-applies the current locale to it.
	if type(fontStringOrFn) ~= "function" then
		reg.managedSet = reg.managedSet or {}
		local existing = reg.managedSet[fontStringOrFn]
		if existing then
			applyOne(self, addon, existing)
			return existing
		end
	end
	local entry = { item = fontStringOrFn }
	if type(fontStringOrFn) ~= "function" and fontStringOrFn.GetFont then
		entry.origFont = select(1, fontStringOrFn:GetFont())
		-- Snapshot the Font OBJECT too (when the string has one): it restores with the
		-- glyph-fallback chain intact, where the raw path alone would not.
		if fontStringOrFn.GetFontObject then entry.origObj = fontStringOrFn:GetFontObject() end
	end
	reg.managed[#reg.managed + 1] = entry
	if type(fontStringOrFn) ~= "function" then reg.managedSet[fontStringOrFn] = entry end
	applyOne(self, addon, entry)   -- apply current locale immediately
	return entry
end

--- Stop managing a FontString (or callback) previously registered. Needed for TRANSIENT
--- (non-pooled) strings -- a one-shot dialog's fontstring would otherwise stay in `managed`
--- forever and get re-fonted on every locale switch. Pooled/persistent strings can be left.
function lib:UnregisterManagedFontString(addon, fontStringOrFn)
	local reg = self.registry[addon]
	if not (reg and reg.managed) then return end
	if reg.managedSet then reg.managedSet[fontStringOrFn] = nil end
	for i = #reg.managed, 1, -1 do
		if reg.managed[i].item == fontStringOrFn then table.remove(reg.managed, i) end
	end
end

--- Forget EVERYTHING registered for an addon (locales, fonts, store, managed strings,
--- callbacks) -- a clean teardown / test-harness reset. The addon may re-register after.
function lib:UnregisterAddon(addon)
	self.registry[addon] = nil
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
	for i = 1, #reg.callbacks do if reg.callbacks[i] == fn then return end end   -- dedup: never double-fire
	reg.callbacks[#reg.callbacks + 1] = fn
end

--- Remove a change callback previously added with RegisterCallback.
function lib:UnregisterCallback(addon, fn)
	local reg = self.registry[addon]
	if not (reg and reg.callbacks) then return end
	for i = #reg.callbacks, 1, -1 do
		if reg.callbacks[i] == fn then table.remove(reg.callbacks, i) end
	end
end
