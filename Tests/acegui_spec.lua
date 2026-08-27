-- LibLocaleOverride-AceGUI-1.0: the pooled-widget clean-release hook, pullout open/close tracking,
-- the language-picker data helpers, the font-aware Dropdown widget type and the TabGroup tab fonts.
--
-- These drive the REAL AceGUI-3.0 from the installed Ace3, not a stand-in. That is the whole point
-- of this file: every defect this integration has ever shipped came from AceGUI's SHARED, GLOBAL
-- widget pools -- one addon's font riding a recycled row into another addon's dropdown -- and a
-- model of AceGUI cannot fail that class of bug, because the model has no pool to leak through.
local H = dofile("Tests/llo_helpers.lua")
local lib, T = H.lib, H.text
local ace = require("env.ace")

ace.load("AceGUI-3.0")
local GUI = LibStub("AceGUI-3.0")

describe("lib:HookCleanRelease", function()
	before_each(function() H.reset() end)

	it("ignores a nil widget and a non-function cleanup", function()
		lib:HookCleanRelease(nil, function() end, "k")
		local w = {}
		lib:HookCleanRelease(w, "not a function", "k")
		assert.is_nil(w._lloCleanReleaseHooked)
	end)

	it("runs the cleanup when AceGUI releases the widget, then the widget's own OnRelease", function()
		local order = {}
		local w = { OnRelease = function() order[#order + 1] = "orig" end }
		lib:HookCleanRelease(w, function() order[#order + 1] = "clean" end, "k")
		w:OnRelease()
		assert.same({ "clean", "orig" }, order)
	end)

	it("works on a widget that had no OnRelease of its own", function()
		local ran = false
		local w = {}
		lib:HookCleanRelease(w, function() ran = true end, "k")
		w:OnRelease()
		assert.is_true(ran)
	end)

	-- The cleanup set is KEYED, not an array, precisely so re-decorating the same pooled widget on
	-- every render replaces rather than queues. An array here grows without bound for the lifetime
	-- of the client.
	it("replaces rather than queues when the same key is registered again", function()
		local n = 0
		local w = {}
		for _ = 1, 5 do lib:HookCleanRelease(w, function() n = n + 1 end, "same") end
		w:OnRelease()
		assert.equal(1, n)
	end)

	it("runs every DISTINCT key's cleanup", function()
		local ran = {}
		local w = {}
		lib:HookCleanRelease(w, function() ran.a = true end, "a")
		lib:HookCleanRelease(w, function() ran.b = true end, "b")
		w:OnRelease()
		assert.same({ a = true, b = true }, ran)
	end)

	it("keys on the function itself when no key is given", function()
		local n = 0
		local fn = function() n = n + 1 end
		local w = {}
		lib:HookCleanRelease(w, fn)
		lib:HookCleanRelease(w, fn)
		w:OnRelease()
		assert.equal(1, n)
	end)

	it("hooks OnRelease only ONCE, however many cleanups are added", function()
		local w = { OnRelease = function() end }
		lib:HookCleanRelease(w, function() end, "a")
		local hooked = w.OnRelease
		lib:HookCleanRelease(w, function() end, "b")
		assert.equal(hooked, w.OnRelease)
	end)

	-- One failing cleanup must not block the others, nor the widget's own release: a widget that
	-- never completes release is a widget that never returns to the pool.
	it("isolates a cleanup that errors", function()
		local ran = {}
		local w = { OnRelease = function() ran.orig = true end }
		lib:HookCleanRelease(w, function() error("boom") end, "bad")
		lib:HookCleanRelease(w, function() ran.good = true end, "good")
		w:OnRelease()
		assert.same({ good = true, orig = true }, ran)
	end)

	it("passes the widget through, and returns the original's return value", function()
		local seen
		local w = { OnRelease = function() return "returned" end }
		lib:HookCleanRelease(w, function(widget) seen = widget end, "k")
		assert.equal("returned", w:OnRelease())
		assert.equal(w, seen)
	end)
end)

describe("pullout open/close tracking", function()
	before_each(function()
		H.reset()
		lib._pulloutDepth = 0
		lib._pulloutCloseCbs = {}
	end)

	it("reports nothing open to start with", function()
		assert.is_false(lib:IsAnyPulloutOpen())
	end)

	it("ignores a non-function close subscriber", function()
		lib:OnPulloutClose("not a function")
		assert.equal(0, #lib._pulloutCloseCbs)
	end)

	-- A consumer registers this ONCE and re-checks its own pending state on each fire, so an
	-- accidental re-registration must not grow a list that lives for the whole session.
	it("dedups a close subscriber", function()
		local fn = function() end
		lib:OnPulloutClose(fn)
		lib:OnPulloutClose(fn)
		assert.equal(1, #lib._pulloutCloseCbs)
	end)
end)

describe("language-picker data", function()
	before_each(function() H.reset() end)

	it("AllLanguageCodes lists every code the library has names for, including auto", function()
		local codes, seen = lib:AllLanguageCodes(), {}
		for _, c in ipairs(codes) do seen[c] = true end
		assert.is_true(seen.auto)
		assert.is_true(seen.enUS)
		assert.is_true(seen.thTH)

		local expected = 0
		for _ in pairs(lib.languageNames.enUS) do expected = expected + 1 end
		assert.equal(expected, #codes)   -- the enUS row is the offerable set, in full
	end)

	it("LanguagePickerValues maps each code to its NATIVE endonym", function()
		local values = lib:LanguagePickerValues({ "deDE", "frFR" })
		assert.equal(lib.languageNames.deDE.deDE, values.deDE)
		assert.equal(lib.languageNames.frFR.frFR, values.frFR)
	end)

	it("falls back to the English name, then to the code itself", function()
		local values = lib:LanguagePickerValues({ "auto", "xxYY" })
		assert.equal(lib.languageNames.enUS.auto, values.auto)   -- no languageNames.auto table
		assert.equal("xxYY", values.xxYY)                        -- nothing knows this code at all
	end)

	-- An RTL endonym has to be shaped at BUILD time here, because these strings go straight into an
	-- AceConfig `values` table and nothing downstream will shape them.
	it("shapes an RTL endonym", function()
		local values = lib:LanguagePickerValues({ "heIL", "arSA" })
		assert.equal(lib:Shape(lib.languageNames.heIL.heIL), values.heIL)
		assert.equal(lib:Shape(lib.languageNames.arSA.arSA), values.arSA)
		assert.are_not.equal(lib.languageNames.heIL.heIL, values.heIL)   -- it really did change
	end)
end)

describe("lib:RegisterAceGUIDropdown", function()
	local addon
	before_each(function()
		H.reset()
		addon = H.addon()
		lib:RegisterLocale(addon, "enUS", { K = "en" }, true)
		lib:RegisterLocale(addon, "thTH", { K = "th" })
	end)

	it("returns nil when AceGUI is not available, so the caller keeps a stock select", function()
		local realLibStub = _G.LibStub
		_G.LibStub = function(major, silent)
			if major == "AceGUI-3.0" then return nil end
			return realLibStub(major, silent)
		end
		local ok, err = pcall(function()
			assert.is_nil(lib:RegisterAceGUIDropdown(addon))
		end)
		_G.LibStub = realLibStub
		if not ok then error(err) end
	end)

	it("returns nil when AceGUI has no stock Dropdown to decorate", function()
		local stock = GUI.WidgetRegistry["Dropdown"]
		GUI.WidgetRegistry["Dropdown"] = nil
		local ok, err = pcall(function()
			assert.is_nil(lib:RegisterAceGUIDropdown(addon))
		end)
		GUI.WidgetRegistry["Dropdown"] = stock
		if not ok then error(err) end
	end)

	it("registers a type bound to the addon, and is idempotent", function()
		local name = lib:RegisterAceGUIDropdown(addon)
		assert.equal("LibLocaleOverride_Dropdown_" .. addon, name)
		assert.is_function(GUI.WidgetRegistry[name])
		assert.equal(name, lib:RegisterAceGUIDropdown(addon))
	end)

	-- Per-addon, not one shared type: a single shared widget type could not tell which addon owns a
	-- given instance, so it could not know whose font to apply.
	it("gives each addon and each mode its own type", function()
		local other = H.addon()
		assert.are_not.equal(lib:RegisterAceGUIDropdown(addon), lib:RegisterAceGUIDropdown(other))
		assert.equal("LibLocaleOverride_Dropdown_" .. addon .. "_lang",
			lib:RegisterAceGUIDropdown(addon, { languagePicker = true }))
	end)

	it("fonts the selected value by its own script when SetText is called", function()
		local name = lib:RegisterAceGUIDropdown(addon)
		local w = GUI:Create(name)
		w:SetText(T.thai)
		assert.equal(lib.scripts.Thai.font, (w.text:GetFontObject():GetFont()))
		GUI:Release(w)
	end)

	it("fonts the open list's rows, each by its OWN script", function()
		local name = lib:RegisterAceGUIDropdown(addon)
		local w = GUI:Create(name)
		w:SetList({ a = T.thai, b = T.bengali }, { "a", "b" })
		local byText = {}
		for _, item in ipairs(w.pullout.items) do byText[item.text:GetText()] = item end
		assert.equal(lib.scripts.Thai.font, (byText[T.thai].text:GetFontObject():GetFont()))
		assert.equal(lib.scripts.Bengali.font, (byText[T.bengali].text:GetFontObject():GetFont()))
		GUI:Release(w)
	end)

	-- AceGUI pools these rows GLOBALLY and its OnAcquire does not reset the font, so a row handed
	-- back carrying our font bleeds it into whatever dropdown recycles it next -- in any addon.
	it("hands every pooled row back on the client default font", function()
		local name = lib:RegisterAceGUIDropdown(addon)
		local w = GUI:Create(name)
		w:SetList({ a = T.thai }, { "a" })
		local item = w.pullout.items[1]
		assert.equal(lib.scripts.Thai.font, (item.text:GetFontObject():GetFont()))
		GUI:Release(w)
		assert.equal(_G.GameFontNormalSmall, item.text:GetFontObject())
	end)

	-- A consumer that live-updates an AceConfig panel (NotifyChange) has to DEFER while a list is
	-- open, because rebuilding the panel yanks the open list shut from under the user's cursor.
	-- That is what the depth counter is for, and it is counted rather than a boolean because these
	-- pullouts come from a shared pool.
	describe("pullout open/close tracking, driven through a real pullout", function()
		it("counts an open and a close, and fires the close subscribers at zero", function()
			local name = lib:RegisterAceGUIDropdown(addon)
			local w = GUI:Create(name)
			w:SetList({ a = T.thai }, { "a" })

			local closes = 0
			lib:OnPulloutClose(function() closes = closes + 1 end)

			assert.is_false(lib:IsAnyPulloutOpen())
			w.pullout:Open("TOPLEFT", w.frame, "BOTTOMLEFT", 0, 0)
			assert.is_true(lib:IsAnyPulloutOpen())
			w.pullout:Close()
			assert.is_false(lib:IsAnyPulloutOpen())
			assert.equal(1, closes)
			GUI:Release(w)
		end)

		it("does not double-count a re-Open while already open", function()
			local name = lib:RegisterAceGUIDropdown(addon)
			local w = GUI:Create(name)
			w:SetList({ a = T.thai }, { "a" })
			w.pullout:Open("TOPLEFT", w.frame, "BOTTOMLEFT", 0, 0)
			w.pullout:Open("TOPLEFT", w.frame, "BOTTOMLEFT", 0, 0)
			w.pullout:Close()
			assert.is_false(lib:IsAnyPulloutOpen())   -- one Close balanced both Opens
			GUI:Release(w)
		end)

		-- Released while still flagged open: without the balancing cleanup a consumer deferring
		-- "while a list is open" would wait forever on a list that no longer exists.
		it("balances the counter when a still-open pullout is released", function()
			local name = lib:RegisterAceGUIDropdown(addon)
			local w = GUI:Create(name)
			w:SetList({ a = T.thai }, { "a" })
			local pullout = w.pullout
			pullout:Open("TOPLEFT", w.frame, "BOTTOMLEFT", 0, 0)
			assert.is_true(lib:IsAnyPulloutOpen())
			pullout:OnRelease()
			assert.is_false(lib:IsAnyPulloutOpen())
			assert.is_false(pullout._lloOwned)   -- and a foreign reuse starts clean
			GUI:Release(w)
		end)

		-- The counter is scoped through `_lloOwned` so a FOREIGN addon's dropdown recycling this
		-- pooled pullout cannot tick it -- otherwise IsAnyPulloutOpen would simply lie.
		it("ignores an Open on a pullout that is not currently ours", function()
			local name = lib:RegisterAceGUIDropdown(addon)
			local w = GUI:Create(name)
			w:SetList({ a = T.thai }, { "a" })
			w.pullout._lloOwned = false
			w.pullout:Open("TOPLEFT", w.frame, "BOTTOMLEFT", 0, 0)
			assert.is_false(lib:IsAnyPulloutOpen())
			w.pullout:Close()
			GUI:Release(w)
		end)
	end)

	-- An opt-in global a developer sets by hand while chasing a font that will not take.
	it("prints a per-row diagnostic when LibLocaleOverride_DEBUG is set", function()
		local name = lib:RegisterAceGUIDropdown(addon)
		_G.LibLocaleOverride_DEBUG = true
		local w = GUI:Create(name)
		local ok, err = pcall(function()
			w:SetList({ a = T.thai }, { "a" })
			assert.is_true(#H.wow.chat > 0)   -- print() writes into DEFAULT_CHAT_FRAME offline
		end)
		_G.LibLocaleOverride_DEBUG = nil
		GUI:Release(w)
		if not ok then error(err) end
	end)

	it("re-fonts after AddItem and SetValue too", function()
		local name = lib:RegisterAceGUIDropdown(addon)
		local w = GUI:Create(name)
		w:SetList({ a = "plain" }, { "a" })
		w:AddItem("b", T.telugu)
		local last = w.pullout.items[#w.pullout.items]
		assert.equal(lib.scripts.Telugu.font, (last.text:GetFontObject():GetFont()))
		w:SetValue("a")
		GUI:Release(w)
	end)

	describe("language-picker mode", function()
		it("sorts A-Z by the column-1 name, with auto pinned first", function()
			local name = lib:RegisterAceGUIDropdown(addon, { languagePicker = true })
			local w = GUI:Create(name)
			w:SetList(lib:LanguagePickerValues({ "auto", "deDE", "arSA", "enUS" }))
			local order = {}
			for i, item in ipairs(w.pullout.items) do
				order[i] = item.userdata and item.userdata.value or item.value
			end
			assert.equal("auto", order[1])
			-- Arabic, English, German -- the English exonyms, sorted, because the active locale is
			-- enUS and its names are what column 1 shows.
			assert.same({ "auto", "arSA", "enUS", "deDE" }, order)
			GUI:Release(w)
		end)

		it("renders column 1 as the exonym and column 2 as the endonym", function()
			local name = lib:RegisterAceGUIDropdown(addon, { languagePicker = true })
			local w = GUI:Create(name)
			w:SetList({ deDE = "ignored" }, { "deDE" })
			local item = w.pullout.items[1]
			assert.equal(lib.languageNames.enUS.deDE, item.text:GetText())
			assert.equal(lib.languageNames.deDE.deDE, item._lloCol2:GetText())
			GUI:Release(w)
		end)

		-- zhCN, zhTW and jaJP share Han, so a row's own TEXT cannot say which font it wants. The
		-- row's CODE can, and that is the only unambiguous answer.
		it("fonts column 2 by the ROW'S locale, not by its text", function()
			local name = lib:RegisterAceGUIDropdown(addon, { languagePicker = true })
			local w = GUI:Create(name)
			w:SetList({ zhTW = "ignored" }, { "zhTW" })
			local item = w.pullout.items[1]
			assert.equal(lib.scripts.ChineseTraditional.font, (item._lloCol2:GetFontObject():GetFont()))
			GUI:Release(w)
		end)

		-- "Single-column" cannot be asserted as `_lloCol2 == nil`: these rows come from AceGUI's
		-- SHARED pool, so an auto row is frequently a recycled row that already carries the extra
		-- fontstring from some earlier language row. What must hold is that nothing is SHOWN in it
		-- -- which is the property a player sees, and the one a nil check would miss entirely on a
		-- recycled row while passing on a fresh one.
		it("leaves the auto row single-column, even when it is a recycled row", function()
			local name = lib:RegisterAceGUIDropdown(addon, { languagePicker = true })
			local w = GUI:Create(name)
			w:SetList({ auto = "ignored" }, { "auto" })
			local item = w.pullout.items[1]
			assert.equal(lib.languageNames.enUS.auto, item.text:GetText())
			if item._lloCol2 then
				assert.equal("", item._lloCol2:GetText())
				assert.is_false(item._lloCol2:IsShown())
			end
			GUI:Release(w)
		end)

		-- The recycled-row case above is only worth having if it is actually reached, so drive it
		-- deliberately: build a language row, release it to the pool, then take an auto row from
		-- that same pool and check the leftover column is cleared rather than left showing German.
		it("clears a leftover second column when a language row is recycled as the auto row", function()
			local name = lib:RegisterAceGUIDropdown(addon, { languagePicker = true })
			local first = GUI:Create(name)
			first:SetList({ deDE = "ignored" }, { "deDE" })
			-- The callable `assert` both fails loudly and narrows the type for the language server;
			-- `assert.is_not_nil` does neither.
			local col2 = assert(first.pullout.items[1]._lloCol2)
			GUI:Release(first)

			local second = GUI:Create(name)
			second:SetList({ auto = "ignored" }, { "auto" })
			assert.equal("", col2:GetText())
			assert.is_false(col2:IsShown())
			GUI:Release(second)
		end)

		it("hides the second column when a pooled row is released", function()
			local name = lib:RegisterAceGUIDropdown(addon, { languagePicker = true })
			local w = GUI:Create(name)
			w:SetList({ deDE = "ignored" }, { "deDE" })
			local item = w.pullout.items[1]
			assert.equal(lib.languageNames.deDE.deDE, item._lloCol2:GetText())
			GUI:Release(w)
			assert.equal("", item._lloCol2:GetText())
			assert.is_false(item._lloCol2:IsShown())
		end)

		it("shapes an RTL exonym when the ACTIVE locale is RTL", function()
			lib:RegisterLocale(addon, "heIL", { K = "he" })
			lib:SetOverride(addon, "heIL")
			local name = lib:RegisterAceGUIDropdown(addon, { languagePicker = true })
			local w = GUI:Create(name)
			w:SetList({ deDE = "ignored" }, { "deDE" })
			assert.equal(lib:Shape(lib.languageNames.heIL.deDE), w.pullout.items[1].text:GetText())
			GUI:Release(w)
		end)

		it("fonts the selected value by the ACTIVE locale rather than its text", function()
			lib:SetOverride(addon, "thTH")
			local name = lib:RegisterAceGUIDropdown(addon, { languagePicker = true })
			local w = GUI:Create(name)
			w:SetText("English text")
			assert.equal(lib.scripts.Thai.font, (w.text:GetFontObject():GetFont()))
			GUI:Release(w)
		end)
	end)
end)

describe("lib:AttachTabGroupFont", function()
	local addon
	before_each(function()
		H.reset()
		addon = H.addon()
		lib:RegisterLocale(addon, "enUS", { K = "en" }, true)
		lib:RegisterLocale(addon, "thTH", { K = "th" })
	end)

	local function tabGroup()
		local tg = GUI:Create("TabGroup")
		tg:SetTabs({ { value = "a", text = "A" }, { value = "b", text = "B" } })
		return tg
	end

	it("ignores anything that is not a tab group", function()
		lib:AttachTabGroupFont(addon, nil)
		lib:AttachTabGroupFont(addon, {})
	end)

	-- A tab is a BUTTON, and a button's text font comes from its Normal / Highlight / Disabled font
	-- OBJECTS. Setting only the fontstring cannot survive a state change, which is the "hovering a
	-- tab turns it into blocks" bug.
	it("points every tab's state font objects at the bundled font", function()
		lib:SetOverride(addon, "thTH")
		local tg = tabGroup()
		lib:AttachTabGroupFont(addon, tg)
		for _, tab in pairs(tg.tabs) do
			assert.equal(lib.scripts.Thai.font, (tab:GetNormalFontObject():GetFont()))
			assert.equal(lib.scripts.Thai.font, (tab:GetHighlightFontObject():GetFont()))
			assert.equal(lib.scripts.Thai.font, (tab:GetDisabledFontObject():GetFont()))
		end
		GUI:Release(tg)
	end)

	-- The gold/white distinction lives entirely in the font objects' COLOURS: AceGUI paints an
	-- unselected tab through Normal and the selected one through Disabled. Collapsing both onto one
	-- colourless bundled object made every deselected tab stay white.
	it("keeps the stock gold/white colours on the bundled objects", function()
		lib:SetOverride(addon, "thTH")
		local gold  = { _G.GameFontNormalSmall:GetTextColor() }
		local white = { _G.GameFontHighlightSmall:GetTextColor() }
		local tg = tabGroup()
		lib:AttachTabGroupFont(addon, tg)
		local tab = select(2, next(tg.tabs))
		assert.same(gold,  { tab:GetNormalFontObject():GetTextColor() })
		assert.same(white, { tab:GetDisabledFontObject():GetTextColor() })
		GUI:Release(tg)
	end)

	-- Not "leave as-is": switching FROM a bundled locale back to English must CLEAR the bundled
	-- objects, or the Latin text boxes in the font that has no Latin coverage.
	it("resets to AceGUI's stock fonts for a locale that needs no bundled font", function()
		lib:SetOverride(addon, "thTH")
		local tg = tabGroup()
		lib:AttachTabGroupFont(addon, tg)
		lib:SetOverride(addon, "enUS")
		lib:AttachTabGroupFont(addon, tg)
		local tab = select(2, next(tg.tabs))
		assert.equal(_G.GameFontNormalSmall, tab:GetNormalFontObject())
		assert.equal(_G.GameFontHighlightSmall, tab:GetDisabledFontObject())
		GUI:Release(tg)
	end)

	-- SelectTab forces the selected tab's Disabled object to GameFontHighlightSmall
	-- (PanelTemplates_SelectTab), so the bundled font has to be re-asserted AFTER it.
	it("re-asserts the bundled font after SelectTab", function()
		lib:SetOverride(addon, "thTH")
		local tg = tabGroup()
		lib:AttachTabGroupFont(addon, tg)
		tg:SelectTab("b")
		for _, tab in pairs(tg.tabs) do
			assert.equal(lib.scripts.Thai.font, (tab:GetDisabledFontObject():GetFont()))
		end
		GUI:Release(tg)
	end)

	it("re-asserts after a rebuild through SetTabs", function()
		lib:SetOverride(addon, "thTH")
		local tg = tabGroup()
		lib:AttachTabGroupFont(addon, tg)
		tg:SetTabs({ { value = "c", text = "C" } })
		for _, tab in pairs(tg.tabs) do
			assert.equal(lib.scripts.Thai.font, (tab:GetNormalFontObject():GetFont()))
		end
		GUI:Release(tg)
	end)

	it("hooks the rebuild methods only once, however often it is attached", function()
		local tg = tabGroup()
		lib:AttachTabGroupFont(addon, tg)
		local hooked = tg.SelectTab
		lib:AttachTabGroupFont(addon, tg)
		assert.equal(hooked, tg.SelectTab)
		GUI:Release(tg)
	end)

	-- The TabGroup pool is shared across every addon, so a released group must not carry our
	-- bundled (non-Latin) objects into whatever recycles it next.
	it("unbinds the locale and restores stock fonts on release", function()
		lib:SetOverride(addon, "thTH")
		local tg = tabGroup()
		lib:AttachTabGroupFont(addon, tg)
		local tab = select(2, next(tg.tabs))
		GUI:Release(tg)
		assert.is_nil(tg._lloFontAddon)
		assert.equal(_G.GameFontNormalSmall, tab:GetNormalFontObject())
	end)

	it("takes the bundled size and flags from the supplied base object", function()
		local base = CreateFont("SpecTabBase")
		base:SetFont("Fonts\\FRIZQT__.TTF", 17, "OUTLINE")
		lib:SetOverride(addon, "thTH")
		local tg = tabGroup()
		lib:AttachTabGroupFont(addon, tg, { base = base })
		local tab = select(2, next(tg.tabs))
		local _, size, flags = tab:GetNormalFontObject():GetFont()
		assert.equal(17, size)
		assert.equal("OUTLINE", flags)
		GUI:Release(tg)
	end)

	it("falls back to the stock objects when the bundled font fails to load", function()
		lib:RegisterFont(addon, "thTH", "Interface\\AddOns\\Nope\\missing-tab.ttf")
		lib:SetOverride(addon, "thTH")
		local realCreateFont = _G.CreateFont
		_G.CreateFont = function(name)
			local o = realCreateFont(name)
			o.GetFont = function() return nil end
			return o
		end
		local tg = tabGroup()
		local ok, err = pcall(function()
			lib:AttachTabGroupFont(addon, tg)
			local tab = select(2, next(tg.tabs))
			assert.equal(_G.GameFontNormalSmall, tab:GetNormalFontObject())
		end)
		_G.CreateFont = realCreateFont
		GUI:Release(tg)
		if not ok then error(err) end
	end)
end)
