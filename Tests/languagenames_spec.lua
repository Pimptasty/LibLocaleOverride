-- LibLocaleOverride-LanguageNames: the canonical `lib.languageNames[displayLocale][langCode]`
-- table that backs the language picker's two columns.
--
-- This is 1,000 lines of hand- and machine-translated data, and the failure it produces is quiet:
-- a missing cell falls back to English, so a picker keeps working while silently showing the wrong
-- language's name -- and nobody running an English client can see it. The whole point of these
-- examples is that the SHAPE of the table is checked mechanically, because reading it cannot be.
--
-- What is NOT checked, and cannot be from here: whether any translation is CORRECT. The file's own
-- header says the first pass is machine-translated with native review pending. A spec can prove
-- every cell exists; only a speaker can prove it says the right thing.
local H = dofile("Tests/llo_helpers.lua")
local lib = H.lib

local names = lib.languageNames

local function keysOf(t)
	local out = {}
	for k in pairs(t) do out[#out + 1] = k end
	table.sort(out)
	return out
end

describe("lib.languageNames", function()
	it("exists, with an enUS row as the fallback every lookup lands on", function()
		assert.is_table(names)
		assert.is_table(names.enUS)
	end)

	-- Column 1 of a picker row is `languageNames[activeLocale][code]` with an enUS fallback. If a
	-- display locale is missing a code, that row silently shows English inside an otherwise fully
	-- translated list -- which reads as a translation bug in whoever's addon embedded the library.
	it("gives every display locale the SAME code set as enUS", function()
		local expected = keysOf(names.enUS)
		for locale, row in pairs(names) do
			assert.same(expected, keysOf(row), "display locale " .. locale .. " has a different code set")
		end
	end)

	it("offers 'auto' in every row -- it is a picker entry, not a language", function()
		for locale, row in pairs(names) do
			assert.is_string(row.auto, locale .. " has no 'auto' entry")
		end
	end)

	-- Column 2 is the NATIVE endonym, `languageNames[code][code]`. A code with no row of its own
	-- has no endonym at all and falls back to its English name, so the picker would show e.g.
	-- "German" in both columns.
	it("gives every offered language a row of its own, so column 2 has an endonym", function()
		for _, code in ipairs(keysOf(names.enUS)) do
			if code ~= "auto" then
				assert.is_table(names[code], "no row for '" .. code .. "': column 2 has no endonym")
				assert.is_string(names[code][code], "'" .. code .. "' has no name in its own language")
			end
		end
	end)

	it("has no row for a language it does not offer", function()
		for locale in pairs(names) do
			assert.is_string(names.enUS[locale], "row '" .. locale .. "' is not an offered language")
		end
	end)

	it("has no empty or whitespace-only name anywhere", function()
		for locale, row in pairs(names) do
			for code, name in pairs(row) do
				assert.is_string(name, locale .. "." .. code .. " is not a string")
				assert.are_not.equal("", (name:gsub("%s", "")), locale .. "." .. code .. " is blank")
			end
		end
	end)

	-- Codes written in Han ideographs, which are SHARED between Simplified, Traditional and Japanese
	-- kanji and therefore cannot be told apart by codepoint. Their per-text matchers return false by
	-- construction; the active locale routes them instead. Listed explicitly rather than skipped by
	-- a condition, so the next two examples both assert something for every code.
	local HAN_ONLY = { zhCN = true, zhTW = true, jaJP = true }

	-- The endonym is the one cell that must NOT be in English: it is the row's entire reason to
	-- exist. A non-Latin language whose endonym is still its English name is an untranslated cell
	-- that the enUS fallback would have produced anyway.
	-- EVERY LOOP BELOW COUNTS WHAT IT CHECKED AND ASSERTS THE COUNT IS NON-ZERO. Audit finding 9:
	-- each of these filters codes by `lib.localeScript`, so emptying that table, narrowing the
	-- filter, or renaming a script would leave the loop iterating and asserting NOTHING -- and the
	-- example would go green while its name makes a universal claim. The assertions are correct
	-- today; nothing was holding them to a non-empty universe. This is the same instinct the
	-- HAN_ONLY list above already applies, applied to its three neighbours.
	it("writes each non-Latin endonym in its own script", function()
		local checked = 0
		for _, code in ipairs(keysOf(names.enUS)) do
			local script = code ~= "auto" and lib.localeScript[code]
			if script and script ~= "Latin" and not HAN_ONLY[code] then
				local endonym = names[code][code]
				checked = checked + 1
				assert.equal(lib.scripts[script].font, lib:FontForText("NeverRegistered", endonym),
					code .. "'s endonym does not resolve to its own script's font")
			end
		end
		assert.is_true(checked > 0, "no code reached the assertion; this example proved nothing")
	end)

	-- The other side of the same claim, and the one that would catch a matcher quietly becoming
	-- greedy: a Han endonym must resolve to NOTHING per-text. If one of these ever started matching,
	-- a Chinese name in a Japanese list (or the reverse) would be painted from the wrong font and
	-- could box a variant-only glyph.
	it("leaves the Han endonyms unrouted, so the active locale decides their font", function()
		for code in pairs(HAN_ONLY) do
			assert.is_nil(lib:FontForText("NeverRegistered", names[code][code]),
				code .. "'s endonym resolved per-text; Han is not distinguishable by codepoint")
		end
	end)

	it("does not leave a non-Latin endonym sitting in English", function()
		local checked = 0
		for _, code in ipairs(keysOf(names.enUS)) do
			local script = code ~= "auto" and lib.localeScript[code]
			if script and script ~= "Latin" then
				checked = checked + 1
				assert.are_not.equal(names.enUS[code], names[code][code],
					code .. "'s endonym is still its English name")
			end
		end
		assert.is_true(checked > 0, "no code reached the assertion; this example proved nothing")
	end)

	-- These are the codes the picker can offer, so every one of them has to be a code the core
	-- library can actually resolve a font for -- or deliberately need none.
	it("keeps every offered code consistent with the font routing", function()
		local checked = 0
		for _, code in ipairs(keysOf(names.enUS)) do
			local script = lib.localeScript[code]
			if script then
				checked = checked + 1
				assert.is_table(lib.scripts[script], code .. " maps to unknown script " .. tostring(script))
			end
		end
		assert.is_true(checked > 0, "no code reached the assertion; this example proved nothing")
	end)
end)
