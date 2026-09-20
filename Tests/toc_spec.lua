-- The `## Interface` list in LibLocaleOverride.toc, asserted as an INVARIANT rather than as numbers.
--
-- Why: this library is a hard `## Dependencies` of FastGuildInvite and Dibs. A dependency the client
-- flags out of date does not load, and a consumer whose hard dependency did not load is simply absent
-- from the AddOn list with nothing explaining why. The list was fixed by transcription on 2026-08-25
-- and was stale again on two values within a month (peer review, 2026-09-10). Transcribing a snapshot
-- is how the stale value got there, so this spec anchors the list to two things that move on their
-- own instead:
--
--   1. every `## Interface` value shipped by an installed consumer that names this library as a hard
--      dependency -- we cannot usefully claim fewer clients than the addons that refuse to load
--      without us;
--   2. every ACTIVE product in the WoW install's own `.build.info`, converted to an interface number
--      -- the client artefact, which outranks anything the ecosystem's TOCs happen to ship.
--
-- Both sources are read from the installed tree, exactly as env/libs.lua loads real libraries from
-- the sibling AddOns folder. Both must be FOUND for the spec to pass: an assertion over an empty set
-- is a passing test that measured nothing, which is the vacuous-assertion defect this board's finding
-- 8 was about.
local ADDONS  = ".."                              -- specs run from the addon root
local TOC     = "LibLocaleOverride.toc"
local BUILD   = "../../../../.build.info"         -- AddOns -> Interface -> <flavour> -> WoW root

local function readFile(path)
	local f = io.open(path, "r")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

--- The `## Interface:` values of one TOC, as a set of numeric strings.
local function interfaces(text)
	local set = {}
	local line = text and text:match("##%s*Interface:%s*([^\r\n]*)")
	for v in (line or ""):gmatch("%d+") do set[v] = true end
	return set
end

--- Does this TOC name LibLocaleOverride as a HARD dependency? `## Dependencies` and
--- `## RequiredDeps` are the load-or-refuse forms; `## OptionalDeps` is not, and is deliberately
--- excluded -- an optional dependency that fails to load costs the consumer nothing.
local function hardDependsOnUs(text)
	for line in text:gmatch("[^\r\n]+") do
		local deps = line:match("^##%s*Dependencies:%s*(.*)") or line:match("^##%s*RequiredDeps:%s*(.*)")
		if deps then
			for name in deps:gmatch("[^,%s]+") do
				if name == "LibLocaleOverride" then return true end
			end
		end
	end
	return false
end

--- Every `<AddOns>/<addon>/*.toc` -- one `dir` per call, listed through the shell because Lua 5.1
--- has no directory API. `cd` on Windows needs `/d` to change drive; here the path is relative so
--- the drive never changes, and `dir /b` on the wildcard is the cheapest listing there is.
local function consumerTocs()
	local out = {}
	local p = io.popen('dir /b /s "' .. ADDONS .. '\\*.toc" 2>nul')
	if not p then return out end
	for path in p:lines() do
		-- Skip our own TOC and anything under a Tests tree (the harness's fixtures carry TOCs).
		if not path:find("[\\/]LibLocaleOverride[\\/]") and not path:find("[\\/]Tests[\\/]") then
			local text = readFile(path)
			if text and hardDependsOnUs(text) then out[#out + 1] = { path = path, set = interfaces(text) } end
		end
	end
	p:close()
	return out
end

--- Active products in `.build.info` as interface numbers: `12.1.0.69875` -> 120100, `1.15.9.x` -> 11509.
--- The pipe-delimited header names the columns; `Active` is 1 for an installed, playable product.
local function activeClients()
	local text = readFile(BUILD)
	if not text then return nil end
	local rows = {}
	for line in text:gmatch("[^\r\n]+") do rows[#rows + 1] = line end
	local header = {}
	local i = 0
	for col in (rows[1] or ""):gmatch("[^|]+") do
		i = i + 1
		header[col:match("^([^!]+)")] = i
	end
	local out = {}
	for r = 2, #rows do
		local cells = {}
		for cell in (rows[r] .. "|"):gmatch("([^|]*)|") do cells[#cells + 1] = cell end
		if cells[header.Active] == "1" then
			local major, minor, patch = cells[header.Version]:match("^(%d+)%.(%d+)%.(%d+)")
			out[#out + 1] = {
				product   = cells[header.Product],
				version   = cells[header.Version],
				interface = tostring(tonumber(major) * 10000 + tonumber(minor) * 100 + tonumber(patch)),
			}
		end
	end
	return out
end

describe("LibLocaleOverride.toc ## Interface", function()
	local ours

	before_each(function()
		ours = interfaces(readFile(TOC))
	end)

	it("declares at least one interface", function()
		assert.is_true(next(ours) ~= nil)
	end)

	it("is a superset of every installed consumer that hard-depends on this library", function()
		local consumers = consumerTocs()
		-- FastGuildInvite and Dibs are installed on this box; an empty list means the listing
		-- failed, not that nobody depends on us.
		assert.is_true(#consumers > 0, "no consumer TOC naming LibLocaleOverride in ## Dependencies was found under " .. ADDONS)
		local missing = {}
		for _, c in ipairs(consumers) do
			for v in pairs(c.set) do
				if not ours[v] then missing[#missing + 1] = v .. " (" .. c.path .. ")" end
			end
		end
		table.sort(missing)
		assert.equal("", table.concat(missing, "\n"))
	end)

	it("carries the interface number of every ACTIVE product in the WoW install's .build.info", function()
		local clients = activeClients()
		assert.is_not_nil(clients, BUILD .. " not found -- the suite runs from the installed addon folder")
		assert.is_true(#clients > 0, "no active product in " .. BUILD)
		local missing = {}
		for _, c in ipairs(clients) do
			if not ours[c.interface] then
				missing[#missing + 1] = c.interface .. " (" .. c.product .. " " .. c.version .. ")"
			end
		end
		assert.equal("", table.concat(missing, "\n"))
	end)

	it("converts a product version to an interface number the way the client does", function()
		-- Pin the arithmetic itself, so a wrong conversion cannot make the assertion above vacuous.
		local text = "Branch!STRING:0|Active!DEC:1|Version!STRING:0|Product!STRING:0\n"
			.. "us|1|12.1.0.69875|wow\n"
			.. "us|0|1.60.1.69913|wow_classic_beta\n"
			.. "us|1|1.15.9.69722|wow_classic_era\n"
		local real = readFile
		readFile = function() return text end
		local ok, clients = pcall(activeClients)
		readFile = real
		assert.is_true(ok, tostring(clients))
		clients = clients or {}
		assert.equal(2, #clients)
		assert.equal("120100", (clients[1] or {}).interface)
		assert.equal("11509", (clients[2] or {}).interface)
	end)
end)
