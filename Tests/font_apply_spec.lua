-- Font APPLICATION: managed fontstrings, per-state button fonts, the recursive frame walk and the
-- shared-dropdown hook. Where `font_resolution_spec.lua` asks "which font?", this asks "did it
-- actually reach the widget, in every state, and did it come back off again?".
--
-- THE AUTO-FIT BLOCK'S THREE DEFECTS ARE NOW FIXED AND SPECCED, and this header used to say the
-- opposite. `docs/AUDIT.md` findings 3 (a zero floor cached permanently, because 0 is truthy),
-- 4 (floor and stock-font cache outliving a POOLED button) and 5 (the block running at all for a
-- textless or anchor-sized button) were open while this file was first written, so it deliberately
-- drove the block only for a labelled button with a real design width. That restriction is gone;
-- see `describe("auto-fit ...")` below, whose last four examples are the three findings.
--
-- Each of those four was driven RED against the pre-fix code before being kept. A spec that claims
-- to cover a specific defect and has never failed against it is decoration.
local H = dofile("Tests/llo_helpers.lua")
local lib, wow, frames, T = H.lib, H.wow, H.frames, H.text

describe("managed fontstrings", function()
	local addon
	before_each(function()
		H.reset()
		addon = H.addon()
		lib:RegisterLocale(addon, "enUS", { K = "en" }, true)
		lib:RegisterLocale(addon, "thTH", { K = "th" })
	end)

	it("applies the current locale immediately on registration", function()
		local fs = H.fontString(T.thai)
		lib:RegisterManagedFontString(addon, fs)
		assert.equal(lib.scripts.Thai.font, (fs:GetFont()))
	end)

	it("re-fonts every managed string on a locale switch", function()
		local a, b = H.fontString(T.thai), H.fontString(T.bengali)
		lib:RegisterManagedFontString(addon, a)
		lib:RegisterManagedFontString(addon, b)
		lib:SetOverride(addon, "thTH")
		assert.equal(lib.scripts.Thai.font, (a:GetFont()))
		assert.equal(lib.scripts.Bengali.font, (b:GetFont()))   -- fonted by its OWN text, not the locale
	end)

	it("restores the string's original font when its text no longer needs a bundled one", function()
		local fs = H.fontString(T.thai)
		fs:SetFont("Fonts\\ORIGINAL.TTF", 11, "")
		lib:RegisterManagedFontString(addon, fs)
		assert.equal(lib.scripts.Thai.font, (fs:GetFont()))

		fs:SetText("English")
		lib:SetOverride(addon, "enUS")
		assert.equal("Fonts\\ORIGINAL.TTF", (fs:GetFont()))
	end)

	-- The object path is the one that keeps WoW's glyph-fallback chain alive. A raw SetFont to a
	-- script-only TTF turns fallback OFF, and that "off" state lingers on a pooled frame even after
	-- a later SetFontObject -- so a string that once showed Thai would then box CJK.
	it("uses the OBJECT path when the string had a font object, and restores that object", function()
		local fs = H.fontString(T.thai)
		fs:SetFontObject(_G.GameFontNormalSmall)
		lib:RegisterManagedFontString(addon, fs)
		assert.equal(lib.scripts.Thai.font, (fs:GetFontObject():GetFont()))

		fs:SetText("English")
		lib:SetOverride(addon, "enUS")
		assert.equal(_G.GameFontNormalSmall, fs:GetFontObject())
	end)

	it("hands a CALLBACK the active locale's font and the resolved code", function()
		local seen = {}
		lib:RegisterManagedFontString(addon, function(font, code) seen[#seen + 1] = { font, code } end)
		lib:SetOverride(addon, "thTH")
		assert.same({ lib.scripts.Thai.font, "thTH" }, seen[#seen])
	end)

	it("hands a callback nil rather than a font when the locale needs none", function()
		local seen
		lib:RegisterManagedFontString(addon, function(font, code) seen = { font, code } end)
		lib:SetOverride(addon, "enUS")
		assert.same({ nil, "enUS" }, seen)
	end)

	-- AceGUI recycles widgets from a pool, so a consumer that re-registers the same FontString on
	-- every rebuild would otherwise grow `reg.managed` without bound -- and re-font stale recycled
	-- strings on every switch thereafter.
	it("dedups a FontString, and re-applies rather than queuing a second entry", function()
		local fs = H.fontString(T.thai)
		local first  = lib:RegisterManagedFontString(addon, fs)
		local second = lib:RegisterManagedFontString(addon, fs)
		assert.equal(first, second)
		assert.equal(1, #lib.registry[addon].managed)
	end)

	it("does NOT dedup callbacks -- two closures are two subscriptions", function()
		lib:RegisterManagedFontString(addon, function() end)
		lib:RegisterManagedFontString(addon, function() end)
		assert.equal(2, #lib.registry[addon].managed)
	end)

	it("unregisters a string, and forgets it from the dedup set too", function()
		local fs = H.fontString(T.thai)
		lib:RegisterManagedFontString(addon, fs)
		lib:UnregisterManagedFontString(addon, fs)
		assert.equal(0, #lib.registry[addon].managed)

		-- Re-registering after an unregister must produce a NEW entry, not resurrect the old one.
		local again = lib:RegisterManagedFontString(addon, fs)
		assert.equal(1, #lib.registry[addon].managed)
		assert.equal(again, lib.registry[addon].managed[1])
	end)

	it("unregisters a callback", function()
		local fn = function() end
		lib:RegisterManagedFontString(addon, fn)
		lib:UnregisterManagedFontString(addon, fn)
		assert.equal(0, #lib.registry[addon].managed)
	end)

	it("tolerates unregistering from an addon with nothing managed", function()
		lib:UnregisterManagedFontString("NeverRegistered", function() end)
		lib:UnregisterManagedFontString(addon, function() end)
	end)

	it("ignores a managed item that is neither a font-capable string nor a function", function()
		lib:RegisterManagedFontString(addon, { NotAFontString = true })
		lib:SetOverride(addon, "thTH")   -- must not raise
		-- The registry survives the bad item. Read through the CALLABLE `assert`, which fails loudly
		-- on nil AND narrows the type for the language server -- audit finding 8: this used to be
		-- `local reg = lib.registry[addon] or {}` followed by `assert.is_table(reg)`, and the `or {}`
		-- made that a table on every path including the nil one, so it passed for a reason
		-- unconnected to the library and could not fail.
		local reg     = assert(lib.registry[addon])
		local managed = assert(reg.managed)
		assert.equal(1, #managed)
	end)

	-- The switch has already happened by the time fonts are applied, so one broken widget must not
	-- abort the others, nor block the change callbacks that run after them.
	it("isolates a managed item that errors", function()
		local bad, good = H.fontString(T.thai), H.fontString(T.bengali)
		lib:RegisterManagedFontString(addon, bad)
		lib:RegisterManagedFontString(addon, good)
		bad.SetFontObject = function() error("boom") end
		bad.SetFont = function() error("boom") end

		local fired = false
		lib:RegisterCallback(addon, function() fired = true end)
		lib:SetOverride(addon, "thTH")

		assert.equal(lib.scripts.Bengali.font, (good:GetFont()))
		assert.is_true(fired)
	end)

	it("re-applies fonts when a per-addon font is registered after the first build", function()
		local fs = H.fontString(T.thai)
		lib:GetLocale(addon)   -- forces the build; RegisterFont only re-applies to a BUILT registry
		lib:RegisterManagedFontString(addon, fs)
		lib:RegisterFont(addon, "thTH", "Interface\\AddOns\\Mine\\th.ttf")
		assert.equal("Interface\\AddOns\\Mine\\th.ttf", (fs:GetFont()))
	end)

	it("RegisterFont before the first build does not force one", function()
		local fresh = H.addon()
		lib:RegisterFont(fresh, "thTH", "Interface\\AddOns\\Mine\\th.ttf")
		assert.is_nil(lib.registry[fresh].built)
	end)
end)

describe("lib:ApplyFontToButton", function()
	local addon
	before_each(function()
		H.reset()
		addon = H.addon()
		lib:RegisterLocale(addon, "enUS", { K = "en" }, true)
	end)

	it("ignores anything that is not a button", function()
		lib:ApplyFontToButton(addon, nil)
		lib:ApplyFontToButton(addon, "not a table")
		lib:ApplyFontToButton(addon, {})   -- no GetNormalFontObject
	end)

	-- A templated button swaps in a PER-STATE font object on hover / push / disable, so fonting only
	-- the label means a non-Latin caption reverts to the glyph-less default -- and renders as boxes
	-- -- the moment the pointer touches it.
	it("points every state font object the client HAS at the bundled font", function()
		local b, fs = H.button(T.thai, { width = 100 })
		lib:ApplyFontToButton(addon, b)
		local obj = b:GetNormalFontObject()
		assert.equal(lib.scripts.Thai.font, (obj:GetFont()))
		assert.equal(obj, b:GetHighlightFontObject())
		assert.equal(obj, b:GetDisabledFontObject())
		assert.equal(obj, fs:GetFontObject())   -- and the label, for the width measured this frame
		-- Three, not four: see `H.button` -- `Set/GetPushedFontObject` exists in no flavour tree,
		-- so the library's guarded call to it is a branch the client never takes.
		assert.is_nil(b.SetPushedFontObject)
	end)

	it("caches the stock per-state objects once, and restores them for a Latin label", function()
		local b, fs = H.button(T.thai, { width = 100 })
		lib:ApplyFontToButton(addon, b)
		assert.are_not.equal(_G.GameFontNormal, b:GetNormalFontObject())

		fs:SetText("English")
		lib:ApplyFontToButton(addon, b)
		assert.equal(_G.GameFontNormal, b:GetNormalFontObject())
		assert.equal(_G.GameFontHighlight, b:GetHighlightFontObject())
		assert.equal(_G.GameFontDisable, b:GetDisabledFontObject())
	end)

	-- The restore reads the cache positionally, and the missing Pushed slot is a `false` sitting in
	-- the middle of it. A restore that treated index 3 as "the disabled object" would put the
	-- WRONG object back -- so the order is part of the contract, not an implementation detail.
	it("caches the states positionally, with a `false` where the client has no getter", function()
		local b = H.button(T.thai, { width = 100 })
		lib:ApplyFontToButton(addon, b)
		assert.same({ _G.GameFontNormal, _G.GameFontHighlight, false, _G.GameFontDisable },
			b.__lloOrigFonts)
	end)

	it("caches the ORIGINALS, not whatever it left behind on the second call", function()
		local b, fs = H.button(T.thai, { width = 100 })
		lib:ApplyFontToButton(addon, b)         -- bundled objects are on the button now
		lib:ApplyFontToButton(addon, b)         -- must not re-cache from the bundled state
		fs:SetText("English")
		lib:ApplyFontToButton(addon, b)
		assert.equal(_G.GameFontNormal, b:GetNormalFontObject())
	end)

	it("records `false` for a state getter the button does not have", function()
		local b = CreateFrame("Button", nil, UIParent)
		b.GetHighlightFontObject, b.SetHighlightFontObject = nil, nil
		b.GetDisabledFontObject,  b.SetDisabledFontObject  = nil, nil
		b:SetNormalFontObject(_G.GameFontNormal)
		-- A REAL DESIGN WIDTH, like every sibling example. Without it this frame reports
		-- GetWidth() == 0, so the auto-fit caches __lloFitFloor = 0 and runs finding 3's exact path
		-- -- which this file's header states it avoids. Nothing here asserts a width, so it did no
		-- harm, but the header is what a later reader trusts when asking "is finding 3 specced?".
		-- Audit round 7, item 2.
		b:SetWidth(100)
		b:SetText(T.thai)
		lib:ApplyFontToButton(addon, b)
		assert.same({ false, false, false }, {
			b.__lloOrigFonts[2], b.__lloOrigFonts[3], b.__lloOrigFonts[4],
		})
		assert.equal(lib.scripts.Thai.font, (b:GetNormalFontObject():GetFont()))
	end)

	-- The common consumer pattern: a bare CreateFrame button with a separate child `.label`
	-- fontstring, which is NOT the button's own GetFontString (that one is nil here).
	it("uses a `.label` child when the button has no fontstring of its own", function()
		local b = CreateFrame("Button", nil, UIParent)
		b:SetNormalFontObject(_G.GameFontNormal)
		b:SetWidth(100)
		b.label = b:CreateFontString(nil, "ARTWORK")
		b.label:SetText(T.bengali)
		lib:ApplyFontToButton(addon, b)
		assert.equal(lib.scripts.Bengali.font, (b.label:GetFontObject():GetFont()))
	end)

	it("falls back to the button's own GetText when there is neither", function()
		local b = CreateFrame("Button", nil, UIParent)
		b:SetNormalFontObject(_G.GameFontNormal)
		b:SetWidth(100)
		b:SetText(T.tamil)
		lib:ApplyFontToButton(addon, b)
		assert.equal(lib.scripts.Tamil.font, (b:GetNormalFontObject():GetFont()))
	end)

	-- A bare CreateFrame button has NO Normal font object, so the size/flags the bundled font is
	-- built at have to come from somewhere. The chain is: cached stock Normal -> live Normal -> the
	-- label's own font object -> GameFontNormal. Both tail steps matter: without them a bare button
	-- would build its bundled font at the hardcoded 12pt and ignore the label entirely.
	it("falls back to the LABEL's font object when the button has no Normal object", function()
		local labelFont = CreateFont("SpecLabelFont")
		labelFont:SetFont("Fonts\\FRIZQT__.TTF", 19, "OUTLINE")
		local b = CreateFrame("Button", nil, UIParent)
		b:SetWidth(100)
		b.label = b:CreateFontString(nil, "ARTWORK")
		b.label:SetText(T.thai)
		b.label:SetFontObject(labelFont)
		lib:ApplyFontToButton(addon, b)
		local _, size, flags = b:GetNormalFontObject():GetFont()
		assert.equal(19, size)
		assert.equal("OUTLINE", flags)
	end)

	it("falls back to GameFontNormal when there is no font object anywhere", function()
		_G.GameFontNormal:SetFont("Fonts\\FRIZQT__.TTF", 21, "THICKOUTLINE")
		local b = CreateFrame("Button", nil, UIParent)
		b:SetWidth(100)
		b.label = b:CreateFontString(nil, "ARTWORK")
		b.label:SetText(T.thai)
		lib:ApplyFontToButton(addon, b)
		local _, size, flags = b:GetNormalFontObject():GetFont()
		assert.equal(21, size)
		assert.equal("THICKOUTLINE", flags)
	end)

	it("sizes the bundled font from the button's Normal font object", function()
		local base = CreateFont("SpecBaseFont")
		base:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
		local b = select(1, H.button(T.thai, { width = 100, normal = base }))
		lib:ApplyFontToButton(addon, b)
		local _, size, flags = b:GetNormalFontObject():GetFont()
		assert.equal(16, size)
		assert.equal("OUTLINE", flags)
	end)

	describe("auto-fit (a labelled button with a real design width)", function()
		it("leaves a button alone when its label already fits", function()
			local b = H.button(T.thai, { width = 100 })
			frames.setStringWidth(T.thai, 40)
			lib:ApplyFontToButton(addon, b)
			assert.equal(100, b:GetWidth())
		end)

		it("grows the button when the label exceeds the design width, plus padding", function()
			local b = H.button(T.thai, { width = 100 })
			frames.setStringWidth(T.thai, 200)
			lib:ApplyFontToButton(addon, b)
			assert.equal(226, b:GetWidth())          -- 200 + the default 26px padding
		end)

		it("honours lloFitPad", function()
			local b = H.button(T.thai, { width = 100 })
			b.lloFitPad = 4
			frames.setStringWidth(T.thai, 200)
			lib:ApplyFontToButton(addon, b)
			assert.equal(204, b:GetWidth())
		end)

		it("is idempotent -- a second call does not compound the padding", function()
			local b = H.button(T.thai, { width = 100 })
			frames.setStringWidth(T.thai, 200)
			lib:ApplyFontToButton(addon, b)
			lib:ApplyFontToButton(addon, b)
			assert.equal(226, b:GetWidth())
		end)

		-- The strip's layout has not settled when the first fit runs, so the same (better) estimate
		-- is re-asserted on the next frame rather than re-measuring the under-reporting string.
		it("re-asserts on the next frame", function()
			local b = H.button(T.thai, { width = 100 })
			frames.setStringWidth(T.thai, 200)
			lib:ApplyFontToButton(addon, b)
			b:SetWidth(999)                          -- something else moved it mid-layout
			assert.equal(1, wow.advanceTime(0.1))    -- exactly one queued callback fires
			assert.equal(226, b:GetWidth())
		end)

		it("reverses cleanly back to the design width on a switch to a Latin label", function()
			local b, fs = H.button(T.thai, { width = 100 })
			frames.setStringWidth(T.thai, 200)
			lib:ApplyFontToButton(addon, b)
			assert.equal(226, b:GetWidth())

			fs:SetText("Short")
			frames.setStringWidth("Short", 30)
			lib:ApplyFontToButton(addon, b)
			assert.equal(100, b:GetWidth())
		end)

		-- FINDING 3. GetWidth() is 0 for a button whose layout has not settled, and 0 is TRUTHY in
		-- Lua -- so the old `floor or GetWidth() or 0` cached that zero for the session, after which
		-- every label took the `w + pad` branch and the button had NO minimum at all. The floor must
		-- refuse to be captured until it is real, and the next-frame pass must then capture it.
		it("refuses to cache a zero floor, and captures a real one once layout settles", function()
			local b = CreateFrame("Button", nil, UIParent)
			local fs = b:CreateFontString(nil, "ARTWORK")
			b:SetFontString(fs)
			b:SetNormalFontObject(_G.GameFontNormal)
			fs:SetText(T.thai)
			frames.setStringWidth(T.thai, 200)
			assert.equal(0, b:GetWidth())          -- unsized and unanchored: the unsettled case

			lib:ApplyFontToButton(addon, b)
			assert.is_nil(b.__lloFitFloor)         -- NOT 0 -- nothing was cached
			assert.equal(0, b:GetWidth())          -- and nothing was written

			b:SetWidth(100)                        -- layout settles
			wow.advanceTime(0.1)                   -- the queued next-frame pass runs
			assert.equal(100, b.__lloFitFloor)     -- a REAL floor, captured late
			assert.equal(226, b:GetWidth())        -- and the fit finally applied
		end)

		-- FINDING 4. AceGUI pools these frames globally, so a cached floor outlives the button it
		-- was measured for: FastGuildInvite's 360px colour swatch came back as `Cancel` and was
		-- forced to the swatch's width. A floor is only ours while the button is still the width we
		-- last set it to.
		it("drops a floor left over from the button this pooled frame USED to be", function()
			local b, fs = H.button(T.thai, { width = 100 })
			frames.setStringWidth(T.thai, 200)
			lib:ApplyFontToButton(addon, b)
			assert.equal(226, b:GetWidth())
			assert.equal(100, b.__lloFitFloor)

			-- Released to the pool and re-acquired by a narrower button, which sets its own width.
			b:SetWidth(80)
			fs:SetText("Cancel")
			frames.setStringWidth("Cancel", 40)
			lib:ApplyFontToButton(addon, b)

			assert.equal(80, b.__lloFitFloor)      -- re-captured from the NEW occupant
			assert.equal(80, b:GetWidth())         -- and not dragged back to 100 or 226
		end)

		it("drops a stock-font cache left over from the button this pooled frame USED to be", function()
			local b, fs = H.button(T.thai, { width = 100 })
			lib:ApplyFontToButton(addon, b)        -- caches GameFontNormal, installs the bundled font

			-- The pool hands the frame to someone else, who fonts it their own way.
			local newStock = CreateFont("SpecRecycledStock")
			newStock:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
			b:SetNormalFontObject(newStock)
			fs:SetText("English")
			lib:ApplyFontToButton(addon, b)

			-- The restore must put back what THIS incarnation had, not the previous one's.
			assert.equal(newStock, b:GetNormalFontObject())
			assert.equal(newStock, b.__lloOrigFonts[1])
		end)

		-- FINDING 5a. "Fit the button to its label" is undefined with no label. The block used to
		-- run anyway and force such a button back to a width captured at an unrelated moment.
		it("never touches a button with no label at all", function()
			local b = CreateFrame("Button", nil, UIParent)
			b:SetNormalFontObject(_G.GameFontNormal)
			b:SetWidth(100)
			lib:ApplyFontToButton(addon, b)
			assert.is_nil(b.__lloFitFloor)

			b:SetWidth(239)                        -- something else resizes it
			lib:ApplyFontToButton(addon, b)
			assert.equal(239, b:GetWidth())        -- and it is left exactly where it was put
		end)

		-- FINDING 5b. AceGUI's Frame builds its status background as a BUTTON anchored BOTTOMLEFT
		-- and BOTTOMRIGHT -- textless AND double-anchored, both missing guards on one object. A
		-- region pinned on two opposing edges derives its width from them, so SetWidth corrupts the
		-- answer GetWidth gives every other reader even where the anchors win at paint time.
		it("never sets a width on a button sized by two opposing anchors", function()
			local parent = CreateFrame("Frame", nil, UIParent)
			parent:SetWidth(400)
			parent:SetHeight(100)
			parent:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
			local b = H.button(T.thai)
			b:SetParent(parent)
			b:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
			b:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
			frames.setStringWidth(T.thai, 200)

			lib:ApplyFontToButton(addon, b)
			assert.is_nil(b.__lloFitFloor)
			assert.is_nil(b.__lloFitSet)
			-- The font still reached it: only the WIDTH is off limits.
			assert.equal(lib.scripts.Thai.font, (b:GetNormalFontObject():GetFont()))
		end)

		-- CENTER constrains the midpoint, not an edge, so a CENTER-anchored button still owns its
		-- width and must still be fitted. Without this the guard would be far too broad.
		it("still fits a CENTER-anchored button, which owns its own width", function()
			local b = H.button(T.thai, { width = 100 })
			b:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
			frames.setStringWidth(T.thai, 200)
			lib:ApplyFontToButton(addon, b)
			assert.equal(226, b:GetWidth())
		end)

		-- The anchor test needs GetNumPoints/GetPoint to answer at all. A real frame has both; a
		-- consumer's hand-rolled widget table may not, and there the honest answer is "cannot tell"
		-- -- so it behaves as it did before the guard existed rather than refusing to fit anything
		-- it cannot inspect. A guard that fails CLOSED here would silently stop fitting every
		-- non-frame button in the fleet.
		it("fits a width-capable table that cannot report its anchors", function()
			local width = 100
			local b = {
				GetNormalFontObject = function() return _G.GameFontNormal end,
				SetNormalFontObject = function() end,
				GetText             = function() return T.thai end,
				GetWidth            = function() return width end,
				SetWidth            = function(_, w) width = w end,
			}
			frames.setStringWidth(T.thai, 200)
			lib:ApplyFontToButton(addon, b)
			assert.equal(226, width)
			assert.equal(100, b.__lloFitFloor)
		end)

		-- The fit block is guarded on SetWidth/GetWidth. A real client frame always has both, so the
		-- guard is only reachable for a hand-made widget-like table -- which is exactly what a
		-- consumer passing something that is not a frame looks like. Driven with one rather than by
		-- deleting the methods from a frame: `b.SetWidth = nil` writes an instance key and the class
		-- metatable still answers, so that spelling proves nothing.
		it("skips the fit entirely for a button-like table with no width methods", function()
			local applied = {}
			local b = {
				GetNormalFontObject = function() return _G.GameFontNormal end,
				SetNormalFontObject = function(_, o) applied.normal = o end,
				GetText             = function() return T.thai end,
			}
			lib:ApplyFontToButton(addon, b)
			assert.equal(lib.scripts.Thai.font, (applied.normal:GetFont()))
			assert.is_nil(b.__lloFitFloor)
		end)
	end)
end)

describe("lib:ApplyFontToFrame -- the recursive walk", function()
	local addon
	before_each(function()
		H.reset()
		addon = H.addon()
		lib:RegisterLocale(addon, "enUS", { K = "en" }, true)
	end)

	it("does nothing for a nil frame", function()
		lib:ApplyFontToFrame(addon, nil)
	end)

	it("fonts a FontString region of the frame itself", function()
		local frame = CreateFrame("Frame", nil, UIParent)
		local fs = frame:CreateFontString(nil, "ARTWORK")
		fs:SetText(T.thai)
		lib:ApplyFontToFrame(addon, frame)
		assert.equal(lib.scripts.Thai.font, (fs:GetFontObject():GetFont()))
	end)

	it("skips regions that are not FontStrings", function()
		local frame = CreateFrame("Frame", nil, UIParent)
		frame:CreateTexture(nil, "ARTWORK")
		lib:ApplyFontToFrame(addon, frame)   -- must not raise on a Texture
	end)

	it("descends into children and fonts each string by its OWN script", function()
		local root  = CreateFrame("Frame", nil, UIParent)
		local child = CreateFrame("Frame", nil, root)
		local a = root:CreateFontString(nil, "ARTWORK");  a:SetText(T.hebrew)
		local b = child:CreateFontString(nil, "ARTWORK"); b:SetText(T.telugu)
		lib:ApplyFontToFrame(addon, root)
		assert.equal(lib.scripts.Hebrew.font, (a:GetFontObject():GetFont()))
		assert.equal(lib.scripts.Telugu.font, (b:GetFontObject():GetFont()))
	end)

	it("fonts a child BUTTON through the per-state path, not just its label", function()
		local root = CreateFrame("Frame", nil, UIParent)
		local b = CreateFrame("Button", nil, root)
		local fs = b:CreateFontString(nil, "ARTWORK")
		b:SetFontString(fs)
		b:SetNormalFontObject(_G.GameFontNormal)
		b:SetWidth(100)
		fs:SetText(T.korean)
		lib:ApplyFontToFrame(addon, root)
		assert.equal(lib.scripts.Korean.font, (b:GetHighlightFontObject():GetFont()))
	end)

	-- A consumer frame tree that is pathologically deep (or cyclic through a custom GetChildren)
	-- must not hang the client. 30 is the documented cutoff.
	it("stops descending past 30 levels", function()
		local frames_, strings = { [0] = CreateFrame("Frame", nil, UIParent) }, {}
		for i = 1, 32 do
			frames_[i] = CreateFrame("Frame", nil, frames_[i - 1])
			strings[i] = frames_[i]:CreateFontString(nil, "ARTWORK")
			strings[i]:SetText(T.thai)
		end
		lib:ApplyFontToFrame(addon, frames_[0])
		assert.equal(lib.scripts.Thai.font, (strings[30]:GetFontObject():GetFont()))
		assert.is_nil(strings[31]:GetFontObject())
	end)
end)

-- The open list of a Blizzard UIDropDownMenu lives in the SHARED global frames DropDownList1/2,
-- parented to UIParent rather than to the consumer's window -- which is exactly why a normal frame
-- walk never reaches it, and why a dropdown's collapsed text fonts correctly while its open items
-- do not.
--
-- ORDERING NOTE, and it is load-bearing: the global ToggleDropDownMenu hook is installed ONCE per
-- Lua state (`ddFontHooked` is a file-local in the library), and the suite runs in one state. A
-- `frames.reset()` between examples reinstalls a fresh `_G.ToggleDropDownMenu` WITHOUT the hook,
-- and the library will not re-hook. So everything that depends on the hook being live is asserted
-- inside a single example rather than spread across several that reset in between.
describe("lib:AttachDropDownFont", function()
	it("ignores a dropdown that is not a table, without arming the global hook", function()
		H.reset()
		lib:AttachDropDownFont(H.addon(), nil)
		lib:AttachDropDownFont(H.addon(), "not a table")
	end)

	it("fonts the open list of a REGISTERED dropdown, and nobody else's", function()
		H.reset()
		local addon = H.addon()
		lib:RegisterLocale(addon, "enUS", { K = "en" }, true)

		-- The shared list frames and their buttons, as the client provides them.
		local list = CreateFrame("Frame", nil, UIParent)
		_G.DropDownList1 = list
		list:Hide()
		local items = {}
		for i = 1, 2 do
			local b = CreateFrame("Button", nil, list)
			local fs = b:CreateFontString(nil, "ARTWORK")
			b:SetFontString(fs)
			b:SetNormalFontObject(_G.GameFontNormal)
			b:SetWidth(100)
			fs:SetText(T.thai)
			b:Show()
			_G["DropDownList1Button" .. i] = b
			items[i] = b
		end

		local mine    = CreateFrame("Frame", nil, UIParent)
		local foreign = CreateFrame("Frame", nil, UIParent)
		mine.initialize = function() end
		foreign.initialize = function() end

		lib:AttachDropDownFont(addon, mine)
		lib:AttachDropDownFont(addon, mine)   -- a second registration must not double-hook

		-- Another addon's dropdown opening must leave the shared buttons alone.
		list:Show()
		_G.ToggleDropDownMenu(1, nil, foreign)
		assert.equal(_G.GameFontNormal, items[1]:GetNormalFontObject())

		-- Ours does font them, in every state.
		_G.CloseDropDownMenus()
		_G.ToggleDropDownMenu(1, nil, mine)
		assert.equal(lib.scripts.Thai.font, (items[1]:GetNormalFontObject():GetFont()))
		assert.equal(lib.scripts.Thai.font, (items[2]:GetHighlightFontObject():GetFont()))

		-- A hidden list button is skipped rather than fonted.
		_G.CloseDropDownMenus()
		items[2]:SetNormalFontObject(_G.GameFontNormal)
		items[2]:Hide()
		_G.ToggleDropDownMenu(1, nil, mine)
		assert.equal(_G.GameFontNormal, items[2]:GetNormalFontObject())

		-- The OnShow backstop: a submenu / re-show that never re-enters ToggleDropDownMenu.
		items[2]:Show()
		items[1]:SetNormalFontObject(_G.GameFontNormal)
		list:Hide()
		list:Show()
		assert.equal(lib.scripts.Thai.font, (items[1]:GetNormalFontObject():GetFont()))

		-- A hidden LIST is skipped entirely.
		list:Hide()
		items[1]:SetNormalFontObject(_G.GameFontNormal)
		_G.CloseDropDownMenus()
		_G.ToggleDropDownMenu(1, nil, mine)
		assert.equal(_G.GameFontNormal, items[1]:GetNormalFontObject())

		_G.DropDownList1, _G.DropDownList1Button1, _G.DropDownList1Button2 = nil, nil, nil
	end)
end)
