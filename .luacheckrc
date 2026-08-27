-- Luacheck configuration for LibLocaleOverride (embeddable WoW library).
--
-- Tames the false positives luacheck produces on WoW addon code: the client injects a large
-- global API at runtime, so "accessing undefined variable 'LibStub'" and friends are not real
-- problems, and library methods frequently don't use their implicit `self`.
--
-- KEEP THIS IN STEP WITH `.luarc.json`. Two checkers, two separate global lists: a name added
-- to one and not the other is reported forever by the checker that never heard of it.

std = "lua51"
codes = true
self = false                 -- methods needn't use their implicit `self`
max_line_length = false

-- Client APIs the library reads. Every one of these is a real global the client installs;
-- the harness's `env/wow.lua` + `env/frames.lua` install the same names offline.
read_globals = {
	"LibStub",
	"GetLocale",             -- the client's UI locale; "auto" resolves through it
	"CreateFont",            -- bundled fonts are applied as cached Font OBJECTS
	"CreateFrame",           -- the hidden measuring frame behind measuredWidth
	"UIParent",
	"GameFontNormal",        -- fallbacks when a button/tab has no font object of its own
	"GameFontNormalSmall",
	"GameFontHighlightSmall",
	"C_Timer",               -- next-frame re-fit; feature-detected before use
	"hooksecurefunc",        -- taint-safe dropdown hook; feature-detected before use
	"ToggleDropDownMenu",
	"UIDROPDOWNMENU_OPEN_MENU",
}

-- The offline suite runs under the harness's bundled runner (`lua Tests/wowapi/run.lua`), not
-- the client. It deliberately installs and reassigns client globals through `_G`, and
-- luassert replaces the stdlib `assert` function with a matcher TABLE (assert.same /
-- assert.equal / ...), which luacheck reads as field access on a function.
files["Tests"] = {
	std = "lua51+busted",
	ignore = { "143/assert" },
}
