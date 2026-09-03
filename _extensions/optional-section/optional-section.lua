-- optional-section.lua — drops slides/sections marked as optional.
--
-- Marking is done with the classes `.optional` and `.optional-extra` in three places:
--
--   1. **Headings** — removed is the heading plus everything up to the next
--      heading of the same or a higher level (the whole slide subtree, deeper
--      headings included).
--   2. **Divs** — `::: {.optional}` … `:::` removes the whole block.
--   3. **Inline spans** — `[text]{.optional}` removes that stretch of text. If
--      the span stands alone in a list item (`- [item]{.optional}`), the
--      **whole item** goes, indented sub-items included. List items cannot
--      carry attributes of their own in pandoc — the span is the way to mark
--      one.
--
-- Without further configuration the filter removes nothing — the classes then
-- act as a hint only and is used by the shipped CSS for badges.
-- On **headings** in RevealJS as a line in the speaker notes (see `markers_to_notes` below)
-- on the website still as a badge next to
-- the heading. The metadata option `remove-optional` is the switch:
--
--   remove-optional: none     (default) remove nothing
--   remove-optional: extra    remove `.optional-extra` only
--   remove-optional: all      remove `.optional` and `.optional-extra`
--
-- Handy while rendering, without touching the YAML:
--
--   quarto render slides.qmd -M remove-optional:extra
--
-- Whether the markers that stay are visible at all is a second option:
--
--   optional-badges: true     (default) the badge CSS is added
--   optional-badges: false    no badges; the classes stay in the html, but
--                             nothing is drawn (the speaker notes on RevealJS
--                             are not affected — they are for the presenter)
--
-- Applies to everything with attributes: Header, Div, Span, CodeBlock, … Blocks
-- without attributes (Para, BulletList, …) have no `classes` and are never
-- marked.
local function marked(el, mode)
	local classes = el.classes
	return classes ~= nil and (classes:includes("optional-extra") or (mode == "all" and classes:includes("optional")))
end

local function is_space(inline)
	return inline.t == "Space" or inline.t == "SoftBreak"
end

-- Drops marked spans from one inline list. Nested inlines, footnotes and image
-- alt texts are reached by the traversal, not from here.
local function prune_inlines(inlines, mode)
	local out = pandoc.Inlines({})
	local dropped = false
	for _, inline in ipairs(inlines) do
		if inline.t == "Span" and marked(inline, mode) then
			dropped = true
		elseif dropped and is_space(inline) and #out > 0 and is_space(out[#out]) then
			dropped = false -- swallow the doubled space around the removed spot
		else
			dropped = false
			out:insert(inline)
		end
	end
	return out
end

-- Drops marked blocks from one block list, and with a marked heading everything
-- up to the next heading of the same or a higher level.
local function prune_blocks(blocks, mode)
	local out = pandoc.Blocks({})
	local skip_level = nil
	for _, block in ipairs(blocks) do
		if block.t == "Header" then
			if skip_level and block.level > skip_level then
				-- deeper heading inside the removed subtree: goes along
			elseif marked(block, mode) then
				skip_level = block.level
			else
				skip_level = nil
				out:insert(block)
			end
		elseif skip_level == nil and not marked(block, mode) then
			out:insert(block)
		end
	end
	return out
end

-- A list item counts as marked when its first block consists **only** of marked
-- content — so `- [item]{.optional}`, or an item starting with a marked div. A
-- span in mid-sentence (`- item [extra]{.optional}`) only removes itself.
local function item_is_marked(item, mode)
	local first = item[1]
	if first == nil then
		return false
	end
	if first.t == "Div" then
		return marked(first, mode)
	end
	if first.t ~= "Plain" and first.t ~= "Para" then
		return false
	end

	local found = false
	for _, inline in ipairs(first.content) do
		if inline.t == "Span" and marked(inline, mode) then
			found = true
		elseif not is_space(inline) then
			return false
		end
	end
	return found
end

local function keep_items(items, mode)
	local out = {}
	for _, item in ipairs(items) do
		if not item_is_marked(item, mode) then
			table.insert(out, item)
		end
	end
	return out
end

-- The traversal runs top down, because a list item and a definition term have
-- to be judged while their marked spans are still in place — the Inlines
-- handler would otherwise have emptied them first. Everything nested (divs,
-- quotes, table cells, captions, footnotes, image alt texts) is reached by
-- pandoc, so only these five handlers are needed.
local function pruner(mode)
	local function items(list)
		list.content = keep_items(list.content, mode)
		return list
	end

	return {
		traverse = "topdown",
		Blocks = function(blocks)
			return prune_blocks(blocks, mode)
		end,
		Inlines = function(inlines)
			return prune_inlines(inlines, mode)
		end,
		BulletList = items,
		OrderedList = items,
		DefinitionList = function(list)
			local out = {}
			for _, entry in ipairs(list.content) do
				local term = prune_inlines(entry[1], mode)
				-- a term emptied by the pruning takes its definitions with it
				if #term > 0 or #entry[1] == 0 then
					table.insert(out, { term, keep_items(entry[2], mode) })
				end
			end
			list.content = out
			return list
		end,
	}
end

-- On the slides, a marked **heading** is the presenter's business: it moves
-- into the speaker notes as a line instead of sitting above the slide title as
-- a badge. That needs the class gone — RevealJS would otherwise pass it on to
-- the `<section>`, and the badge comes from the CSS
-- (optional-section-revealjs.css).
--
-- Marked divs and spans keep their badge: they point at a spot **inside** the
-- slide, which cannot be moved into a note.
local function heading_marker(header)
	if header.classes:includes("optional-extra") then
		return "optional-extra"
	end
	if header.classes:includes("optional") then
		return "optional"
	end
end

local function markers_to_notes(blocks)
	local out = pandoc.Blocks({})
	local changed = false
	for _, block in ipairs(blocks) do
		out:insert(block)
		local marker = block.t == "Header" and heading_marker(block)
		if marker then
			block.classes = block.classes:filter(function(class)
				return class ~= "optional" and class ~= "optional-extra"
			end)
			-- pandoc.Plain would parse a bare string into Str/Space/Str
			local note = pandoc.Plain(pandoc.Str("⚑ " .. marker))
			out:insert(pandoc.Div(note, pandoc.Attr("", { "notes" })))
			changed = true
		end
	end
	if changed then
		return out
	end
end

-- `optional-badges: false` (a boolean in the YAML, a string via `-M`) switches
-- the badges off; anything else, including an absent key, leaves them on.
local function badges_wanted(meta)
	local raw = meta["optional-badges"]
	if raw == nil then
		return true
	end
	if type(raw) == "boolean" then
		return raw
	end
	local value = pandoc.utils.stringify(raw)
	return value ~= "false" and value ~= "no"
end

-- The badges for marked divs and spans come from CSS that ships with the
-- extension; the filter adds it itself, so nothing has to be put into the
-- theme.
local function add_badge_css()
	quarto.doc.add_html_dependency({
		name = "optional-section",
		version = "0.1.0",
		stylesheets = {
			quarto.doc.is_format("revealjs") and "optional-section-revealjs.css" or "optional-section-html.css",
		},
	})
end

function Pandoc(doc)
	local raw = doc.meta["remove-optional"]
	local mode = raw and pandoc.utils.stringify(raw) or "none"

	if mode == "extra" or mode == "all" then
		doc.blocks = doc.blocks:walk(pruner(mode))
	elseif mode ~= "none" and mode ~= "" then
		local msg = "optional: unknown value remove-optional="
			.. mode
			.. " — allowed: none, extra, all. Nothing is removed."
		quarto.log.warning(msg)
	end

	if quarto.doc.is_format("revealjs") then
		doc.blocks = doc.blocks:walk({ Blocks = markers_to_notes })
	end
	-- matches every html-based format, revealjs included
	if quarto.doc.is_format("html:js") and badges_wanted(doc.meta) then
		add_badge_css()
	end

	return doc
end
