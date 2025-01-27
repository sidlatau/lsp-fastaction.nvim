local vim = vim
local api = vim.api
local validate = vim.validate
local floor = math.floor

local M = {}

M.window_border_chars_thick = {
	{ "▛", "FloatBorder" },
	{ "▀", "FloatBorder" },
	{ "▜", "FloatBorder" },
	{ "▐", "FloatBorder" },
	{ "▟", "FloatBorder" },
	{ "▄", "FloatBorder" },
	{ "▙", "FloatBorder" },
	{ "▌", "FloatBorder" },
}

M.window_border_chars_thin = {
	{ "🭽", "FloatBorder" },
	{ "▔", "FloatBorder" },
	{ "🭾", "FloatBorder" },
	{ "▕", "FloatBorder" },
	{ "🭿", "FloatBorder" },
	{ "▁", "FloatBorder" },
	{ "🭼", "FloatBorder" },
	{ "▏", "FloatBorder" },
}

M.window_border_chars_round = {
	{ "╭", "FloatBorder" },
	{ "─", "FloatBorder" },
	{ "╮", "FloatBorder" },
	{ "│", "FloatBorder" },
	{ "╯", "FloatBorder" },
	{ "─", "FloatBorder" },
	{ "╰", "FloatBorder" },
	{ "│", "FloatBorder" },
}

M.window_border_chars = M.window_border_chars_round

function M.scale_win(w, h)
	local win_width = floor(vim.fn.winwidth(0) * w)
	local win_height = floor(vim.fn.winheight(0) * h)
	return win_width, win_height
end

local function make_popup_options(width, height, opts)
	validate({
		opts = { opts, "t", true },
	})
	opts = opts or {}
	validate({
		["opts.offset_x"] = { opts.offset_x, "n", true },
		["opts.offset_y"] = { opts.offset_y, "n", true },
	})

	local anchor = ""
	local row, col

	local lines_above = vim.fn.winline() - 1
	local lines_below = vim.fn.winheight(0) - lines_above

	if lines_above < lines_below then
		anchor = anchor .. "N"
		height = math.min(lines_below, height)
		row = 1
	else
		anchor = anchor .. "S"
		height = math.min(lines_above, height)
		row = 0
	end

	-- if vim.fn.wincol() + width <= api.nvim_get_option_value("columns") then
	anchor = anchor .. "W"
	col = 0
	-- else
	-- 	anchor = anchor .. "E"
	-- 	col = 1
	-- end

	return {
		anchor = anchor,
		col = col + (opts.offset_x or 0),
		height = height,
		relative = "cursor",
		row = row + (opts.offset_y or 0),
		style = "minimal",
		width = width,
	}
end

function M.floating_window(opts)
	opts = opts or {}
	local border = opts.border
	if border == true then
		border = M.window_border_chars
	end

	opts.width_per = opts.width_per or 0.7
	opts.height_per = opts.height_per or 0.7
	opts.filetype = opts.filetype or ""

	validate({
		width_per = { opts.width_per, "n", true },
		height_per = { opts.height_per, "n", true },
	})

	local uis = api.nvim_list_uis()
	local ui_min_width = math.huge
	local ui_min_height = math.huge
	for _, ui in ipairs(uis) do
		ui_min_width = math.min(ui.width, ui_min_width)
		ui_min_height = math.min(ui.height, ui_min_height)
	end
	local win_width = floor(ui_min_width * opts.width_per)
	local win_height = floor(ui_min_height * opts.height_per)

	-- content window
	local content_opts = {
		relative = "editor",
		width = win_width - 4,
		height = win_height - 2,
		row = 1 + floor((ui_min_height - win_height) / 2),
		col = 2 + floor((ui_min_width - win_width) / 2),
		style = "minimal",
	}
	content_opts.border = border
	local content_buf = api.nvim_create_buf(false, true)
	local content_win = api.nvim_open_win(content_buf, true, content_opts)
	api.nvim_set_option_value("ft", opts.filetype, { buf = content_buf })
	api.nvim_set_option_value("wrap", false, { win = content_win })
	api.nvim_set_option_value("number", false, { win = content_win })
	api.nvim_set_option_value("relativenumber", false, { win = content_win })
	api.nvim_set_option_value("cursorline", false, { win = content_win })
	api.nvim_set_option_value("signcolumn", "no", { win = content_win })

	return content_buf, content_win
end

local cursor_hl_grp = "FastActionHiddenCursor"

local guicursor = vim.o.guicursor
-- Hide cursor whilst menu is open
function M.hide_cursor()
	if vim.o.termguicolors and vim.o.guicursor ~= "" then
		local fmt = string.format
		if vim.fn.hlexists(cursor_hl_grp) == 0 then
			vim.cmd(fmt("highlight %s gui=reverse blend=100", cursor_hl_grp))
		end
		vim.o.guicursor = fmt("a:%s/lCursor", cursor_hl_grp)
	end
end

local function restore_cursor()
	vim.o.guicursor = guicursor
end

function _G.__fastaction_popup_close()
	restore_cursor()
	pcall(vim.api.nvim_win_close, vim.api.nvim_get_current_win(), true)
end
---Helper function to close the actions menu
---@param win integer
---@param events string[]
local function close_popup_window(win, events)
	if #events > 0 then
		vim.cmd("autocmd " .. table.concat(events, ",") .. " <buffer> ++once lua __fastaction_popup_close()")
	end
end

function M.popup_window(contents, filetype, opts)
	validate({
		contents = { contents, "t" },
		filetype = { filetype, "s", true },
		opts = { opts, "t", true },
	})
	opts = opts or {}
	local border = opts.border
	if border == true then
		border = M.window_border_chars
	end

	-- Trim empty lines from the end.
	contents = vim.lsp.util.trim_empty_lines(contents)

	local width = opts.width
	local height = opts.height or #contents
	if not width then
		width = 0
		for i, line in ipairs(contents) do
			-- Clean up the input and add left pad.
			line = " " .. line:gsub("\r", "")
			local line_width = vim.fn.strdisplaywidth(line)
			width = math.max(line_width, width)
			contents[i] = line
		end
		-- Add right padding of 1 each.
		width = width + 1
	end

	-- content window
	local content_buf = api.nvim_create_buf(false, true)
	api.nvim_buf_set_lines(content_buf, 0, -1, true, contents)
	if filetype then
		api.nvim_set_option_value("filetype", filetype, { buf = content_buf })
	end
	api.nvim_set_option_value("modifiable", false, { buf = content_buf })
	local content_opts = make_popup_options(width, height, opts)
	if content_opts.anchor == "SE" then
		content_opts.row = content_opts.row - 1
		content_opts.col = content_opts.col - 1
	elseif content_opts.anchor == "NE" then
		content_opts.row = content_opts.row + 1
		content_opts.col = content_opts.col - 1
	elseif content_opts.anchor == "NW" then
		content_opts.row = content_opts.row + 1
		content_opts.col = content_opts.col + 1
	elseif content_opts.anchor == "SW" then
		content_opts.row = content_opts.row - 1
		content_opts.col = content_opts.col + 1
	end

	content_opts.border = border

	local content_win = api.nvim_open_win(content_buf, true, content_opts)
	if filetype == "markdown" then
		api.nvim_set_option_value("conceallevel", 2, { win = content_win })
	end
	--api.nvim_win_set_option(content_win, "winhighlight", "Normal:NormalNC")
	api.nvim_set_option_value("cursorline", false, { win = content_win })

	if opts.enter == true then
		api.nvim_set_current_win(content_win)
	end
	if opts.window_hl then
		api.nvim_set_option_value("winhighlight", "Normal:" .. opts.window_hl, { win = content_win })
	end
	close_popup_window(content_win, {
		"BufHidden",
		"InsertCharPre",
		"WinLeave",
		"FocusLost",
	})

	return content_buf, content_win
end

--  get decoration column with (signs + folding + number)
function M.window_decoration_columns()
	local function starts_with(str, start)
		return str:sub(1, #start) == start
	end

	local decoration_width = 0

	-- number width
	-- Note: 'numberwidth' is only the minimal width, can be more if...
	local max_number = 0
	if vim.api.nvim_get_option_value("number", { win = 0 }) then
		-- ...the buffer has many lines.
		max_number = vim.api.nvim_buf_line_count(0)
	elseif vim.api.nvim_get_option_value("relativenumber", { win = 0 }) then
		-- ...the window width has more digits.
		max_number = vim.fn.winheight(0)
	end
	if max_number > 0 then
		local actual_number_width = string.len(max_number) + 1
		local number_width = vim.api.nvim_get_option_value("numberwidth", { win = 0 })
		decoration_width = decoration_width + math.max(number_width, actual_number_width)
	end

	-- signs
	if vim.fn.has("signs") then
		local signcolumn = vim.api.nvim_get_option_value("signcolumn", { win = 0 })
		local signcolumn_width = 2
		if starts_with(signcolumn, "yes") or starts_with(signcolumn, "auto") then
			decoration_width = decoration_width + signcolumn_width
		end
	end

	-- folding
	if vim.fn.has("folding") then
		local folding_width = vim.api.nvim_get_option_value("foldcolumn", { win = 0 })
		decoration_width = decoration_width + folding_width
	end

	return decoration_width
end

return M
