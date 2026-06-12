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

-- Re-font one pulled-up option row to the addon's active font (or restore its
-- default for a Latin locale) and -- once per pooled row -- wrap its release so
-- the shared pool always gets the row back at its original font.
local function decorateItem(addon, item)
	local fs = item and item.text
	if not (fs and fs.SetFont and fs.GetFont) then return end

	if not item._lloRelHooked then
		item._lloRelHooked = true
		-- Capture the row's default font object now (fresh rows use GameFontNormalSmall);
		-- fall back to it explicitly so a restore never lands on nil.
		item._lloOrigObj = (fs.GetFontObject and fs:GetFontObject()) or _G.GameFontNormalSmall
		local origRelease = item.OnRelease
		item.OnRelease = function(it)
			-- AceGUI discipline: return pooled widgets clean. Restore the row's
			-- default font so the next dropdown to recycle it -- ours or anyone
			-- else's -- never inherits our locale font.
			local t = it.text
			local obj = it._lloOrigObj or _G.GameFontNormalSmall
			if t and obj and t.SetFontObject then t:SetFontObject(obj) end
			if origRelease then return origRelease(it) end
		end
	end

	-- Font each row by its OWN script, independent of the active UI locale: the
	-- picker lists many languages at once, so "ไทย" must use the Thai font even when
	-- the UI locale is English. Rows whose script the client font already renders
	-- (Latin / Cyrillic / CJK / Hangul) are put back on their default face.
	local font = addon and lib:FontForText(addon, fs.GetText and fs:GetText())
	if font then
		local _, size, flags = fs:GetFont()
		if size then fs:SetFont(font, size, flags) end
	else
		local obj = item._lloOrigObj or _G.GameFontNormalSmall
		if obj and fs.SetFontObject then fs:SetFontObject(obj) end
	end
end

--- Register (once) an AceGUI dropdown widget type bound to `addon` whose display
--- AND pullout render the addon's active override font. Returns the type name to
--- use as an AceConfig option's `dialogControl`, or nil when AceGUI-3.0 isn't
--- available (the caller should then leave the option as a stock "select").
function lib:RegisterAceGUIDropdown(addon)
	-- Resolved at call time (not file load) so load order vs AceGUI never matters.
	local GUI = LibStub("AceGUI-3.0", true)
	if not GUI or not GUI.WidgetRegistry then return nil end
	local stock = GUI.WidgetRegistry["Dropdown"]
	if not stock then return nil end

	local typeName = "LibLocaleOverride_Dropdown_" .. tostring(addon)
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
			-- Font the selected value by its own script (so "Русский" shows in the
			-- client font and "ไทย" in Sarabun) regardless of the active UI locale.
			local font = lib:FontForText(addon, fs.GetText and fs:GetText())
			if font then
				local _, size, flags = fs:GetFont()
				if size then fs:SetFont(font, size, flags) end
			else
				local obj = widget._lloDisplayOrig or _G.GameFontNormalSmall
				if obj and fs.SetFontObject then fs:SetFontObject(obj) end
			end
		end

		local function refontPullout()
			local p = widget.pullout
			if not p or not p.items then return end
			for _, item in ipairs(p.items) do
				decorateItem(addon, item)
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

		-- SetList (re)builds the option rows; SetValue/AddItem change the display
		-- or add a row. Re-font after each so a freshly built menu localizes.
		for _, m in ipairs({ "SetList", "AddItem", "SetValue" }) do
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
