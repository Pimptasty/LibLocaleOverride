-- LibLocaleOverride-RTL-1.0: `lib:Shape` (Arabic contextual reshaping + BiDi visual ordering) and
-- the two RTL predicates.
--
-- WoW's font engine is strictly left-to-right and does no BiDi reordering and no Arabic shaping at
-- all, so both jobs are the library's. Every expectation below is written as EXPLICIT presentation
-- -form codepoints (U+FE70..U+FEFF), not by re-running the library's own tables through a helper --
-- a test that recomputes the implementation asserts nothing about it.
--
-- Byte escapes throughout: Lua 5.1 has no \u, and an expectation spelled in raw glyphs would depend
-- on every tool that touches this file preserving the encoding.
local H = dofile("Tests/llo_helpers.lua")
local lib, T = H.lib, H.text

-- Arabic base letters (2-byte UTF-8).
local ALEF, BEH, TEH, LAM = "\216\167", "\216\168", "\216\170", "\217\132"
-- The presentation forms they must resolve to (3-byte, U+FE8D..U+FEFC).
local ALEF_ISO = "\239\186\141"
local BEH_ISO, BEH_INI, BEH_FIN = "\239\186\143", "\239\186\145", "\239\186\144"
local TEH_MID = "\239\186\152"
local LAM_ALEF_ISO, LAM_ALEF_FIN = "\239\187\187", "\239\187\188"

-- Split UTF-8 into characters and reverse them. Written here rather than reused from the library
-- because the BiDi rule for a pure-RTL run IS "reverse the characters" -- so an independent
-- reversal is the specification, and reusing the library's would be circular.
local function revChars(s)
	local out, i = {}, 1
	while i <= #s do
		local b = s:byte(i)
		local len = (b < 0x80 and 1) or (b < 0xE0 and 2) or (b < 0xF0 and 3) or 4
		table.insert(out, 1, s:sub(i, i + len - 1))
		i = i + len
	end
	return table.concat(out)
end

describe("lib:Shape -- pass-through", function()
	before_each(function() H.reset() end)

	it("returns nil and the empty string unchanged", function()
		assert.is_nil(lib:Shape(nil))
		assert.equal("", lib:Shape(""))
	end)

	-- The consumer contract: wrap EVERY display string unconditionally. That only works if text
	-- with no RTL character is returned byte-identical.
	it("returns text with no RTL character byte-identical", function()
		assert.equal("Hello, world 123", lib:Shape("Hello, world 123"))
		assert.equal(T.thai, lib:Shape(T.thai))
		assert.equal(T.cyrillic, lib:Shape(T.cyrillic))
		assert.equal(T.han, lib:Shape(T.han))
	end)

	it("looks past a 4-byte character without mistaking it for RTL", function()
		local emoji = "\240\159\152\128"                     -- U+1F600
		assert.equal("hi " .. emoji, lib:Shape("hi " .. emoji))
	end)
end)

describe("lib:Shape -- BiDi ordering", function()
	before_each(function() H.reset() end)

	it("reverses a pure Hebrew run into visual order", function()
		assert.equal(revChars(T.hebrew), lib:Shape(T.hebrew))
	end)

	-- Hebrew has no positional forms, so nothing is reshaped -- only the order changes. Asserting
	-- the byte SET is unchanged is what pins that: a reshaping bug would substitute codepoints.
	it("changes only the order of a Hebrew run, never the characters", function()
		local shaped = lib:Shape(T.hebrew)
		assert.equal(#T.hebrew, #shaped)
		assert.equal(T.hebrew, revChars(shaped))
	end)

	-- Numbers and Latin runs are read left-to-right even inside an RTL line. Reversing them with
	-- the rest would render "60" as "06", which is a wrong number rather than an ugly one.
	it("puts an embedded LTR run back in reading order", function()
		assert.equal(revChars(T.hebrew) .. "abc ", lib:Shape("abc " .. T.hebrew))
		assert.equal(revChars(T.hebrew) .. "60 ", lib:Shape("60 " .. T.hebrew))
	end)

	-- A format placeholder is an LTR run for the same reason: `%d` reversed is `d%`, which no
	-- longer formats. (Shape is applied AFTER format() fills them, but a raw template must still
	-- survive being passed in.)
	it("does not mirror a format placeholder", function()
		assert.equal(revChars(T.hebrew) .. "%d ", lib:Shape("%d " .. T.hebrew))
	end)

	-- Reversing only the POSITION of a bracket leaves "(" looking like a close bracket. Both the
	-- glyph and the position have to move, which is why these are mirrored AND held in RTL context
	-- rather than swept into an adjacent LTR run.
	it("mirrors paired brackets so they still wrap their content", function()
		assert.equal("(" .. revChars(T.hebrew) .. ")", lib:Shape("(" .. T.hebrew .. ")"))
		assert.equal("[" .. revChars(T.hebrew) .. "]", lib:Shape("[" .. T.hebrew .. "]"))
		assert.equal("{" .. revChars(T.hebrew) .. "}", lib:Shape("{" .. T.hebrew .. "}"))
		assert.equal("<" .. revChars(T.hebrew) .. ">", lib:Shape("<" .. T.hebrew .. ">"))
	end)
end)

describe("lib:Shape -- Arabic contextual reshaping", function()
	before_each(function() H.reset() end)

	it("uses the ISOLATED form for a lone letter", function()
		assert.equal(BEH_ISO, lib:Shape(BEH))
	end)

	-- The whole point of reshaping: a letter's glyph depends on its neighbours. Initial, medial and
	-- final are three different codepoints, and WoW substitutes none of them for us.
	it("picks initial / medial / final across a three-letter word", function()
		-- Logical BEH-TEH-BEH; visual order is the reverse, so the FINAL form comes first.
		assert.equal(BEH_FIN .. TEH_MID .. BEH_INI, lib:Shape(BEH .. TEH .. BEH))
	end)

	-- ALEF is right-joining: it never connects to the letter AFTER it. So a following letter must
	-- NOT take a medial/final form -- a dual-joining classifier that got this wrong would connect
	-- the whole word into one unreadable ligature chain.
	it("treats a right-joining letter as not joining forward", function()
		assert.equal(BEH_ISO .. ALEF_ISO, lib:Shape(ALEF .. BEH))
	end)

	it("folds LAM + ALEF into its ligature", function()
		assert.equal(LAM_ALEF_ISO, lib:Shape(LAM .. ALEF))
	end)

	it("uses the JOINED ligature form when a dual-joining letter precedes the LAM", function()
		-- BEH joins forward, so the LAM-ALEF ligature takes its final (joined) glyph and the BEH
		-- takes its initial form.
		assert.equal(LAM_ALEF_FIN .. BEH_INI, lib:Shape(BEH .. LAM .. ALEF))
	end)

	it("leaves non-Arabic characters in an Arabic string untouched apart from order", function()
		-- A Hebrew character has no entry in the form tables and must pass through the reshaper.
		local mixed = lib:Shape(T.hebrew .. BEH)
		assert.equal(BEH_ISO .. revChars(T.hebrew), mixed)
	end)

	it("keeps digits in reading order beside reshaped Arabic", function()
		assert.equal(BEH_ISO .. "12 ", lib:Shape("12 " .. BEH))
	end)
end)

-- ----------------------------------------------------------------------------
-- Joining type, asserted against Unicode rather than against the library's own tables
--
-- The library decides "does this letter join to the next one" from the SHAPE of its
-- form row -- distinct initial and medial glyphs. That is a proxy: it answers an
-- ENCODING question ("did Unicode give this letter four distinct compatibility
-- glyphs") in place of a LINGUISTIC one, and the two can disagree. AUDIT finding 11
-- is the row where they do.
--
-- So the expected values below come from Unicode's `ArabicShaping.txt` -- field 3,
-- the joining type -- and NOT from AR_FORMS. A table transcribed from AR_FORMS could
-- only ever prove the library agrees with itself. Each entry is `[codepoint] = type`
-- exactly as that file spells it, so a reader can check a row against the source
-- without decoding a byte escape first.
--
-- Everything here is driven BLACK-BOX through lib:Shape. `dualJoining` and AR_FORMS
-- are file-locals and stay that way: widening a shipped library's public surface for
-- a test is a worse trade than probing the behaviour, and the behaviour is what a
-- consumer actually gets.
local JOIN_TYPE = {
	[0x0621] = "U",  -- HAMZA
	[0x0622] = "R",  -- ALEF WITH MADDA ABOVE
	[0x0623] = "R",  -- ALEF WITH HAMZA ABOVE
	[0x0624] = "R",  -- WAW WITH HAMZA ABOVE
	[0x0625] = "R",  -- ALEF WITH HAMZA BELOW
	[0x0626] = "D",  -- DOTLESS YEH WITH HAMZA ABOVE
	[0x0627] = "R",  -- ALEF
	[0x0628] = "D",  -- BEH
	[0x0629] = "R",  -- TEH MARBUTA
	[0x062A] = "D",  -- TEH
	[0x062B] = "D",  -- THEH
	[0x062C] = "D",  -- JEEM
	[0x062D] = "D",  -- HAH
	[0x062E] = "D",  -- KHAH
	[0x062F] = "R",  -- DAL
	[0x0630] = "R",  -- THAL
	[0x0631] = "R",  -- REH
	[0x0632] = "R",  -- ZAIN
	[0x0633] = "D",  -- SEEN
	[0x0634] = "D",  -- SHEEN
	[0x0635] = "D",  -- SAD
	[0x0636] = "D",  -- DAD
	[0x0637] = "D",  -- TAH
	[0x0638] = "D",  -- ZAH
	[0x0639] = "D",  -- AIN
	[0x063A] = "D",  -- GHAIN
	[0x0641] = "D",  -- FEH
	[0x0642] = "D",  -- QAF
	[0x0643] = "D",  -- KAF
	[0x0644] = "D",  -- LAM
	[0x0645] = "D",  -- MEEM
	[0x0646] = "D",  -- NOON
	[0x0647] = "D",  -- HEH
	[0x0648] = "R",  -- WAW
	[0x0649] = "D",  -- DOTLESS YEH (ALEF MAKSURA)
	[0x064A] = "D",  -- YEH
	[0x0671] = "R",  -- ALEF WITH WASLA ABOVE
	[0x0677] = "R",  -- HIGH HAMZA WAW WITH COMMA ABOVE
	[0x0679] = "D",  -- TTEH
	[0x067A] = "D",  -- TTEHEH
	[0x067B] = "D",  -- BEEH
	[0x067E] = "D",  -- PEH
	[0x067F] = "D",  -- TEHEH
	[0x0680] = "D",  -- BEHEH
	[0x0683] = "D",  -- NYEH
	[0x0684] = "D",  -- DYEH
	[0x0686] = "D",  -- TCHEH
	[0x0687] = "D",  -- TCHEHEH
	[0x0688] = "R",  -- DDAL
	[0x068C] = "R",  -- DAHAL
	[0x068D] = "R",  -- DDAHAL
	[0x068E] = "R",  -- DUL
	[0x0691] = "R",  -- RREH
	[0x0698] = "R",  -- JEH
	[0x06A4] = "D",  -- VEH
	[0x06A6] = "D",  -- PEHEH
	[0x06A9] = "D",  -- KEHEH
	[0x06AD] = "D",  -- NG
	[0x06AF] = "D",  -- GAF
	[0x06B1] = "D",  -- NGOEH
	[0x06B3] = "D",  -- GUEH
	[0x06BA] = "D",  -- NOON GHUNNA -- finding 11: D, but no initial or medial form exists
	[0x06BB] = "D",  -- RNOON
	[0x06BE] = "D",  -- HEH DOACHASHMEE (KNOTTED HEH)
	[0x06C0] = "R",  -- HEH WITH YEH ABOVE
	[0x06C1] = "D",  -- HEH GOAL
	[0x06C5] = "R",  -- KIRGHIZ OE
	[0x06C6] = "R",  -- OE
	[0x06C7] = "R",  -- U
	[0x06C8] = "R",  -- YU
	[0x06C9] = "R",  -- KIRGHIZ YU
	[0x06CB] = "R",  -- VE
	[0x06CC] = "D",  -- FARSI YEH
	[0x06D0] = "D",  -- E
	[0x06D2] = "R",  -- YEH BARREE
	[0x06D3] = "R",  -- YEH BARREE WITH HAMZA ABOVE
}

-- Every codepoint above is in the Arabic block, so all of them are 2-byte UTF-8.
local function u(cp)
	return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
end

-- U+06BA NOON GHUNNA and its only two encoded forms (U+FB9E, U+FB9F). Its `ini` and
-- `mid` slots hold those same two glyphs, because Unicode encodes nothing else to
-- put there -- which is precisely why the shape of the row cannot reveal its type.
local NOON_GHUNNA = u(0x06BA)
local NOON_GHUNNA_ISO = "\239\174\158"

describe("Arabic joining type -- the library's classification vs Unicode's", function()
	before_each(function() H.reset() end)

	-- Probe: shape "<letter>BEH". BEH is last, so it takes its FINAL form if the letter
	-- before it joins forward and its ISOLATED form if it does not -- one observable bit
	-- per letter, and the one the whole reshaper turns on.
	local function joinsForward(ch)
		-- Callable assert, not is_not_nil: it fails loudly AND narrows the type, and Shape
		-- is declared nilable because it returns its argument for a nil input.
		local shaped = assert(lib:Shape(ch .. BEH))         -- visual order: BEH's glyph first
		local head = shaped:sub(1, 3)
		assert.is_true(head == BEH_FIN or head == BEH_ISO,
			"probe produced neither BEH form for the letter before it")
		return head == BEH_FIN
	end

	it("classifies all 76 letters exactly as ArabicShaping.txt does", function()
		local checked = 0
		for cp, join in pairs(JOIN_TYPE) do
			assert.equal(join == "D", joinsForward(u(cp)),
				string.format("U+%04X is joining type %s", cp, join))
			checked = checked + 1
		end
		assert.equal(76, checked)
	end)

	-- The guard that makes the table above a specification rather than a snapshot: if a
	-- 77th row is ever added to AR_FORMS, this goes red until its joining type is looked
	-- up in ArabicShaping.txt and written down here. The letter set is DISCOVERED, not
	-- transcribed -- a character the library reshapes comes back as a 3-byte presentation
	-- form, one it does not comes back byte-identical.
	it("reshapes exactly the letters this table names, across the whole Arabic block", function()
		local checked = 0
		for cp = 0x0600, 0x06FF do
			local ch = u(cp)
			local reshaped = lib:Shape(ch) ~= ch
			assert.equal(JOIN_TYPE[cp] ~= nil, reshaped,
				string.format("U+%04X: reshaped=%s but JOIN_TYPE entry=%s",
					cp, tostring(reshaped), tostring(JOIN_TYPE[cp])))
			checked = checked + 1
		end
		assert.equal(256, checked)
	end)

	-- Finding 11's measured instance. NOON GHUNNA is dual-joining, but Unicode encodes
	-- only its isolated and final forms, so a classifier reading the row's shape calls it
	-- right-joining. The letter that suffers is the NEXT one, whose forms all exist.
	it("joins forward from NOON GHUNNA, whose own row cannot show that it does", function()
		assert.equal(BEH_FIN .. NOON_GHUNNA_ISO, lib:Shape(NOON_GHUNNA .. BEH))
	end)

	-- The second call site: the same predicate picks the LAM+ALEF ligature's glyph.
	it("picks the JOINED ligature after NOON GHUNNA", function()
		assert.equal(LAM_ALEF_FIN .. NOON_GHUNNA_ISO, lib:Shape(NOON_GHUNNA .. LAM .. ALEF))
	end)

	-- NOON GHUNNA itself still renders as well as it can: there is no medial glyph to
	-- reach for, so the isolated one is the only available answer and is the right one.
	it("still renders NOON GHUNNA itself from the two forms that exist", function()
		assert.equal(NOON_GHUNNA_ISO, lib:Shape(NOON_GHUNNA))
	end)
end)

describe("the RTL predicates", function()
	local addon
	before_each(function()
		H.reset()
		addon = H.addon()
		lib:RegisterLocale(addon, "enUS", { K = "en" }, true)
		lib:RegisterLocale(addon, "heIL", { K = "he" })
	end)

	it("names the four RTL override locales", function()
		assert.same({ arSA = true, faIR = true, heIL = true, urPK = true }, lib.rtlLocales)
	end)

	it("agrees with localeScript: every RTL locale renders in Hebrew or Arabic", function()
		for code in pairs(lib.rtlLocales) do
			local script = lib.localeScript[code]
			assert.is_true(script == "Hebrew" or script == "Arabic",
				code .. " is RTL but maps to script '" .. tostring(script) .. "'")
		end
	end)

	it("IsRTL follows the addon's ACTIVE locale", function()
		lib:SetOverride(addon, "enUS")
		assert.is_false(lib:IsRTL(addon))
		lib:SetOverride(addon, "heIL")
		assert.is_true(lib:IsRTL(addon))
	end)

	it("IsRTL is false for an addon nothing has registered", function()
		assert.is_false(lib:IsRTL("NeverRegistered"))
	end)

	-- The sanctioned accessor for a SINGLE label or picker row, so consumers never reach into
	-- lib.rtlLocales themselves.
	it("IsRTLCode answers for a code regardless of any addon's active locale", function()
		assert.is_true(lib:IsRTLCode("arSA"))
		assert.is_true(lib:IsRTLCode("urPK"))
		assert.is_false(lib:IsRTLCode("deDE"))
		assert.is_false(lib:IsRTLCode(nil))
	end)
end)
