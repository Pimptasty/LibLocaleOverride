-- The core locale layer of LibLocaleOverride-1.0: registration, the in-place merge, override
-- resolution, the consumer-owned store, the client-locale table, and the change callbacks.
--
-- The property this whole library exists for -- and the one thing AceLocale cannot do -- is that
-- EVERY registered table is kept and the active table is rebuilt IN PLACE, so a consumer's
-- `local L = lib:GetLocale("MyAddon")` captured once at load stays correct after a live switch.
-- Several examples below assert table IDENTITY (`assert.equal(t1, t2)`) rather than contents for
-- exactly that reason: a rebuild that returned a NEW table would pass a contents assertion and
-- break every consumer that captured the old one.
local H = dofile("Tests/llo_helpers.lua")
local lib, wow = H.lib, H.wow

describe("LibLocaleOverride: registration", function()
	before_each(function() H.reset() end)

	it("registers under LibStub with the expected major", function()
		assert.equal(lib, LibStub("LibLocaleOverride-1.0"))
	end)

	it("rejects a non-string addon, a non-string code and a non-table locale", function()
		assert.has_error(function() lib:RegisterLocale(nil, "enUS", {}) end)
		assert.has_error(function() lib:RegisterLocale("A", nil, {}) end)
		assert.has_error(function() lib:RegisterLocale("A", "enUS", "not a table") end)
	end)

	it("returns the table it was given, so a consumer can register and capture in one line", function()
		local addon, t = H.addon(), { HELLO = "Hello" }
		assert.equal(t, lib:RegisterLocale(addon, "enUS", t, true))
	end)

	it("KEEPS every registered table -- the whole difference from AceLocale", function()
		local addon = H.addon()
		lib:RegisterLocale(addon, "enUS", { A = "a" }, true)
		lib:RegisterLocale(addon, "deDE", { A = "de" })
		lib:RegisterLocale(addon, "thTH", { A = "th" })
		assert.same({ "deDE", "enUS", "thTH" }, lib:GetAvailable(addon))
	end)

	it("reports what it has, and does not invent what it has not", function()
		local addon = H.addon()
		lib:RegisterLocale(addon, "enUS", { A = "a" }, true)
		assert.is_true(lib:HasLocale(addon, "enUS"))
		assert.is_false(lib:HasLocale(addon, "deDE"))
		assert.is_false(lib:HasLocale("NeverRegistered", "enUS"))
	end)

	it("returns an empty list for an addon that has registered nothing", function()
		assert.same({}, lib:GetAvailable("NeverRegistered"))
	end)
end)

describe("LibLocaleOverride: the merged table", function()
	local addon
	before_each(function()
		H.reset()
		addon = H.addon()
		lib:RegisterLocale(addon, "enUS", { GREET = "Hello", ONLY_EN = "en" }, true)
		lib:RegisterLocale(addon, "deDE", { GREET = "Hallo" })
	end)

	it("falls back to the baseline for a key the chosen locale does not translate", function()
		lib:SetOverride(addon, "deDE")
		local L = lib:GetLocale(addon)
		assert.equal("Hallo", L.GREET)
		assert.equal("en", L.ONLY_EN)     -- untranslated key survives from the baseline
	end)

	it("rebuilds IN PLACE, so a table captured before the switch is still correct after it", function()
		local L = lib:GetLocale(addon)
		assert.equal("Hello", L.GREET)
		lib:SetOverride(addon, "deDE")
		assert.equal(L, lib:GetLocale(addon))   -- same object
		assert.equal("Hallo", L.GREET)          -- ...and it has the new values
	end)

	it("drops a key the previous locale added but the new one does not have", function()
		lib:RegisterLocale(addon, "frFR", { GREET = "Bonjour", EXTRA = "extra" })
		lib:SetOverride(addon, "frFR")
		local L = lib:GetLocale(addon)
		assert.equal("extra", L.EXTRA)
		lib:SetOverride(addon, "deDE")
		assert.is_nil(L.EXTRA)   -- wiped, not left behind from the last build
	end)

	it("folds a LATE registration into an already-built table", function()
		local L = lib:GetLocale(addon)
		lib:SetOverride(addon, "thTH")            -- no thTH table yet: falls back to the baseline
		assert.equal("Hello", L.GREET)
		lib:RegisterLocale(addon, "thTH", { GREET = "Sawatdee" })
		assert.equal("Sawatdee", L.GREET)         -- the late table reached the SAME captured object
	end)
end)

describe("LibLocaleOverride: override resolution", function()
	local addon
	before_each(function()
		H.reset()
		addon = H.addon()
		lib:RegisterLocale(addon, "enUS", { K = "en" }, true)
		lib:RegisterLocale(addon, "deDE", { K = "de" })
	end)

	it("follows the CLIENT locale when the override is 'auto'", function()
		wow.locale = "deDE"
		lib:SetOverride(addon, "auto")
		assert.equal("deDE", lib:GetActiveCode(addon))
		assert.equal("de", lib:GetLocale(addon).K)
	end)

	it("treats a nil override as 'auto'", function()
		wow.locale = "deDE"
		lib:SetOverride(addon, nil)
		assert.equal("auto", lib:GetOverride(addon))
		assert.equal("deDE", lib:GetActiveCode(addon))
	end)

	it("falls back to the baseline when the client locale has no registered table", function()
		wow.locale = "koKR"
		lib:SetOverride(addon, "auto")
		assert.equal("enUS", lib:GetActiveCode(addon))
	end)

	it("falls back to the baseline when the OVERRIDE names a locale we do not have", function()
		lib:SetOverride(addon, "esMX")
		assert.equal("esMX", lib:GetOverride(addon))     -- the SETTING is kept as chosen...
		assert.equal("enUS", lib:GetActiveCode(addon))   -- ...and resolves to something real
	end)

	it("last resort: takes ANY registered table when neither override nor baseline resolves", function()
		local orphan = H.addon()
		lib:RegisterLocale(orphan, "thTH", { K = "th" })   -- no enUS baseline at all
		wow.locale = "frFR"
		assert.equal("thTH", lib:GetActiveCode(orphan))
		assert.equal("th", lib:GetLocale(orphan).K)
	end)

	it("resolves to nil, without erroring, for an addon with no tables at all", function()
		local empty = H.addon()
		assert.same({}, lib:GetLocale(empty))
		assert.is_nil(lib:GetActiveCode(empty))
	end)

	it("honours a baseline that is NOT enUS", function()
		local other = H.addon()
		lib:RegisterLocale(other, "frFR", { K = "fr", ONLY_FR = "x" }, true)
		lib:RegisterLocale(other, "deDE", { K = "de" })
		lib:SetOverride(other, "deDE")
		local L = lib:GetLocale(other)
		assert.equal("de", L.K)
		assert.equal("x", L.ONLY_FR)    -- the French baseline is what fills the gaps
	end)

	it("defaults the override SETTING to 'auto' for an addon nothing has touched", function()
		assert.equal("auto", lib:GetOverride("NeverRegistered"))
	end)

	it("lazily builds for GetActiveCode without creating a registry entry for a stranger", function()
		assert.is_nil(lib:GetActiveCode("NeverRegistered"))
		assert.is_nil(lib.registry["NeverRegistered"])   -- a getter must not register an addon
	end)
end)

describe("LibLocaleOverride: the consumer-owned store", function()
	local addon
	before_each(function()
		H.reset()
		addon = H.addon()
		lib:RegisterLocale(addon, "enUS", { K = "en" }, true)
		lib:RegisterLocale(addon, "deDE", { K = "de" })
	end)

	it("rejects a store accessor that is not a function", function()
		assert.has_error(function() lib:SetStore(addon, "nope", nil) end)
		assert.has_error(function() lib:SetStore(addon, nil, 42) end)
	end)

	it("accepts nil accessors -- unbinding a store is legal", function()
		lib:SetStore(addon, nil, nil)
		lib:ApplyStored(addon)
		assert.equal("auto", lib:GetOverride(addon))
	end)

	it("ApplyStored reads the stored code and builds with it", function()
		lib:SetStore(addon, function() return "deDE" end, nil)
		lib:ApplyStored(addon)
		assert.equal("deDE", lib:GetOverride(addon))
		assert.equal("de", lib:GetLocale(addon).K)
	end)

	it("ApplyStored treats an empty store as 'auto'", function()
		wow.locale = "deDE"
		lib:SetStore(addon, function() return nil end, nil)
		lib:ApplyStored(addon)
		assert.equal("auto", lib:GetOverride(addon))
		assert.equal("deDE", lib:GetActiveCode(addon))
	end)

	it("SetOverride writes through the setter -- including the 'auto' it substitutes for nil", function()
		local written = {}
		lib:SetStore(addon, nil, function(code) written[#written + 1] = code end)
		lib:SetOverride(addon, "deDE")
		lib:SetOverride(addon, nil)
		assert.same({ "deDE", "auto" }, written)
	end)
end)

describe("LibLocaleOverride: the CLIENT-locale table", function()
	local addon
	before_each(function()
		H.reset()
		addon = H.addon()
		lib:RegisterLocale(addon, "enUS", { K = "en", ONLY_EN = "e" }, true)
		lib:RegisterLocale(addon, "deDE", { K = "de" })
		lib:RegisterLocale(addon, "thTH", { K = "th" })
	end)

	-- Chat and print output must read from this table, never from `active`: an override can select a
	-- language WoW does not ship, whose glyphs the SHARED chat font cannot render, and the library
	-- cannot re-font Blizzard's chat frame for one addon without bleeding into every other addon.
	it("IGNORES the override and follows the client", function()
		wow.locale = "deDE"
		lib:SetOverride(addon, "thTH")
		assert.equal("th", lib:GetLocale(addon).K)          -- the UI is Thai
		assert.equal("de", lib:GetClientLocale(addon).K)    -- ...and chat is still German
	end)

	it("still fills gaps from the baseline", function()
		wow.locale = "deDE"
		assert.equal("e", lib:GetClientLocale(addon).ONLY_EN)
	end)

	it("falls back to the baseline when the client locale has no table", function()
		wow.locale = "koKR"
		assert.equal("en", lib:GetClientLocale(addon).K)
	end)

	it("hands back the SAME table each call, so a consumer may capture it", function()
		assert.equal(lib:GetClientLocale(addon), lib:GetClientLocale(addon))
	end)

	it("folds a late registration into the client table too", function()
		wow.locale = "frFR"
		local C = lib:GetClientLocale(addon)
		assert.equal("en", C.K)
		lib:RegisterLocale(addon, "frFR", { K = "fr" })
		assert.equal("fr", C.K)
	end)
end)

describe("LibLocaleOverride: change callbacks", function()
	local addon
	before_each(function()
		H.reset()
		addon = H.addon()
		lib:RegisterLocale(addon, "enUS", { K = "en" }, true)
		lib:RegisterLocale(addon, "deDE", { K = "de" })
	end)

	it("rejects a callback that is not a function", function()
		assert.has_error(function() lib:RegisterCallback(addon, "nope") end)
	end)

	it("fires with the addon name and the RESOLVED code", function()
		local seen = {}
		lib:RegisterCallback(addon, function(a, code) seen[#seen + 1] = { a, code } end)
		lib:SetOverride(addon, "deDE")
		assert.same({ { addon, "deDE" } }, seen)
	end)

	it("never double-registers the same function", function()
		local n = 0
		local fn = function() n = n + 1 end
		lib:RegisterCallback(addon, fn)
		lib:RegisterCallback(addon, fn)
		lib:SetOverride(addon, "deDE")
		assert.equal(1, n)
	end)

	it("unregisters", function()
		local n = 0
		local fn = function() n = n + 1 end
		lib:RegisterCallback(addon, fn)
		lib:UnregisterCallback(addon, fn)
		lib:SetOverride(addon, "deDE")
		assert.equal(0, n)
	end)

	it("tolerates unregistering from an addon that has no callbacks", function()
		lib:UnregisterCallback("NeverRegistered", function() end)
		lib:UnregisterCallback(addon, function() end)
	end)

	-- A consumer's broken callback must not take the switch down with it: the locale change has
	-- already happened by the time callbacks run, so aborting here would leave every OTHER widget
	-- unrefreshed against a table that has already moved.
	it("isolates a callback that errors, so the rest still run", function()
		local ran = {}
		lib:RegisterCallback(addon, function() error("boom") end)
		lib:RegisterCallback(addon, function() ran[#ran + 1] = true end)
		lib:SetOverride(addon, "deDE")
		assert.same({ true }, ran)
		assert.equal("de", lib:GetLocale(addon).K)
	end)
end)

describe("LibLocaleOverride: teardown", function()
	before_each(function() H.reset() end)

	it("UnregisterAddon forgets everything, and the addon may register again after", function()
		local addon = H.addon()
		lib:RegisterLocale(addon, "enUS", { K = "en" }, true)
		lib:SetOverride(addon, "enUS")
		lib:UnregisterAddon(addon)

		assert.is_nil(lib.registry[addon])
		assert.same({}, lib:GetAvailable(addon))
		assert.equal("auto", lib:GetOverride(addon))

		lib:RegisterLocale(addon, "enUS", { K = "again" }, true)
		assert.equal("again", lib:GetLocale(addon).K)
	end)

	it("UnregisterAddon on an addon that was never registered is a no-op", function()
		lib:UnregisterAddon("NeverRegistered")
	end)
end)
