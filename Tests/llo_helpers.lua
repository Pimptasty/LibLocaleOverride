-- charset-ok: this is a LOCALE library's test-fixture file. Its subject IS non-Latin script, and
-- every one of the characters below appears only in a trailing comment naming what the adjacent
-- byte escape spells -- the values themselves are pure ASCII escapes. Nothing here is ever drawn
-- by the client: this file is dev-only (`Tests` is in .pkgmeta's ignore list) and never ships.
--
-- Shared spec helpers for LibLocaleOverride.
--
-- NOT a spec file (no `_spec` suffix), so neither runner collects it. Loaded with
-- `local h = dofile("Tests/llo_helpers.lua")` -- paths in a spec are relative to the ADDON ROOT,
-- which is where both runners start.
--
-- Why a shared file rather than a copy per spec: every spec here needs the same three-line
-- bootstrap (env, widget layer, load the real library through env.libs) and the same
-- "give me a clean registry" reset. Six copies of that is six places for the bootstrap to drift.

local wow    = require("env.wow")
local frames = require("env.frames")   -- OPT-IN widget layer: CreateFont, CreateFontString,
                                       -- GameFontNormalSmall and the Button font-object surface
                                       -- all live here, and the library touches every one of them.
local libs   = require("env.libs")

local H = { wow = wow, frames = frames, libs = libs }

-- The REAL library, loaded from the installed folder through the shared manifest -- never a copy.
-- `env.libs`'s root is `..` (the AddOns folder), so from this addon's root that resolves back to
-- this very working tree: the bytes under test are the bytes that ship.
libs.load("LibLocaleOverride-1.0")
H.lib = LibStub("LibLocaleOverride-1.0")

-- Every addon name a spec has touched, so `H.reset()` can clear the library's persistent
-- `lib.registry` between examples. The registry is state on the library object, and the whole
-- suite shares one Lua state -- without this, one example's override leaks into the next FILE.
local touched = {}

--- A fresh, unused addon name. Unique per call, so an example that forgets to reset still cannot
--- read another example's registry entry.
local n = 0
function H.addon(prefix)
	n = n + 1
	local name = (prefix or "LLOSpec") .. n
	touched[name] = true
	return name
end

--- Register a name a spec made up itself, so the reset still reaches it.
function H.track(name)
	touched[name] = true
	return name
end

--- Put the world back: the env, the widget layer, and the library's own registry.
function H.reset()
	wow.reset()
	frames.reset()
	for name in pairs(touched) do H.lib:UnregisterAddon(name) end
	touched = {}
end

--- A FontString on a real (offline) frame -- the only way to get one the library will accept,
--- since it checks for SetFontObject/GetFont before touching anything.
function H.fontString(text)
	local f  = CreateFrame("Frame", nil, UIParent)
	local fs = f:CreateFontString(nil, "ARTWORK")
	if text then fs:SetText(text) end
	return fs, f
end

--- A Button carrying the per-state font objects `ApplyFontToButton` drives, plus a fontstring --
--- i.e. what a templated client button looks like from the library's side.
---
--- THERE ARE THREE STATE FONT OBJECTS, NOT FOUR. `Set/GetPushedFontObject` does not exist:
--- searched for across the whole of `F:\Blizzard API Docs` -- every flavour tree, `GlobalAPI.lua`
--- and `Blizzard_APIDocumentationGenerated` -- and it appears ZERO times, while
--- `SetNormalFontObject` and `SetDisabledFontObject` appear throughout. The pushed state is a text
--- OFFSET (`SetPushedTextOffset`), not a font swap. `env/frames.lua` is right to leave the method
--- nil, and the library's `button.SetPushedFontObject and ...` guard is a branch the client never
--- takes. Do not "fix" this by adding the method to a stand-in: that would make a dead branch look
--- live and would be the exact permissive-stub failure the harness's own rules warn about.
function H.button(text, opts)
	opts = opts or {}
	local b = CreateFrame("Button", nil, UIParent)
	local fs = b:CreateFontString(nil, "ARTWORK")
	b:SetFontString(fs)
	if text then fs:SetText(text) end
	b:SetNormalFontObject(opts.normal or _G.GameFontNormal)
	b:SetHighlightFontObject(opts.highlight or _G.GameFontHighlight)
	b:SetDisabledFontObject(opts.disabled or _G.GameFontDisable)
	if opts.width then b:SetWidth(opts.width) end
	return b, fs
end

-- Real UTF-8 sample text, written as byte escapes so the file's own encoding can never change what
-- the specs assert. Lua 5.1 has no \u, and a spec that depends on an editor preserving raw bytes is
-- a spec that breaks on the first tool that rewrites the file.
H.text = {
	thai        = "\224\185\132\224\184\151\224\184\162",                                     -- Thai
	devanagari  = "\224\164\185\224\164\191\224\164\168\224\165\141\224\164\166\224\165\128", -- Hindi
	bengali     = "\224\166\172\224\166\190\224\166\130\224\166\178\224\166\190",             -- Bangla
	tamil       = "\224\174\164\224\174\174\224\174\191\224\174\180",                         -- Tamil
	telugu      = "\224\176\164\224\177\134\224\176\178\224\177\129",                         -- Telugu
	gurmukhi    = "\224\168\170\224\169\176\224\168\156\224\168\190\224\168\172\224\169\128", -- Punjabi
	hebrew      = "\215\162\215\145\215\168\215\153\215\170",                                 -- Hebrew
	arabic      = "\216\185\216\168\216\177\217\138",                                         -- Arabic base letters
	cyrillic    = "\208\160\209\131\209\129\209\129\208\186\208\184\208\185",                 -- Russian
	japanese    = "\227\129\178\227\130\137\227\129\140\227\129\170",                         -- Hiragana
	korean      = "\237\149\156\234\181\173\236\150\180",                                     -- Hangul
	han         = "\228\184\173\230\150\135",                                                 -- shared Han: never matches
	latinExt    = "Ti\225\186\191ng Vi\225\187\135t",                                         -- Vietnamese (Latin Extended)
	latin1      = "Fran\195\167ais",                                                          -- French (C3 -> client font)
	danda       = "\224\165\164",                                                             -- U+0964 danda
	doubleDanda = "\224\165\165",                                                             -- U+0965 double danda
}

return H
