-- charset-ok: a locale library's script-matching specs. Non-Latin characters appear only in
-- comments naming which script an ASCII byte-escape fixture spells; the fixtures themselves live
-- in Tests/llo_helpers.lua as escapes. Dev-only file -- `Tests` is ignored by the packager.
--
-- Font RESOLUTION: which bundled font a given piece of text or a given active locale resolves to.
-- This is the half of the font layer that is pure data and string matching, so it is fully
-- assertable offline -- unlike the width arithmetic, which depends on metrics the harness
-- deliberately does not model faithfully.
--
-- The rule the matchers encode, and the reason each one is byte-ranged rather than "does it look
-- foreign": each bundled font carries ONLY its own script (plus Latin and digits). Routing text to
-- the wrong bundled font does not degrade gracefully -- every glyph outside that font renders as a
-- box. So a matcher that is too GREEDY is worse than one that never matches at all, which is why
-- shared-Han and Latin-1 deliberately resolve to nil.
local H = dofile("Tests/llo_helpers.lua")
local lib, T = H.lib, H.text

local FONT_DIR = "Interface\\AddOns\\LibLocaleOverride\\fonts\\"

describe("lib.scripts / lib.scriptOrder", function()
	it("orders Latin LAST, so a mixed string resolves to its non-Latin script", function()
		assert.equal("Latin", lib.scriptOrder[#lib.scriptOrder])
	end)

	it("names every script in scripts, and every script in scriptOrder -- no orphans either way", function()
		local inOrder = {}
		for _, name in ipairs(lib.scriptOrder) do
			assert.is_table(lib.scripts[name], "scriptOrder names '" .. name .. "', lib.scripts does not")
			inOrder[name] = true
		end
		for name in pairs(lib.scripts) do
			-- A script missing from scriptOrder is unreachable from FontForText: it would still be
			-- consulted by localeScript for an ACTIVE locale, so the file would look fine, while
			-- per-text routing silently never chose it.
			assert.is_true(inOrder[name], "lib.scripts has '" .. name .. "' but scriptOrder does not")
		end
	end)

	it("points every localeScript row at a real script", function()
		for code, name in pairs(lib.localeScript) do
			assert.is_table(lib.scripts[name], code .. " maps to unknown script '" .. tostring(name) .. "'")
		end
	end)

	it("keeps every bundled font under the library's own fonts/ tree", function()
		for name, s in pairs(lib.scripts) do
			assert.equal(FONT_DIR, s.font:sub(1, #FONT_DIR), name .. " points outside fonts/")
			assert.equal(".ttf", s.font:sub(-4), name .. " is not a .ttf")
		end
	end)

	it("survives a nil or empty string in every matcher", function()
		for name, s in pairs(lib.scripts) do
			assert.is_false(s.match(nil), name .. " matched nil")
			assert.is_false(s.match(""), name .. " matched the empty string")
		end
	end)
end)

describe("lib:FontForText", function()
	local addon
	before_each(function()
		H.reset()
		addon = H.addon()
		lib:RegisterLocale(addon, "enUS", { K = "en" }, true)
	end)

	it("returns nil for nothing to font", function()
		assert.is_nil(lib:FontForText(addon, nil))
		assert.is_nil(lib:FontForText(addon, ""))
	end)

	it("routes each script to its own bundled font", function()
		local cases = {
			{ T.thai,       "Thai" },
			{ T.devanagari, "Devanagari" },
			{ T.bengali,    "Bengali" },
			{ T.tamil,      "Tamil" },
			{ T.telugu,     "Telugu" },
			{ T.gurmukhi,   "Gurmukhi" },
			{ T.hebrew,     "Hebrew" },
			{ T.arabic,     "Arabic" },
			{ T.cyrillic,   "Cyrillic" },
			{ T.japanese,   "Japanese" },
			{ T.korean,     "Korean" },
			{ T.latinExt,   "Latin" },
		}
		for _, case in ipairs(cases) do
			assert.equal(lib.scripts[case[2]].font, lib:FontForText(addon, case[1]), case[2])
		end
	end)

	-- Han ideographs are shared between Simplified, Traditional and Japanese kanji, so they CANNOT
	-- be told apart by codepoint. A per-text matcher would misroute and could box a variant-only
	-- glyph, so both Chinese matchers return false by construction and Han is left to the client
	-- font. The tab strip picks the right one from the ACTIVE locale instead.
	it("leaves shared Han alone rather than guessing Simplified or Traditional", function()
		assert.is_nil(lib:FontForText(addon, T.han))
		assert.is_false(lib.scripts.ChineseSimplified.match(T.han))
		assert.is_false(lib.scripts.ChineseTraditional.match(T.han))
	end)

	-- The client font renders Latin-1 perfectly well. Matching it would switch German, French and
	-- Spanish onto a bundled font for no benefit at all.
	it("leaves Latin-1 accents to the client font", function()
		assert.is_nil(lib:FontForText(addon, T.latin1))
		assert.is_nil(lib:FontForText(addon, "plain ASCII 123"))
	end)

	-- The danda (U+0964) is sentence punctuation SHARED across the North-Indic scripts, but Unicode
	-- files it in the DEVANAGARI block -- which is checked before Bengali. Without the strip, a
	-- Bengali line ending in a danda matched Devanagari, and the Devanagari font has no Bengali
	-- glyphs, so every letter in the line rendered as a box.
	it("strips the shared danda before detecting the script", function()
		assert.equal(lib.scripts.Bengali.font, lib:FontForText(addon, T.bengali .. T.danda))
		assert.equal(lib.scripts.Gurmukhi.font, lib:FontForText(addon, T.gurmukhi .. T.doubleDanda))
		-- ...and real Devanagari still resolves to Devanagari, because it has its own letters too.
		assert.equal(lib.scripts.Devanagari.font, lib:FontForText(addon, T.devanagari .. T.danda))
	end)

	it("returns nil for text that is ONLY dandas -- the probe empties out", function()
		assert.is_nil(lib:FontForText(addon, T.danda .. T.doubleDanda))
	end)

	it("prefers the non-Latin script when a string mixes Latin-extended with another script", function()
		assert.equal(lib.scripts.Thai.font, lib:FontForText(addon, T.latinExt .. " " .. T.thai))
	end)

	it("lets a per-addon RegisterFont override win over the built-in font", function()
		lib:RegisterFont(addon, "thTH", "Interface\\AddOns\\Mine\\my-thai.ttf")
		assert.equal("Interface\\AddOns\\Mine\\my-thai.ttf", lib:FontForText(addon, T.thai))
	end)

	-- arSA, urPK and faIR all render in the Arabic script, so "which override applies" is ambiguous
	-- unless the ACTIVE locale breaks the tie.
	it("prefers the ACTIVE locale's override when several codes share one script", function()
		lib:RegisterLocale(addon, "faIR", { K = "fa" })
		lib:RegisterFont(addon, "arSA", "Interface\\AddOns\\Mine\\ar.ttf")
		lib:RegisterFont(addon, "faIR", "Interface\\AddOns\\Mine\\fa.ttf")
		lib:SetOverride(addon, "faIR")
		assert.equal("Interface\\AddOns\\Mine\\fa.ttf", lib:FontForText(addon, T.arabic))
	end)

	it("falls back to ANY registered override for the script when the active locale has none", function()
		lib:RegisterFont(addon, "urPK", "Interface\\AddOns\\Mine\\ur.ttf")
		lib:SetOverride(addon, "enUS")   -- active locale is Latin, so no per-code preference applies
		assert.equal("Interface\\AddOns\\Mine\\ur.ttf", lib:FontForText(addon, T.arabic))
	end)

	it("ignores an override registered for a DIFFERENT script", function()
		lib:RegisterFont(addon, "thTH", "Interface\\AddOns\\Mine\\th.ttf")
		assert.equal(lib.scripts.Hebrew.font, lib:FontForText(addon, T.hebrew))
	end)

	it("works for an addon that has registered nothing at all", function()
		assert.equal(lib.scripts.Thai.font, lib:FontForText("NeverRegistered", T.thai))
	end)
end)

describe("lib:GetFont -- the ACTIVE locale's font", function()
	local addon
	before_each(function()
		H.reset()
		addon = H.addon()
		lib:RegisterLocale(addon, "enUS", { K = "en" }, true)
		lib:RegisterLocale(addon, "thTH", { K = "th" })
		lib:RegisterLocale(addon, "deDE", { K = "de" })
	end)

	it("returns the bundled font for a locale whose script needs one", function()
		lib:SetOverride(addon, "thTH")
		assert.equal(lib.scripts.Thai.font, lib:GetFont(addon))
	end)

	it("returns nil for a locale the client already renders", function()
		lib:SetOverride(addon, "deDE")
		assert.is_nil(lib:GetFont(addon))
	end)

	it("lazily builds, so it is safe before the first GetLocale", function()
		local fresh = H.addon()
		lib:RegisterLocale(fresh, "thTH", { K = "th" }, true)
		assert.equal(lib.scripts.Thai.font, lib:GetFont(fresh))
	end)

	it("returns nil for an unknown addon and for one with no resolvable locale", function()
		assert.is_nil(lib:GetFont("NeverRegistered"))
		assert.is_nil(lib:GetFont(H.addon()))
	end)

	it("prefers a per-addon RegisterFont for the active code", function()
		lib:RegisterFont(addon, "thTH", "Interface\\AddOns\\Mine\\th.ttf")
		lib:SetOverride(addon, "thTH")
		assert.equal("Interface\\AddOns\\Mine\\th.ttf", lib:GetFont(addon))
	end)

	-- Every WoW-native non-Latin locale is bundled too. As an OVERRIDE on a client that does not
	-- ship it, the client font lacks those glyphs (and AceGUI's raw SetFont kills the fallback
	-- chain), so "WoW supports this locale" is not the same as "this client can draw it".
	it("bundles the CJK / Hangul / Cyrillic locales as well, because an override is not a client", function()
		local expected = {
			koKR = "Korean", zhCN = "ChineseSimplified", zhTW = "ChineseTraditional",
			ruRU = "Cyrillic", jaJP = "Japanese",
		}
		for code, script in pairs(expected) do
			assert.equal(script, lib.localeScript[code], code)
		end
	end)
end)

describe("lib:FontObject -- the cached Font OBJECT layer", function()
	before_each(function() H.reset() end)

	it("returns nil for a nil path", function()
		assert.is_nil(lib:FontObject(nil))
	end)

	it("hands back the SAME object for the same path/size/flags", function()
		local a = lib:FontObject(lib.scripts.Thai.font, 12, "")
		local b = lib:FontObject(lib.scripts.Thai.font, 12, "")
		assert.equal(a, b)
	end)

	it("keys the cache on size and flags, not on the path alone", function()
		local a = lib:FontObject(lib.scripts.Thai.font, 12, "")
		local b = lib:FontObject(lib.scripts.Thai.font, 14, "")
		local c = lib:FontObject(lib.scripts.Thai.font, 12, "OUTLINE")
		assert.are_not.equal(a, b)
		assert.are_not.equal(a, c)
	end)

	it("applies the requested path, size and flags to the object it builds", function()
		local o = lib:FontObject(lib.scripts.Tamil.font, 15, "OUTLINE")
		local path, size, flags = o:GetFont()
		assert.equal(lib.scripts.Tamil.font, path)
		assert.equal(15, size)
		assert.equal("OUTLINE", flags)
	end)

	-- The load is verified through GetFont, NOT through SetFont's return value: on a Font OBJECT
	-- that boolean is unreliable across client versions, and gating on it fails CLOSED -- every
	-- bundled font would fall back and ALL non-Latin text would box.
	it("returns nil when the font file fails to load, and caches the failure", function()
		local built, realCreateFont = 0, _G.CreateFont
		_G.CreateFont = function(name)
			built = built + 1
			local o = realCreateFont(name)
			o.GetFont = function() return nil end   -- the client's answer for a missing .ttf
			return o
		end
		local ok, err = pcall(function()
			assert.is_nil(lib:FontObject("Interface\\AddOns\\Nope\\missing.ttf", 12, ""))
			assert.is_nil(lib:FontObject("Interface\\AddOns\\Nope\\missing.ttf", 12, ""))
			assert.equal(1, built)   -- the failure is cached; no second dead object is built
		end)
		_G.CreateFont = realCreateFont
		if not ok then error(err) end
	end)
end)

describe("lib:ApplyFontToString", function()
	local addon
	before_each(function()
		H.reset()
		addon = H.addon()
		lib:RegisterLocale(addon, "enUS", { K = "en" }, true)
		lib:RegisterLocale(addon, "thTH", { K = "th" })
	end)

	it("ignores anything that is not a FontString", function()
		lib:ApplyFontToString(nil, addon)
		lib:ApplyFontToString({}, addon)                       -- no SetFontObject
		lib:ApplyFontToString({ SetFontObject = function() end }, addon)   -- no GetFont
	end)

	it("fonts by the STRING'S OWN script by default, whatever the active locale is", function()
		local fs = H.fontString(H.text.thai)
		lib:ApplyFontToString(fs, addon)
		assert.equal(lib.scripts.Thai.font, (fs:GetFontObject():GetFont()))
	end)

	it("leaves a string with no bundled script untouched when no base is given", function()
		local fs = H.fontString("plain")
		lib:ApplyFontToString(fs, addon)
		assert.is_nil(fs:GetFontObject())
	end)

	it("drops a non-bundled string onto the supplied base object instead", function()
		local fs = H.fontString("plain")
		lib:ApplyFontToString(fs, addon, { base = _G.GameFontNormalSmall })
		assert.equal(_G.GameFontNormalSmall, fs:GetFontObject())
	end)

	it("byLocale fonts by the ADDON'S active locale rather than the text", function()
		local fs = H.fontString("English text")
		lib:SetOverride(addon, "thTH")
		lib:ApplyFontToString(fs, addon, { byLocale = true })
		assert.equal(lib.scripts.Thai.font, (fs:GetFontObject():GetFont()))
	end)

	-- The only unambiguous way to font a language-picker row: zhCN, zhTW and jaJP share Han, so the
	-- row's own TEXT cannot say which font it wants -- but the row's CODE can.
	it("localeCode fonts by an explicit code, ignoring both the text and the active locale", function()
		local fs = H.fontString("plain ASCII")
		lib:ApplyFontToString(fs, addon, { localeCode = "zhTW" })
		assert.equal(lib.scripts.ChineseTraditional.font, (fs:GetFontObject():GetFont()))
	end)

	it("localeCode for a locale that needs no bundled font falls through to the base", function()
		local fs = H.fontString(H.text.thai)
		lib:ApplyFontToString(fs, addon, { localeCode = "deDE", base = _G.GameFontNormalSmall })
		assert.equal(_G.GameFontNormalSmall, fs:GetFontObject())
	end)

	it("takes size and flags from the base object when it is not told otherwise", function()
		_G.GameFontNormalSmall:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
		local fs = H.fontString(H.text.thai)
		lib:ApplyFontToString(fs, addon, { base = _G.GameFontNormalSmall })
		local _, size, flags = fs:GetFontObject():GetFont()
		assert.equal(10, size)
		assert.equal("OUTLINE", flags)
	end)

	it("takes them from the fontstring itself when there is no base", function()
		local fs = H.fontString(H.text.thai)
		fs:SetFont("Fonts\\FRIZQT__.TTF", 18, "THICKOUTLINE")
		lib:ApplyFontToString(fs, addon)
		local _, size, flags = fs:GetFontObject():GetFont()
		assert.equal(18, size)
		assert.equal("THICKOUTLINE", flags)
	end)

	it("honours an explicit size and flags over both", function()
		local fs = H.fontString(H.text.thai)
		fs:SetFont("Fonts\\FRIZQT__.TTF", 18, "THICKOUTLINE")
		lib:ApplyFontToString(fs, addon, { size = 9, flags = "" })
		local _, size, flags = fs:GetFontObject():GetFont()
		assert.equal(9, size)
		assert.equal("", flags)
	end)

	-- Bundled faces render larger than the Western font at the same point size, so a dropdown row
	-- scales its bundled font down to sit level with the Latin rows around it.
	it("scales the bundled size", function()
		_G.GameFontNormalSmall:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
		local fs = H.fontString(H.text.thai)
		lib:ApplyFontToString(fs, addon, { base = _G.GameFontNormalSmall, scale = 0.90 })
		local _, size = fs:GetFontObject():GetFont()
		assert.equal(9, size)
	end)

	it("falls back to the base when the bundled font fails to load", function()
		local realCreateFont = _G.CreateFont
		_G.CreateFont = function(name)
			local o = realCreateFont(name)
			o.GetFont = function() return nil end
			return o
		end
		local fs = H.fontString(H.text.thai)
		local ok, err = pcall(function()
			-- A size nothing else in this file uses, so the shared object cache cannot answer first.
			lib:ApplyFontToString(fs, addon, { base = _G.GameFontNormalSmall, size = 37 })
			assert.equal(_G.GameFontNormalSmall, fs:GetFontObject())
		end)
		_G.CreateFont = realCreateFont
		if not ok then error(err) end
	end)
end)
