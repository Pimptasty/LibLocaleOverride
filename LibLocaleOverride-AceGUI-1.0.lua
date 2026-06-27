--[[----------------------------------------------------------------------------
LibLocaleOverride-AceGUI  --  optional AceGUI-3.0 integration

Loaded after the core LibLocaleOverride-1.0; adds a font-aware AceConfig/AceGUI
dropdown so a non-Latin override locale (e.g. Thai) renders in the library's
bundled font in BOTH the selected value and the open option-list (pullout).

Per-addon factory, not one shared type: a single shared widget type couldn't tell
which addon owns a given dropdown instance, so it couldn't know whose font to
apply. RegisterAceGUIDropdown(addon) registers one type bound to that addon and
returns its name for use as an AceConfig option's `dialogControl`.

Shared-pool safety (why this is leak-free): AceGUI pools its option-row widgets
and their OnAcquire does NOT reset the font, so naively fonting a row would bleed
our font into the next dropdown that recycles it. We follow AceGUI's own rule --
hand pooled widgets back clean -- by restoring each row's original font on
release. Every row therefore returns to the pool at its default font, so there is
zero cross-addon (and cross-locale) bleed.

The core library never depends on this file or on AceGUI: if AceGUI is absent the
factory returns nil and the consumer leaves the option as a stock "select".
------------------------------------------------------------------------------]]

local lib = LibStub and LibStub("LibLocaleOverride-1.0", true)
if not lib then return end

-- Satellite version stamp. This file decorates the shared `lib` directly (it has no LibStub
-- NewLibrary guard of its own), so if an OLDER embedded copy loaded AFTER a newer one it
-- would re-install stale functions/hooks. Bail when an equal-or-newer copy already ran;
-- the newest always wins regardless of load order. Bump on every change to THIS file.
local ACEGUI_MINOR = 4
if (lib._aceguiMinor or 0) >= ACEGUI_MINOR then return end
lib._aceguiMinor = ACEGUI_MINOR

-- All font application goes through the core lib:ApplyFontToString, the single
-- applicator (bundled font -> cached Font OBJECT; no bundled font -> the row's
-- fallback object). That keeps WoW's glyph fallback intact and was the cure for every
-- shrink/box/wrong-font-on-pooled-row regression; this file just supplies each row's
-- fallback object and the dropdown's scale.
--
-- Bundled fonts (Thai/Sarabun, Indic Noto) render larger than the Western font at the
-- same point size, so we scale them down to sit level with the Latin rows. CJK/Hangul
-- aren't bundled (they come from the client's fallback) and so aren't scaled.
local SCALE_BUNDLED = 0.90
local COL2_GUTTER   = 200   -- px from column 1's left edge to column 2's (native name)

--- Wrap an AceGUI widget's OnRelease exactly ONCE so that when AceGUI returns the widget
--- to its (shared, global) pool, `restoreFn(widget)` runs to hand it back in stock state,
--- then the widget's original OnRelease chains. THE single place every LLO feature routes
--- pooled-widget cleanup through -- tab groups, dropdown rows and the pullout all use it --
--- so a widget type the library touches can't ship without a clean release (the gap that
--- bled FGI's tab font into another addon through the shared pool). Each caller guards its
--- own re-decoration, so the same restoreFn isn't queued twice; restoreFns are pcall-
--- isolated so one failing cleanup can't block the others or the widget's original release.
--- Pass a stable `key` so re-decorating the same pooled widget REPLACES rather than queues
--- a duplicate -- the cleanup set then can't grow even if a caller re-registers every render
--- or forgets its own guard. Distinct features pass distinct keys and all run on release.
function lib:HookCleanRelease(widget, restoreFn, key)
	if not widget or type(restoreFn) ~= "function" then return end
	-- Keyed map (key -> fn), NOT an array, so repeated registration can't grow it.
	widget._lloCleanReleases = widget._lloCleanReleases or {}
	widget._lloCleanReleases[key or restoreFn] = restoreFn
	if widget._lloCleanReleaseHooked then return end
	widget._lloCleanReleaseHooked = true
	local origRelease = widget.OnRelease
	widget.OnRelease = function(w, ...)
		local fns = w._lloCleanReleases
		if fns then for _, fn in pairs(fns) do pcall(fn, w) end end
		if origRelease then return origRelease(w, ...) end
	end
end

-- Pullout open/close tracking. A consumer (e.g. an AceConfig panel that live-updates
-- a button via NotifyChange) can ask whether a dropdown list is open and DEFER its
-- refresh -- because NotifyChange rebuilds the panel, which would otherwise close the
-- open list out from under the user. Counted because pullouts come from a shared pool.
lib._pulloutDepth    = lib._pulloutDepth or 0
lib._pulloutCloseCbs = lib._pulloutCloseCbs or {}
function lib:IsAnyPulloutOpen() return (self._pulloutDepth or 0) > 0 end
function lib:OnPulloutClose(fn)
	if type(fn) ~= "function" then return end
	-- Dedup: this is a PERSISTENT "flush my deferred refresh when a list closes" hook a
	-- consumer registers ONCE (it re-checks its own pending state each fire). Guard against
	-- accidental re-registration so the global list can't grow unbounded.
	for i = 1, #self._pulloutCloseCbs do if self._pulloutCloseCbs[i] == fn then return end end
	self._pulloutCloseCbs[#self._pulloutCloseCbs + 1] = fn
end
local function notePulloutOpen() lib._pulloutDepth = (lib._pulloutDepth or 0) + 1 end
local function notePulloutClose()
	lib._pulloutDepth = math.max(0, (lib._pulloutDepth or 0) - 1)
	if lib._pulloutDepth == 0 then
		for _, fn in ipairs(lib._pulloutCloseCbs) do pcall(fn) end
	end
end
-- Hook a pullout's Open/Close once so it feeds the depth counter (guarded per-pullout
-- so a re-Open while already open doesn't double-count).
local function hookPullout(p)
	if not p or p._lloHooked then return end
	p._lloHooked = true
	local origOpen, origClose = p.Open, p.Close
	if origOpen then
		p.Open = function(self, ...)
			-- Only count opens while this pooled pullout currently belongs to one of OUR
			-- dropdowns (_lloOwned, set in refontPullout). Without that gate a foreign
			-- addon's dropdown recycling this pullout from the shared pool would tick our
			-- counter and make IsAnyPulloutOpen() lie.
			if self._lloOwned and not self._lloIsOpen then self._lloIsOpen = true; notePulloutOpen() end
			return origOpen(self, ...)
		end
	end
	if origClose then
		p.Close = function(self, ...)
			local r = origClose(self, ...)
			if self._lloIsOpen then self._lloIsOpen = false; notePulloutClose() end
			return r
		end
	end
	-- On release back to the pool: drop our ownership flag and balance the counter if the
	-- pullout was still flagged open (Close didn't fire), so a consumer that defers
	-- refreshes "while a list is open" can't get stuck and a foreign reuse starts clean.
	lib:HookCleanRelease(p, function(self)
		self._lloOwned = false
		if self._lloIsOpen then self._lloIsOpen = false; notePulloutClose() end
	end, "lloPullout")
end

-- A Noto Sans (Latin) Font OBJECT sized to GameFontNormalSmall, so the picker can
-- render Latin rows in OUR font too (consistent across WoW clients), not the client
-- font. Lazily built + cached. Falls back to GameFontNormalSmall if the font is absent.
local _latinBase
local function latinBaseObj()
	if _latinBase ~= nil then return _latinBase end
	local p = lib.scripts and lib.scripts.Latin and lib.scripts.Latin.font
	local _, s, f = _G.GameFontNormalSmall:GetFont()
	_latinBase = (p and lib:FontObject(p, s or 12, f)) or _G.GameFontNormalSmall
	return _latinBase
end

-- Font `fs` by its own text, falling back to `baseObj` -- a thin wrapper over the
-- shared core applicator so dropdown rows obey the one font rule.
local function applyFont(fs, addon, baseObj)
	lib:ApplyFontToString(fs, addon, { base = baseObj, scale = SCALE_BUNDLED })
end

-- Re-font one pulled-up option row by its own script, then normalize its size. The
-- row's font is NOT captured/restored from a per-item "original" -- via the shared
-- pool that leaked another language's font onto a recycled row (Sarabun bleeding
-- onto "Francais", the Korean font onto "Portugues", etc.). Instead a non-bundled
-- row goes on the client default object, and WoW resolves the right per-script file
-- (Latin/Cyrillic/Korean/CJK) from it for the row's own text.
local function decorateItem(addon, item)
	local fs = item and item.text
	if not (fs and fs.SetFont and fs.GetFont and fs.SetFontObject) then return end

	-- Hand the pooled row back on the client default so the next dropdown to recycle it
	-- (any addon) never inherits our font. Keyed clean-release: idempotent across renders,
	-- registered unconditionally (its own key) so it's never skipped because this pooled
	-- item happened to be lang-decorated before.
	lib:HookCleanRelease(item, function(it)
		if it.text and it.text.SetFontObject then it.text:SetFontObject(_G.GameFontNormalSmall) end
	end, "lloItemFont")

	local txt = fs.GetText and fs:GetText()
	applyFont(fs, addon, _G.GameFontNormalSmall)

	if _G.LibLocaleOverride_DEBUG then
		_G.print("|cff88ccffLLO|r", tostring(txt):sub(1, 16), "now:", tostring(select(1, fs:GetFont())):match("[^\\]+$") or "?")
	end
end

-- Re-font one option row as TWO columns for a language picker. Names come from the
-- library's canonical table (lib.languageNames):
--   column 1 = lib.languageNames[active][code] (English fallback) -- the language's name
--              in the ACTIVE locale; fonted by the text's OWN script.
--   column 2 = lib.languageNames[code][code] -- its native endonym; fonted by THAT ROW's
--              own locale (the only unambiguous way for shared-Han zhCN/zhTW/jaJP).
-- RTL names are shaped at render: column 1 when the active locale is RTL, column 2 when
-- THIS row's code is RTL. The "auto" row stays single-column.
local function decorateLangItem(addon, item)
	local fs = item and item.text
	if not (fs and fs.SetText and fs.GetText and fs.SetFontObject) then return end

	-- Reset the row font AND hide our extra column-2 fontstring on release, so the pooled
	-- row goes back clean for the next addon. Keyed clean-release: idempotent across renders
	-- and ALWAYS registered (own key), so the col2-hide is never skipped even if this pooled
	-- item was previously decorated by the non-lang path.
	lib:HookCleanRelease(item, function(it)
		if it.text and it.text.SetFontObject then it.text:SetFontObject(_G.GameFontNormalSmall) end
		if it._lloCol2 then it._lloCol2:SetText(""); it._lloCol2:Hide() end
	end, "lloLangItem")

	local code = (item.userdata and item.userdata.value) or item.value
	local base = latinBaseObj()
	if not code then applyFont(fs, addon, base); return end

	local names  = lib.languageNames or {}
	local en     = names.enUS or {}
	local an     = names[lib.GetActiveCode and lib:GetActiveCode(addon) or "enUS"]
	local exonym  = (an and an[code]) or en[code] or tostring(code)                       -- column 1
	local endonym = (names[code] and names[code][code]) or en[code] or tostring(code)     -- column 2
	if lib.Shape then
		if lib.IsRTL and lib:IsRTL(addon) then exonym = lib:Shape(exonym) end             -- active locale RTL
		if lib.rtlLocales and lib.rtlLocales[code] then endonym = lib:Shape(endonym) end  -- this row's code RTL
	end

	fs:SetText(exonym)                                                     -- column 1
	-- Font by the text's OWN script (FontForText): the exonym is the active locale's name
	-- when translated but English when not, so font by what it actually is.
	lib:ApplyFontToString(fs, addon, { base = base, scale = SCALE_BUNDLED })

	if code ~= "auto" and endonym ~= "" then                               -- column 2
		local c2 = item._lloCol2
		if not c2 then
			-- Inherit a font template so SetText has a font (a bare CreateFontString
			-- errors "Font not set"); ApplyFontToString below sets the per-locale font.
			c2 = item.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			c2:SetPoint("LEFT", fs, "LEFT", COL2_GUTTER, 0)
			c2:SetJustifyH("LEFT")
			item._lloCol2 = c2
		end
		c2:SetText(endonym)
		c2:Show()
		lib:ApplyFontToString(c2, addon, { localeCode = code, base = base, scale = SCALE_BUNDLED })
	elseif item._lloCol2 then
		item._lloCol2:SetText(""); item._lloCol2:Hide()
	end
end

-- Display order for a language picker: every code sorted A-Z by its column-1 name in the
-- ACTIVE locale (lib.languageNames[active][code], English fallback), "auto" pinned first.
-- Re-sorts whenever the list is (re)built, so it follows the chosen language.
local function langSortOrder(addon, values, order)
	local codes = {}
	if order then
		for i = 1, #order do codes[i] = order[i] end
	else
		for k in pairs(values) do codes[#codes + 1] = k end
	end
	local names = lib.languageNames or {}
	local en = names.enUS or {}
	local an = names[lib.GetActiveCode and lib:GetActiveCode(addon) or "enUS"]
	table.sort(codes, function(a, b)
		if a == "auto" then return b ~= "auto" end   -- "auto" always first
		if b == "auto" then return false end
		local na = (an and an[a]) or en[a] or tostring(a)
		local nb = (an and an[b]) or en[b] or tostring(b)
		if na == nb then return tostring(a) < tostring(b) end
		return na < nb
	end)
	return codes
end

--- A native-endonym map { [code] = name } for a language picker's AceConfig `values`,
--- built from the library's canonical names (RTL endonyms shaped). Pass the codes to
--- offer (e.g. lib:AllLanguageCodes()).
function lib:LanguagePickerValues(codes)
	local names = self.languageNames or {}
	local en = names.enUS or {}
	local out = {}
	for _, code in ipairs(codes) do
		local endonym = (names[code] and names[code][code]) or en[code] or tostring(code)
		if self.rtlLocales and self.rtlLocales[code] and self.Shape then endonym = self:Shape(endonym) end
		out[code] = endonym
	end
	return out
end

--- Every language code the library has names for (the offerable set; includes "auto").
--- Order is unspecified -- a language picker re-sorts A-Z by column 1 anyway.
function lib:AllLanguageCodes()
	local out, en = {}, self.languageNames and self.languageNames.enUS
	if en then for code in pairs(en) do out[#out + 1] = code end end
	return out
end

--- Register (once) an AceGUI dropdown widget type bound to `addon` whose display
--- AND pullout render the addon's active override font. Returns the type name to
--- use as an AceConfig option's `dialogControl`, or nil when AceGUI-3.0 isn't
--- available (the caller should then leave the option as a stock "select").
---   opts.languagePicker = render the open list as TWO columns -- column 1 the
---     language name in the current locale (L["lang_<itemvalue>"], English fallback),
---     column 2 the native endonym -- for a UI-language picker. The pullout is also
---     tracked (lib:IsAnyPulloutOpen / OnPulloutClose) so the consumer can defer a
---     panel refresh while the list is open instead of yanking it shut.
function lib:RegisterAceGUIDropdown(addon, opts)
	-- Resolved at call time (not file load) so load order vs AceGUI never matters.
	local GUI = LibStub("AceGUI-3.0", true)
	if not GUI or not GUI.WidgetRegistry then return nil end
	local stock = GUI.WidgetRegistry["Dropdown"]
	if not stock then return nil end

	local langMode = opts and opts.languagePicker and true or false
	local typeName = "LibLocaleOverride_Dropdown_" .. tostring(addon) .. (langMode and "_lang" or "")
	if GUI.WidgetRegistry[typeName] then return typeName end   -- already registered

	local function Constructor()
		-- Reuse AceGUI's stock Dropdown wholesale, then decorate it. No behaviour
		-- change beyond re-fonting; the widget pools under `typeName`, separate
		-- from the stock "Dropdown" pool.
		local widget = stock()
		widget._lloDisplayOrig = (widget.text and widget.text.GetFontObject)
			and widget.text:GetFontObject() or nil

		local function refontDisplay()
			local fs = widget.text
			if not (fs and fs.SetFont and fs.GetFont) then return end
			if langMode then
				-- Selected value: font by the ACTIVE locale (which is the selection),
				-- in our fonts, so it matches the list.
				lib:ApplyFontToString(fs, addon, { byLocale = true, base = latinBaseObj(), scale = SCALE_BUNDLED })
			else
				-- Font the selected value by its own script (so "Русский" shows in the
				-- client font and "ไทย" in Sarabun) regardless of the active UI locale.
				applyFont(fs, addon, widget._lloDisplayOrig or _G.GameFontNormalSmall)
			end
		end

		local function refontPullout()
			local p = widget.pullout
			if not p or not p.items then return end
			hookPullout(p)   -- track open/close so a consumer can defer refreshes
			p._lloOwned = true   -- this pullout currently belongs to our dropdown (scopes the counter)
			for _, item in ipairs(p.items) do
				if langMode then decorateLangItem(addon, item) else decorateItem(addon, item) end
			end
		end

		local origSetText = widget.SetText
		if origSetText then
			widget.SetText = function(w, ...)
				local r = origSetText(w, ...)
				refontDisplay()
				return r
			end
		end

		-- SetList (re)builds the option rows; in language-picker mode re-sort the order
		-- A-Z by column 1 first. SetValue/AddItem change the display or add a row.
		-- Re-font after each so a freshly built menu localizes.
		local origSetList = widget.SetList
		if origSetList then
			widget.SetList = function(w, values, order, ...)
				if langMode and type(values) == "table" then
					order = langSortOrder(addon, values, order)
				end
				local r = origSetList(w, values, order, ...)
				refontDisplay()
				refontPullout()
				return r
			end
		end
		for _, m in ipairs({ "AddItem", "SetValue" }) do
			local orig = widget[m]
			if orig then
				widget[m] = function(w, ...)
					local r = orig(w, ...)
					refontDisplay()
					refontPullout()
					return r
				end
			end
		end

		widget.type = typeName
		return widget
	end

	GUI:RegisterWidgetType(typeName, Constructor, 1)
	return typeName
end

-- Cache of bundled-font Font OBJECTS that also carry a fixed text COLOUR, keyed by
-- (path,size,flags,colour). AceGUI's tab look is driven entirely by per-state font
-- objects, so to keep the gold(unselected) / white(selected) distinction with a bundled
-- (Indic / CJK / Arabic) font we need colour-matched objects -- the shared core FontObject
-- cache is colourless (defaults to white), which would force every tab to one colour.
local tabFontCache, tabFontN = {}, 0
local function coloredTabFont(path, size, flags, r, g, b)
	if not path then return nil end
	local key = path .. "|" .. tostring(size) .. "|" .. tostring(flags or "") .. "|" .. r .. "," .. g .. "," .. b
	local o = tabFontCache[key]
	if o == nil then
		tabFontN = tabFontN + 1
		local f = _G.CreateFont("LibLocaleOverrideTabFont" .. tabFontN)
		f:SetFont(path, size or 12, flags or "")
		if f:GetFont() then          -- verify via GetFont, NOT SetFont's unreliable boolean
			f:SetTextColor(r, g, b)
			o = f
		else
			o = false                -- font failed to load; caller falls back to stock objects
		end
		tabFontCache[key] = o
	end
	return o or nil
end

-- ONE applicator for an AceGUI TabGroup's tab-button fonts, used by both the apply path
-- (bundled locale font) and the release path (restore AceGUI's stock fonts). A tab is a
-- Button whose text font comes from its Normal/Highlight/Disabled font OBJECTS, not the
-- fontstring, so we set all three + the fontstring. Centralised so a fix lands in one place.
local function applyTabFonts(tg, normalObj, highlightObj, disabledObj, fsObj)
	for _, tab in pairs(tg.tabs or {}) do
		if type(tab) == "table" then
			if tab.SetNormalFontObject    then tab:SetNormalFontObject(normalObj) end
			if tab.SetHighlightFontObject then tab:SetHighlightFontObject(highlightObj) end
			if tab.SetDisabledFontObject  then tab:SetDisabledFontObject(disabledObj) end
			local tfs = tab.text or tab.Text   -- older embedded Ace3 exposed only tab.Text
			if tfs and tfs.SetFontObject then tfs:SetFontObject(fsObj) end
		end
	end
end

--- Keep an AceGUI TabGroup's tab buttons fonted for `addon`'s active override locale,
--- automatically and for the life of the widget -- call this ONCE right after creating
--- the TabGroup and never hand-font the strip again.
---
--- A tab is a BUTTON, and a button's text font is governed by its Normal / Highlight /
--- Disabled font OBJECTS (AceGUI sets all three to GameFont*Small in CreateTab), NOT by
--- the fontstring. On a non-native client those default objects lack CJK / Indic / Arabic
--- glyphs, so the moment a tab changes state -- HOVER applies the Highlight object,
--- SELECT disables the tab and applies the Disabled object -- the text reverts to boxes,
--- even though the fresh build looked fine (that's the "hovering a tab turns it into
--- blocks" bug). Setting only the fontstring can't survive a state change. So for a
--- locale WITH a bundled font we set all three button font objects (and the fontstring,
--- for the immediate paint) to the bundled object, on every SetTabs/BuildTabs/SelectTab,
--- so every state renders. Locales with NO bundled font (Latin / client-native) RESET the
--- tab fonts to AceGUI's stock objects -- not "leave as-is", because switching FROM a
--- bundled locale back to Latin must clear the bundled font or the Latin text boxes. The
--- per-instance binding is cleared on release so a pooled reuse never inherits this locale.
---   opts.base = base Font object the bundled glyphs are sized/flagged from (default GameFontNormalSmall)
function lib:AttachTabGroupFont(addon, tg, opts)
	if not (tg and tg.SelectTab) then return end
	tg._lloFontAddon = addon
	tg._lloFontBase  = (opts and opts.base) or _G.GameFontNormalSmall
	local libRef = self
	local function refont()
		local a = tg._lloFontAddon
		if not a then return end
		-- Bundled font OBJECT for the active locale, sized to the base tab font. nil for a
		-- Latin / client-native locale (its script renders in the stock font).
		local path = libRef:GetFont(a)
		local normalObj, selObj
		if path then
			local _, size, flags = tg._lloFontBase:GetFont()
			-- TWO colour-matched bundled objects, not one. AceGUI paints an unselected
			-- (enabled) tab through its Normal object and the selected tab through its
			-- Disabled object, which SelectTab forces to GameFontHighlightSmall (white);
			-- the gold/white distinction lives entirely in those object colours. Collapsing
			-- all states to a single colourless bundled object made a deselected tab stay
			-- white, so mirror the stock Normal (gold) and Highlight (white) colours onto
			-- the bundled font instead.
			local nr, ng, nb = _G.GameFontNormalSmall:GetTextColor()
			local wr, wg, wb = _G.GameFontHighlightSmall:GetTextColor()
			normalObj = coloredTabFont(path, size or 12, flags, nr, ng, nb)
			selObj    = coloredTabFont(path, size or 12, flags, wr, wg, wb)
		end
		if normalObj and selObj then
			-- Normal = gold (unselected/enabled), Highlight = white (hover), Disabled =
			-- white (the selected/disabled tab), fontstring = gold for the immediate paint.
			-- Re-applied after every SelectTab, so a deselected tab returns to gold.
			applyTabFonts(tg, normalObj, selObj, selObj, normalObj)
		else
			-- No bundled font for the active locale (Latin) -- RESET to AceGUI's stock tab
			-- fonts. Must NOT early-return: switching FROM a bundled locale (e.g. Bengali)
			-- TO English would otherwise leave the Bengali font objects on the buttons and
			-- box the Latin text. Same restore the release path uses.
			applyTabFonts(tg, _G.GameFontNormalSmall, _G.GameFontHighlightSmall, _G.GameFontHighlightSmall, _G.GameFontNormalSmall)
		end
	end
	-- AceGUI sizes each tab and assigns it to a row from GetFontString():GetStringWidth(),
	-- measured during BuildTabs. WoW does NOT shape complex scripts, so the bundled font's
	-- matra/mark advances collapse under GetStringWidth -- it reports far less than the width
	-- the client actually paints. If AceGUI measures the tabs while they carry the bundled
	-- font it sizes them too narrow, over-packs the first row, and the painted (wider) labels
	-- spill past the window edge. So for a bundled-font locale we force the tabs into the BASE
	-- (client) font for the DURATION of AceGUI's measurement -- the base font advances every
	-- codepoint, a close proxy for the painted bundled width -- then swap to the bundled font
	-- for display once the widths and rows are set. This runs for EVERY build (the initial one,
	-- AceGUI's own next-frame OnUpdate re-layout, and SetTabs), so the rows are always packed
	-- to a width close to what gets painted.
	if not tg._lloFontHooked then
		tg._lloFontHooked = true
		for _, m in ipairs({ "BuildTabs", "SetTabs" }) do
			local orig = tg[m]
			if type(orig) == "function" then
				tg[m] = function(w, ...)
					if libRef:GetFont(tg._lloFontAddon) then
						applyTabFonts(tg, _G.GameFontNormalSmall, _G.GameFontHighlightSmall,
							_G.GameFontHighlightSmall, _G.GameFontNormalSmall)
					end
					local r = orig(w, ...)
					refont()
					return r
				end
			end
		end
		-- SelectTab re-sets the selected tab's Disabled font object to GameFontHighlightSmall
		-- (PanelTemplates_SelectTab), so we must re-assert AFTER it.
		local origSelect = tg.SelectTab
		tg.SelectTab = function(w, ...) local r = origSelect(w, ...); refont(); return r end
		-- Route release cleanup through the shared clean-release: unbind the locale and
		-- restore AceGUI's stock tab fonts (CreateTab's defaults) via the same applicator,
		-- so the pooled TabGroup -- shared across every addon -- can't carry our bundled
		-- (non-Latin) font objects into the next addon that recycles it.
		libRef:HookCleanRelease(tg, function(w)
			w._lloFontAddon = nil
			applyTabFonts(w, _G.GameFontNormalSmall, _G.GameFontHighlightSmall, _G.GameFontHighlightSmall, _G.GameFontNormalSmall)
		end, "lloTabFont")
	end
	refont()   -- initial pass
end
