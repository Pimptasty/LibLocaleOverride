--[[----------------------------------------------------------------------------
LibLocaleOverride-RTL  --  optional right-to-left support

Loaded after the core LibLocaleOverride-1.0; adds lib:Shape(text), which turns
logical-order RTL text (Hebrew, Arabic) into the visual order WoW's strictly
left-to-right font engine needs -- WoW does no BiDi reordering and no Arabic
shaping itself. Text with no RTL characters is returned unchanged, so a consumer
can wrap EVERY display string in lib:Shape() unconditionally.

What it does:
  * BiDi (this file): reverse the string for RTL base direction, but put embedded
    LTR runs (numbers, Latin, %d/%s, punctuation) back in reading order so they
    aren't mirrored. Good-enough Unicode-Bidi for UI labels -- not the full
    embedding-level algorithm.
  * Arabic reshaping: map base letters to contextual presentation forms before
    reversing, using form tables generated from python-arabic-reshaper (MIT) with the
    reshaping approach seeded by Arabic_Reshaper_LUA (MIT); both credited below.
    Covers Arabic, Persian and Urdu. Hebrew needs no reshaping (no positional forms).

The core library never depends on this file.
------------------------------------------------------------------------------]]

local lib = LibStub and LibStub("LibLocaleOverride-1.0", true)
if not lib then return end

-- Satellite version stamp (no NewLibrary guard of its own); newest copy wins regardless of
-- load order. Bump on every change to THIS file.
local RTL_MINOR = 1
if (lib._rtlMinor or 0) >= RTL_MINOR then return end
lib._rtlMinor = RTL_MINOR

-- Override locales whose script is right-to-left (used by lib:IsRTL).
lib.rtlLocales = {
	heIL = true,  -- Hebrew
	arSA = true,  -- Arabic
	urPK = true,  -- Urdu (Arabic script)
	faIR = true,  -- Persian / Farsi (Arabic script)
}

-- UTF-8 helpers (byte length from the lead byte; decode to a codepoint). No deps.
local function leadLen(b)
	if b < 0x80 then return 1 elseif b < 0xE0 then return 2 elseif b < 0xF0 then return 3 else return 4 end
end
local function codepoint(ch)
	local b1 = ch:byte(1)
	if b1 < 0x80 then return b1 end
	if b1 < 0xE0 then return (b1 % 0x20) * 0x40 + (ch:byte(2) % 0x40) end
	if b1 < 0xF0 then return (b1 % 0x10) * 0x1000 + (ch:byte(2) % 0x40) * 0x40 + (ch:byte(3) % 0x40) end
	return (b1 % 0x08) * 0x40000 + (ch:byte(2) % 0x40) * 0x1000 + (ch:byte(3) % 0x40) * 0x40 + (ch:byte(4) % 0x40)
end

-- Right-to-left scripts: Hebrew (U+0590-05FF), Arabic (U+0600-06FF) and its
-- presentation forms (U+FB50-FDFF, U+FE70-FEFF).
local function isRTLcp(cp)
	return (cp >= 0x0590 and cp <= 0x05FF)
		or (cp >= 0x0600 and cp <= 0x06FF)
		or (cp >= 0xFB50 and cp <= 0xFDFF)
		or (cp >= 0xFE70 and cp <= 0xFEFF)
end

local function isRTLchar(ch)
	return #ch >= 2 and isRTLcp(codepoint(ch))
end

-- Split a UTF-8 string into an array of single characters.
local function toChars(s)
	local t, i, n = {}, 1, #s
	while i <= n do
		local len = leadLen(s:byte(i))
		t[#t + 1] = s:sub(i, i + len - 1)
		i = i + len
	end
	return t
end

-- True if the text contains any RTL character.
local function hasRTL(s)
	local i, n = 1, #s
	while i <= n do
		local len = leadLen(s:byte(i))
		if len >= 2 and isRTLcp(codepoint(s:sub(i, i + len - 1))) then return true end
		i = i + len
	end
	return false
end

-- Reverse chars[a..b] in place.
local function reverseRange(c, a, b)
	while a < b do c[a], c[b] = c[b], c[a]; a = a + 1; b = b - 1 end
end

-- BiDi bracket mirroring: a paired-punctuation glyph in an RTL run must be swapped
-- for its mirror, because reversing only the POSITION leaves "(" looking like a close
-- bracket and ")" like an open one. Without this, an Arabic name like
-- "البرتغالية (البرازيل)" renders with the parentheses visually backwards. We treat
-- these as RTL-context (mirrored, and NOT pulled into an LTR run) -- correct for the
-- dominant case where the parenthetical matches the base direction, which is every
-- localized language name here. (A Latin parenthetical inside RTL would mirror wrong,
-- but that doesn't occur in these labels.)
local MIRROR = {
	["("] = ")", [")"] = "(", ["["] = "]", ["]"] = "[",
	["{"] = "}", ["}"] = "{", ["<"] = ">", [">"] = "<",
}

-- Logical -> visual for RTL base direction: reverse the whole sequence, then put
-- each maximal run of non-RTL characters (Latin, digits, %d/%s, punctuation) back
-- in reading order so numbers and placeholders aren't mirrored. Paired brackets are
-- mirrored and held in RTL order so they wrap RTL content the right way round.
local function visualOrder(s)
	local c = toChars(s)
	local n = #c
	for i = 1, n do local m = MIRROR[c[i]]; if m then c[i] = m end end
	reverseRange(c, 1, n)
	local runStart
	for i = 1, n do
		-- Brackets count as RTL-context here so they aren't re-reversed back into an
		-- adjacent LTR run (which would undo the mirror and re-mirror the position).
		if isRTLchar(c[i]) or MIRROR[c[i]] then
			if runStart then reverseRange(c, runStart, i - 1); runStart = nil end
		elseif not runStart then
			runStart = i
		end
	end
	if runStart then reverseRange(c, runStart, n) end
	return table.concat(c)
end

-- ----------------------------------------------------------------------------
-- Arabic contextual reshaping
--
-- Per-letter form tables generated from the Unicode Arabic Presentation Forms via
-- python-arabic-reshaper (github.com/mpcabd/python-arabic-reshaper, MIT, (c) 2019
-- Abdullah Diab) -- covers Arabic, Persian and Urdu letters. The reshaping/ligature
-- approach was seeded by Arabic_Reshaper_LUA (github.com/DiNaSoR/Arabic_Reshaper_LUA,
-- MIT). Each base letter maps to its four contextual presentation forms (isolated /
-- initial / medial / final, U+FB50-FEFF); a missing initial falls back to isolated,
-- a missing medial to final. WoW does no Arabic shaping, so we substitute the correct
-- form ourselves before the BiDi reverse; the bundled Noto Sans Arabic carries the
-- presentation-form glyphs.
-- ----------------------------------------------------------------------------
local AR_FORMS = {
	["\216\161"] = { iso = "\239\186\128", ini = "\239\186\128", mid = "\239\186\128", fin = "\239\186\128" }, -- HAMZA
	["\216\162"] = { iso = "\239\186\129", ini = "\239\186\129", mid = "\239\186\130", fin = "\239\186\130" }, -- ALEF WITH MADDA ABOVE
	["\216\163"] = { iso = "\239\186\131", ini = "\239\186\131", mid = "\239\186\132", fin = "\239\186\132" }, -- ALEF WITH HAMZA ABOVE
	["\216\164"] = { iso = "\239\186\133", ini = "\239\186\133", mid = "\239\186\134", fin = "\239\186\134" }, -- WAW WITH HAMZA ABOVE
	["\216\165"] = { iso = "\239\186\135", ini = "\239\186\135", mid = "\239\186\136", fin = "\239\186\136" }, -- ALEF WITH HAMZA BELOW
	["\216\166"] = { iso = "\239\186\137", ini = "\239\186\139", mid = "\239\186\140", fin = "\239\186\138" }, -- YEH WITH HAMZA ABOVE
	["\216\167"] = { iso = "\239\186\141", ini = "\239\186\141", mid = "\239\186\142", fin = "\239\186\142" }, -- ALEF
	["\216\168"] = { iso = "\239\186\143", ini = "\239\186\145", mid = "\239\186\146", fin = "\239\186\144" }, -- BEH
	["\216\169"] = { iso = "\239\186\147", ini = "\239\186\147", mid = "\239\186\148", fin = "\239\186\148" }, -- TEH MARBUTA
	["\216\170"] = { iso = "\239\186\149", ini = "\239\186\151", mid = "\239\186\152", fin = "\239\186\150" }, -- TEH
	["\216\171"] = { iso = "\239\186\153", ini = "\239\186\155", mid = "\239\186\156", fin = "\239\186\154" }, -- THEH
	["\216\172"] = { iso = "\239\186\157", ini = "\239\186\159", mid = "\239\186\160", fin = "\239\186\158" }, -- JEEM
	["\216\173"] = { iso = "\239\186\161", ini = "\239\186\163", mid = "\239\186\164", fin = "\239\186\162" }, -- HAH
	["\216\174"] = { iso = "\239\186\165", ini = "\239\186\167", mid = "\239\186\168", fin = "\239\186\166" }, -- KHAH
	["\216\175"] = { iso = "\239\186\169", ini = "\239\186\169", mid = "\239\186\170", fin = "\239\186\170" }, -- DAL
	["\216\176"] = { iso = "\239\186\171", ini = "\239\186\171", mid = "\239\186\172", fin = "\239\186\172" }, -- THAL
	["\216\177"] = { iso = "\239\186\173", ini = "\239\186\173", mid = "\239\186\174", fin = "\239\186\174" }, -- REH
	["\216\178"] = { iso = "\239\186\175", ini = "\239\186\175", mid = "\239\186\176", fin = "\239\186\176" }, -- ZAIN
	["\216\179"] = { iso = "\239\186\177", ini = "\239\186\179", mid = "\239\186\180", fin = "\239\186\178" }, -- SEEN
	["\216\180"] = { iso = "\239\186\181", ini = "\239\186\183", mid = "\239\186\184", fin = "\239\186\182" }, -- SHEEN
	["\216\181"] = { iso = "\239\186\185", ini = "\239\186\187", mid = "\239\186\188", fin = "\239\186\186" }, -- SAD
	["\216\182"] = { iso = "\239\186\189", ini = "\239\186\191", mid = "\239\187\128", fin = "\239\186\190" }, -- DAD
	["\216\183"] = { iso = "\239\187\129", ini = "\239\187\131", mid = "\239\187\132", fin = "\239\187\130" }, -- TAH
	["\216\184"] = { iso = "\239\187\133", ini = "\239\187\135", mid = "\239\187\136", fin = "\239\187\134" }, -- ZAH
	["\216\185"] = { iso = "\239\187\137", ini = "\239\187\139", mid = "\239\187\140", fin = "\239\187\138" }, -- AIN
	["\216\186"] = { iso = "\239\187\141", ini = "\239\187\143", mid = "\239\187\144", fin = "\239\187\142" }, -- GHAIN
	["\217\129"] = { iso = "\239\187\145", ini = "\239\187\147", mid = "\239\187\148", fin = "\239\187\146" }, -- FEH
	["\217\130"] = { iso = "\239\187\149", ini = "\239\187\151", mid = "\239\187\152", fin = "\239\187\150" }, -- QAF
	["\217\131"] = { iso = "\239\187\153", ini = "\239\187\155", mid = "\239\187\156", fin = "\239\187\154" }, -- KAF
	["\217\132"] = { iso = "\239\187\157", ini = "\239\187\159", mid = "\239\187\160", fin = "\239\187\158" }, -- LAM
	["\217\133"] = { iso = "\239\187\161", ini = "\239\187\163", mid = "\239\187\164", fin = "\239\187\162" }, -- MEEM
	["\217\134"] = { iso = "\239\187\165", ini = "\239\187\167", mid = "\239\187\168", fin = "\239\187\166" }, -- NOON
	["\217\135"] = { iso = "\239\187\169", ini = "\239\187\171", mid = "\239\187\172", fin = "\239\187\170" }, -- HEH
	["\217\136"] = { iso = "\239\187\173", ini = "\239\187\173", mid = "\239\187\174", fin = "\239\187\174" }, -- WAW
	["\217\137"] = { iso = "\239\187\175", ini = "\239\175\168", mid = "\239\175\169", fin = "\239\187\176" }, -- ALEF MAKSURA
	["\217\138"] = { iso = "\239\187\177", ini = "\239\187\179", mid = "\239\187\180", fin = "\239\187\178" }, -- YEH
	["\217\177"] = { iso = "\239\173\144", ini = "\239\173\144", mid = "\239\173\145", fin = "\239\173\145" }, -- ALEF WASLA
	["\217\183"] = { iso = "\239\175\157", ini = "\239\175\157", mid = "\239\175\157", fin = "\239\175\157" }, -- U WITH HAMZA ABOVE
	["\217\185"] = { iso = "\239\173\166", ini = "\239\173\168", mid = "\239\173\169", fin = "\239\173\167" }, -- TTEH
	["\217\186"] = { iso = "\239\173\158", ini = "\239\173\160", mid = "\239\173\161", fin = "\239\173\159" }, -- TTEHEH
	["\217\187"] = { iso = "\239\173\146", ini = "\239\173\148", mid = "\239\173\149", fin = "\239\173\147" }, -- BEEH
	["\217\190"] = { iso = "\239\173\150", ini = "\239\173\152", mid = "\239\173\153", fin = "\239\173\151" }, -- PEH
	["\217\191"] = { iso = "\239\173\162", ini = "\239\173\164", mid = "\239\173\165", fin = "\239\173\163" }, -- TEHEH
	["\218\128"] = { iso = "\239\173\154", ini = "\239\173\156", mid = "\239\173\157", fin = "\239\173\155" }, -- BEHEH
	["\218\131"] = { iso = "\239\173\182", ini = "\239\173\184", mid = "\239\173\185", fin = "\239\173\183" }, -- NYEH
	["\218\132"] = { iso = "\239\173\178", ini = "\239\173\180", mid = "\239\173\181", fin = "\239\173\179" }, -- DYEH
	["\218\134"] = { iso = "\239\173\186", ini = "\239\173\188", mid = "\239\173\189", fin = "\239\173\187" }, -- TCHEH
	["\218\135"] = { iso = "\239\173\190", ini = "\239\174\128", mid = "\239\174\129", fin = "\239\173\191" }, -- TCHEHEH
	["\218\136"] = { iso = "\239\174\136", ini = "\239\174\136", mid = "\239\174\137", fin = "\239\174\137" }, -- DDAL
	["\218\140"] = { iso = "\239\174\132", ini = "\239\174\132", mid = "\239\174\133", fin = "\239\174\133" }, -- DAHAL
	["\218\141"] = { iso = "\239\174\130", ini = "\239\174\130", mid = "\239\174\131", fin = "\239\174\131" }, -- DDAHAL
	["\218\142"] = { iso = "\239\174\134", ini = "\239\174\134", mid = "\239\174\135", fin = "\239\174\135" }, -- DUL
	["\218\145"] = { iso = "\239\174\140", ini = "\239\174\140", mid = "\239\174\141", fin = "\239\174\141" }, -- RREH
	["\218\152"] = { iso = "\239\174\138", ini = "\239\174\138", mid = "\239\174\139", fin = "\239\174\139" }, -- JEH
	["\218\164"] = { iso = "\239\173\170", ini = "\239\173\172", mid = "\239\173\173", fin = "\239\173\171" }, -- VEH
	["\218\166"] = { iso = "\239\173\174", ini = "\239\173\176", mid = "\239\173\177", fin = "\239\173\175" }, -- PEHEH
	["\218\169"] = { iso = "\239\174\142", ini = "\239\174\144", mid = "\239\174\145", fin = "\239\174\143" }, -- KEHEH
	["\218\173"] = { iso = "\239\175\147", ini = "\239\175\149", mid = "\239\175\150", fin = "\239\175\148" }, -- NG
	["\218\175"] = { iso = "\239\174\146", ini = "\239\174\148", mid = "\239\174\149", fin = "\239\174\147" }, -- GAF
	["\218\177"] = { iso = "\239\174\154", ini = "\239\174\156", mid = "\239\174\157", fin = "\239\174\155" }, -- NGOEH
	["\218\179"] = { iso = "\239\174\150", ini = "\239\174\152", mid = "\239\174\153", fin = "\239\174\151" }, -- GUEH
	["\218\186"] = { iso = "\239\174\158", ini = "\239\174\158", mid = "\239\174\159", fin = "\239\174\159" }, -- NOON GHUNNA
	["\218\187"] = { iso = "\239\174\160", ini = "\239\174\162", mid = "\239\174\163", fin = "\239\174\161" }, -- RNOON
	["\218\190"] = { iso = "\239\174\170", ini = "\239\174\172", mid = "\239\174\173", fin = "\239\174\171" }, -- HEH DOACHASHMEE
	["\219\128"] = { iso = "\239\174\164", ini = "\239\174\164", mid = "\239\174\165", fin = "\239\174\165" }, -- HEH WITH YEH ABOVE
	["\219\129"] = { iso = "\239\174\166", ini = "\239\174\168", mid = "\239\174\169", fin = "\239\174\167" }, -- HEH GOAL
	["\219\133"] = { iso = "\239\175\160", ini = "\239\175\160", mid = "\239\175\161", fin = "\239\175\161" }, -- KIRGHIZ OE
	["\219\134"] = { iso = "\239\175\153", ini = "\239\175\153", mid = "\239\175\154", fin = "\239\175\154" }, -- OE
	["\219\135"] = { iso = "\239\175\151", ini = "\239\175\151", mid = "\239\175\152", fin = "\239\175\152" }, -- U
	["\219\136"] = { iso = "\239\175\155", ini = "\239\175\155", mid = "\239\175\156", fin = "\239\175\156" }, -- YU
	["\219\137"] = { iso = "\239\175\162", ini = "\239\175\162", mid = "\239\175\163", fin = "\239\175\163" }, -- KIRGHIZ YU
	["\219\139"] = { iso = "\239\175\158", ini = "\239\175\158", mid = "\239\175\159", fin = "\239\175\159" }, -- VE
	["\219\140"] = { iso = "\239\175\188", ini = "\239\175\190", mid = "\239\175\191", fin = "\239\175\189" }, -- FARSI YEH
	["\219\144"] = { iso = "\239\175\164", ini = "\239\175\166", mid = "\239\175\167", fin = "\239\175\165" }, -- E
	["\219\146"] = { iso = "\239\174\174", ini = "\239\174\174", mid = "\239\174\175", fin = "\239\174\175" }, -- YEH BARREE
	["\219\147"] = { iso = "\239\174\176", ini = "\239\174\176", mid = "\239\174\177", fin = "\239\174\177" }, -- YEH BARREE WITH HAMZA ABOVE
}

-- LAM + ALEF-variant fold into one ligature. a = isolated/initial glyph (LAM not
-- joined on its right), b = final/medial glyph (LAM joined to a preceding letter).
-- Like ALEF, the ligature never joins forward.
local LAM = "\217\132"
local LAM_ALEF = {
	["\216\167"] = { a = "\239\187\187", b = "\239\187\188" }, -- + ALEF
	["\216\162"] = { a = "\239\187\181", b = "\239\187\182" }, -- + ALEF MADDA
	["\216\163"] = { a = "\239\187\183", b = "\239\187\184" }, -- + ALEF HAMZA ABOVE
	["\216\165"] = { a = "\239\187\185", b = "\239\187\186" }, -- + ALEF HAMZA BELOW
}

-- A letter joins to the FOLLOWING letter (is dual-joining) iff it has distinct
-- initial and medial forms -- right-joining letters (ALEF, DAL, REH, WAW...),
-- HAMZA and TEH MARBUTA do not, so this classifies them correctly too.
local function dualJoining(rule)
	return rule ~= nil and rule.ini ~= rule.iso and rule.mid ~= rule.fin
end

-- Substitute each Arabic base letter with its contextual presentation form and
-- fold LAM+ALEF ligatures. Output is STILL logical order; visualOrder() reverses
-- it. Non-Arabic characters (e.g. Hebrew) pass through untouched.
local function reshapeArabic(s)
	local c = toChars(s)
	local n = #c
	-- Pass 1: fold ligatures and classify each unit.
	local units, i = {}, 1
	while i <= n do
		local nextCh = c[i + 1]
		local lig = c[i] == LAM and nextCh and LAM_ALEF[nextCh]
		if lig then
			local joinBack = dualJoining(AR_FORMS[c[i - 1]])
			units[#units + 1] = { ch = joinBack and lig.b or lig.a, isArabic = true, joinsFwd = false }
			i = i + 2
		else
			local rule = AR_FORMS[c[i]]
			units[#units + 1] = { ch = c[i], rule = rule, isArabic = rule ~= nil, joinsFwd = dualJoining(rule) }
			i = i + 1
		end
	end
	-- Pass 2: pick the contextual form for each plain letter unit.
	local out = {}
	for k = 1, #units do
		local u = units[k]
		if not u.rule then
			out[k] = u.ch
		else
			local prev, nxt = units[k - 1], units[k + 1]
			local joinPrev = prev ~= nil and prev.joinsFwd
			local joinNext = u.joinsFwd and nxt ~= nil and nxt.isArabic
			if joinPrev and joinNext then out[k] = u.rule.mid
			elseif joinPrev then out[k] = u.rule.fin
			elseif joinNext then out[k] = u.rule.ini
			else out[k] = u.rule.iso end
		end
	end
	return table.concat(out)
end

--- Convert logical-order text to the visual order WoW's LTR renderer needs. Arabic
--- is reshaped to contextual presentation forms first, then RTL text (Hebrew/Arabic)
--- is BiDi-reordered; text with no RTL characters is returned unchanged, so this is
--- safe to wrap around ANY string -- including format() results, which is where it
--- MUST be applied (after %d/%s are filled, never on the raw template).
function lib:Shape(text)
	if not text or text == "" or not hasRTL(text) then return text end
	return visualOrder(reshapeArabic(text))
end

--- True if the addon's ACTIVE override locale is right-to-left -- for choosing text
--- justification (RIGHT) and the like.
function lib:IsRTL(addon)
	local reg = self.registry[addon]
	return (reg and reg.code and lib.rtlLocales[reg.code]) and true or false
end

--- True if a SPECIFIC locale code is right-to-left (Hebrew/Arabic/Urdu/Persian), regardless
--- of any addon's active locale -- for shaping a single label or a language-picker row. A
--- sanctioned accessor so consumers don't reach into the lib.rtlLocales table directly.
function lib:IsRTLCode(code)
	return (code and lib.rtlLocales[code]) and true or false
end
