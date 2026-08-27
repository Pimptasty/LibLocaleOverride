-- The two text utilities: `LocalizeDigits` (native numerals, markup-aware) and `SplitToBytes`
-- (byte-aware chat chunking).
--
-- Both are pure string arithmetic over a supplied string, so nothing here depends on the harness's
-- deliberately-unfaithful text metrics -- these are the parts of the library that are fully
-- assertable offline.
local H = dofile("Tests/llo_helpers.lua")
local lib = H.lib

-- Devanagari digits U+0966..U+096F, as raw UTF-8 bytes. Lua 5.1 has no \u escape, and byte escapes
-- mean nothing in this file depends on an editor preserving the encoding.
local DEV = {}
for d = 0, 9 do DEV[tostring(d)] = "\224\165" .. string.char(166 + d) end

local function digitLocale()
	local t = { PLAIN = "no digits here" }
	for k, v in pairs(DEV) do t[k] = v end
	return t
end

describe("lib:LocalizeDigits", function()
	local addon
	before_each(function()
		H.reset()
		addon = H.addon()
		lib:RegisterLocale(addon, "enUS", { ["0"] = "0" }, true)
		lib:RegisterLocale(addon, "hiIN", digitLocale())
		lib:SetOverride(addon, "hiIN")
	end)

	it("returns anything that is not a non-empty string untouched", function()
		assert.is_nil(lib:LocalizeDigits(addon, nil))
		assert.equal("", lib:LocalizeDigits(addon, ""))
		assert.equal(42, lib:LocalizeDigits(addon, 42))
	end)

	it("returns the text unchanged for an addon with no active table", function()
		assert.equal("123", lib:LocalizeDigits("NeverRegistered", "123"))
	end)

	-- Latin, Cyrillic and CJK locales all write 0-9, so their tables define L["0"] == "0" (or leave
	-- it out). Rewriting nothing must cost nothing and must not rebuild the string.
	it("returns the text unchanged when the active locale has no native digits", function()
		lib:SetOverride(addon, "enUS")
		assert.equal("Level 60", lib:LocalizeDigits(addon, "Level 60"))
	end)

	it("rewrites the Western digits and leaves everything else alone", function()
		assert.equal("Level " .. DEV["6"] .. DEV["0"], lib:LocalizeDigits(addon, "Level 60"))
	end)

	it("falls back to the Western digit for any single digit the locale omits", function()
		local partial = digitLocale()
		partial["7"] = nil
		lib:RegisterLocale(addon, "mrIN", partial)
		lib:SetOverride(addon, "mrIN")
		assert.equal(DEV["6"] .. "7", lib:LocalizeDigits(addon, "67"))
	end)

	-- The backend stays Western (%d, arithmetic); only the DISPLAY string is rewritten. Markup is
	-- the hazard: a colour code is eight HEX bytes, and rewriting a digit inside one turns the
	-- escape into visible garbage.
	describe("markup awareness", function()
		it("never touches the 8 hex bytes of a colour code", function()
			local s = "|cff00ff00Level 3|r"
			assert.equal("|cff00ff00Level " .. DEV["3"] .. "|r", lib:LocalizeDigits(addon, s))
		end)

		it("never touches the body of a texture escape", function()
			local s = "|TInterface\\Icons\\INV_Misc_1:16:16|t x2"
			assert.equal("|TInterface\\Icons\\INV_Misc_1:16:16|t x" .. DEV["2"],
				lib:LocalizeDigits(addon, s))
		end)

		it("never touches the body of an atlas escape", function()
			local s = "|Aatlas-name-99:12:12|a 5"
			assert.equal("|Aatlas-name-99:12:12|a " .. DEV["5"], lib:LocalizeDigits(addon, s))
		end)

		-- The DATA half of a hyperlink is item ids and numbers; rewriting one breaks the link.
		it("never touches a hyperlink's data, only what follows it", function()
			local s = "|Hitem:12345:0:0:0|h[Sword]|h x3"
			assert.equal("|Hitem:12345:0:0:0|h[Sword]|h x" .. DEV["3"], lib:LocalizeDigits(addon, s))
		end)

		-- Retail's SECOND colour form, `|cn<NAME>:`, is terminator-delimited rather than
		-- fixed-length (Blizzard_Colors/Mainline/ColorManager.lua). Its name is arbitrary length and
		-- may contain digits, so the old fixed 10-byte skip left the tail of a long name exposed and
		-- rewrote digits inside the token itself. Classic Era has zero occurrences of `|cn`, which is
		-- why this survived: the development flavour never shows it. Audit finding 6.
		it("skips a retail |cn<NAME>: token to its colon, however long the name", function()
			-- 7 characters before the colon: fits inside the old 10-byte window, so it survived by
			-- luck. Pinned so a regression to fixed-width is caught here first.
			assert.equal("|cnIQ4:" .. DEV["5"] .. "|r", lib:LocalizeDigits(addon, "|cnIQ4:5|r"))
		end)

		it("skips a LONG |cn name whose digits the fixed-width parser would have rewritten", function()
			-- 12 characters before the colon, so bytes past the 10-byte window carry digits. Under
			-- the old parser the trailing "9" of the name was rewritten and the token stopped
			-- resolving; the visible "7" after the colon must still be localized.
			local s = "|cnLONGNAME99:7|r"
			assert.equal("|cnLONGNAME99:" .. DEV["7"] .. "|r", lib:LocalizeDigits(addon, s))
		end)

		it("emits an unterminated |cn literally rather than swallowing the rest of the line", function()
			-- No colon anywhere: emit the "|c", step 2, and let "n" fall through as ordinary text.
			-- The digit after it is still localized, which is the point -- a malformed token must
			-- not disable digit rewriting for the remainder of the string.
			assert.equal("|cn " .. DEV["4"], lib:LocalizeDigits(addon, "|cn 4"))
		end)

		-- Audit finding 10: the colon search must be BOUNDED to a well-formed name. An unbounded
		-- find(":") reaches a colon in ordinary prose -- and unlike |t / |a / |h, a bare colon is
		-- common in UI text -- so a malformed token disabled digit rewriting for a SPAN rather than
		-- corrupting one. Cheap direction of failure, which is why it is LOW, but it defeats the
		-- reason the unterminated branch exists at all.
		it("does not let a malformed |cn reach a colon in ordinary prose", function()
			local s = "|cnBROKEN Level 60: 5 items"
			assert.equal("|cnBROKEN Level " .. DEV["6"] .. DEV["0"] .. ": " .. DEV["5"] .. " items",
				lib:LocalizeDigits(addon, s))
		end)

		it("still skips the fixed-length |cAARRGGBB form beside it", function()
			-- The `n` test must key on the byte AFTER `|c`, not merely find an `n` somewhere: a
			-- hex colour whose digits include no `n` has to keep taking the 10-byte path.
			assert.equal("|cff00ff00" .. DEV["8"], lib:LocalizeDigits(addon, "|cff00ff008"))
		end)

		it("emits an unterminated |T / |A / |H literally instead of eating the rest of the line", function()
			assert.equal("|T " .. DEV["7"], lib:LocalizeDigits(addon, "|T 7"))
			assert.equal("|A " .. DEV["7"], lib:LocalizeDigits(addon, "|A 7"))
			assert.equal("|H " .. DEV["7"], lib:LocalizeDigits(addon, "|H 7"))
		end)

		it("handles several escapes and digits in one string", function()
			local s = "|cffffffff5|r |TIcon:1:1|t 6"
			assert.equal("|cffffffff" .. DEV["5"] .. "|r |TIcon:1:1|t " .. DEV["6"],
				lib:LocalizeDigits(addon, s))
		end)
	end)
end)

describe("lib:SplitToBytes", function()
	before_each(function() H.reset() end)

	it("returns NO chunks for nothing to send -- never an empty chunk", function()
		assert.same({}, lib:SplitToBytes(nil))
		assert.same({}, lib:SplitToBytes(""))
	end)

	it("returns a single chunk when the whole text fits", function()
		assert.same({ "hello world" }, lib:SplitToBytes("hello world"))
	end)

	it("breaks at whitespace so words stay whole", function()
		assert.same({ "hello ", "world" }, lib:SplitToBytes("hello world", 8))
	end)

	it("breaks at a full stop and a comma too, keeping the punctuation with its word", function()
		assert.same({ "one,", "two.", "three" }, lib:SplitToBytes("one,two.three", 5))
	end)

	-- The whole point of a BYTE limit in a locale library: Cyrillic is 2 bytes per character and
	-- Thai / Indic / CJK are 3, so a character count would lie about the wire size and the client
	-- would silently truncate the message.
	it("counts BYTES, not characters", function()
		local cyr = H.text.cyrillic          -- 7 characters, 14 bytes
		assert.equal(14, #cyr)
		assert.same({}, lib:SplitToBytes(cyr, 7))          -- would fit as characters; does not as bytes
		assert.same({ cyr }, lib:SplitToBytes(cyr, 14))
	end)

	-- An empty array is the "won't send" signal: a single token longer than the limit cannot be
	-- broken without corrupting it, so the caller is told rather than handed a truncated chunk.
	it("returns an empty array for an unsplittable token longer than the limit", function()
		assert.same({}, lib:SplitToBytes("0123456789", 8))
	end)

	it("defaults to WoW's 255-byte SendChatMessage limit", function()
		local long = string.rep("a", 300)
		assert.same({}, lib:SplitToBytes(long))            -- one 300-byte token: unsplittable at 255
		assert.same({ string.rep("a", 255) }, lib:SplitToBytes(string.rep("a", 255)))
	end)

	it("treats a non-numeric or non-positive limit as the default", function()
		assert.same({ "hi" }, lib:SplitToBytes("hi", "not a number"))
		assert.same({ "hi" }, lib:SplitToBytes("hi", 0))
		assert.same({ "hi" }, lib:SplitToBytes("hi", -5))
	end)

	it("packs as many whole words into each chunk as fit", function()
		assert.same({ "aa bb ", "cc dd ", "ee" }, lib:SplitToBytes("aa bb cc dd ee", 6))
	end)
end)
