local parser = require("nabla.latex")

local ascii = require("nabla.ascii")

local ts_utils = vim.treesitter
local utils=require"nabla.utils"

local autogen_autocmd = {}
local mode_autocmd = {}
local autogen_flag = false

local virt_enabled = {}

local saved_conceallevel = {}
local saved_concealcursor = {}
local saved_wrap = {}

local mult_virt_ns = {}



local colorize

local colorize_virt

local enable_virt

local disable_virt

local toggle_virt

local is_virt_enabled

function colorize(g, first_dx, dx, dy, ns_id, drawing, px, py, buf)
  if g.t == "num" then
    local off
    if dy == 0 then off = first_dx else off = dx end

    local sx = vim.str_byteindex(drawing[dy+1], off)
    local se = vim.str_byteindex(drawing[dy+1], off+g.w)

    local of
    if dy == 0 then of = px else of = 0 end
    vim.api.nvim_buf_add_highlight(buf, ns_id, "@number", py+dy, of+sx,of+se)
  end

  if g.t == "sym" then
    local off
    if dy == 0 then off = first_dx else off = dx end

    local sx = vim.str_byteindex(drawing[dy+1], off)
    local se = vim.str_byteindex(drawing[dy+1], off+g.w)

    if string.match(g.content[1], "^%a") then
      local of
      if dy == 0 then of = px else of = 0 end
      vim.api.nvim_buf_add_highlight(buf, ns_id, "@string", dy+py, of+sx, of+se)

    elseif string.match(g.content[1], "^%d") then
      local of
      if dy == 0 then of = px else of = 0 end
      vim.api.nvim_buf_add_highlight(buf, ns_id, "@number", dy+py, of+sx, of+se)

    else
      for y=1,g.h do
        local off
        if y+dy == 1 then off = first_dx else off = dx end

        local sx = vim.str_byteindex(drawing[dy+y], off)
        local se = vim.str_byteindex(drawing[dy+y], off+g.w)
        local of
        if y+dy == 1 then of = px else of = 0 end
        vim.api.nvim_buf_add_highlight(buf, ns_id, "@operator", dy+py+y-1, of+sx, of+se)
      end
    end
  end

  if g.t == "op" then
    for y=1,g.h do
      local off
      if y+dy == 1 then off = first_dx else off = dx end

      local sx = vim.str_byteindex(drawing[dy+y], off)
      local se = vim.str_byteindex(drawing[dy+y], off+g.w)

      local of
      if dy+y == 1 then of = px else of = 0 end
      vim.api.nvim_buf_add_highlight(buf, ns_id, "@operator", dy+py+y-1, of+sx, of+se)
    end
  end
  if g.t == "par" then
    for y=1,g.h do
      local off
      if y+dy == 1 then off = first_dx else off = dx end

      local sx = vim.str_byteindex(drawing[dy+y], off)
      local se = vim.str_byteindex(drawing[dy+y], off+g.w)

      local of
      if y+dy == 1 then of = px else of = 0 end
      vim.api.nvim_buf_add_highlight(buf, ns_id, "@operator", dy+py+y-1, of+sx, of+se)
    end
  end

  if g.t == "var" then
    local off
    if dy == 0 then off = first_dx else off = dx end

    local sx = vim.str_byteindex(drawing[dy+1], off)
    local se = vim.str_byteindex(drawing[dy+1], off+g.w)

    local of
    if dy == 0 then of = px else of = 0 end
    vim.api.nvim_buf_add_highlight(buf, ns_id, "@string", dy+py, of+sx, of+se)
  end

  for _, child in ipairs(g.children) do
    colorize(child[1], child[2]+first_dx, child[2]+dx, child[3]+dy, ns_id, drawing, px, py, buf)
  end

end

function colorize_virt(g, virt_lines, first_dx, dx, dy)
  if g.t == "num" then
    local off
    if dy == 0 then off = first_dx else off = dx end

    for i=1,g.w do
      virt_lines[dy+1][off+i][2] = "@number"
    end
  end

  if g.t == "sym" then
    local off
    if dy == 0 then off = first_dx else off = dx end

    if string.match(g.content[1], "^%a") then
      for i=1,g.w do
        virt_lines[dy+1][off+i][2] = "@string"
      end

    elseif string.match(g.content[1], "^%d") then
      for i=1,g.w do
        virt_lines[dy+1][off+i][2] = "@number"
      end


    else
      for y=1,g.h do
        local off
        if y+dy == 1 then off = first_dx else off = dx end

        for i=1,g.w do
          virt_lines[dy+y][off+i][2] = "@operator"
        end

      end
    end
  end

  if g.t == "op" then
    for y=1,g.h do
      local off
      if y+dy == 1 then off = first_dx else off = dx end

      for i=1,g.w do
        virt_lines[dy+y][off+i][2] = "@operator"
      end
    end
  end
  if g.t == "par" then
    for y=1,g.h do
      local off
      if y+dy == 1 then off = first_dx else off = dx end

      for i=1,g.w do
        virt_lines[dy+y][off+i][2] = "@operator"
      end
    end
  end

  if g.t == "var" then
    local off
    if dy == 0 then off = first_dx else off = dx end

    for i=1,g.w do
      virt_lines[dy+1][off+i][2] = "@string"
    end
  end

  for _, child in ipairs(g.children) do
    colorize_virt(child[1], virt_lines, child[2]+first_dx, child[2]+dx, child[3]+dy)
  end

end

local function gen_drawing(lines)
  local parser = require("nabla.latex")
  local ascii = require("nabla.ascii")
  local line = table.concat(lines, " ")

  local success, exp = pcall(parser.parse_all, line)


  if success and exp then
    local succ, g = pcall(ascii.to_ascii, {exp}, 1)
    if not succ then
      print(g)
      return 0
    end

    if not g or g == "" then
      vim.api.nvim_echo({{"Empty expression detected. Please use the $...$ syntax.", "ErrorMsg"}}, false, {})
      return 0
    end

    local drawing = {}
    for row in vim.gsplit(tostring(g), "\n") do
    	table.insert(drawing, row)
    end
    if whitespace then
    	for i=1,#drawing do
    		drawing[i] = whitespace .. drawing[i]
    	end
    end



    return drawing
  end
  return 0
end

local function gen_drawing_typst(text)
  local typst = require("nabla.typst")
  local ascii = require("nabla.ascii")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {"$" .. text .. "$"})
  vim.bo[buf].filetype = "typst"
  local ok, ts_parser = pcall(vim.treesitter.get_parser, buf, "typst")
  if not ok or not ts_parser then
    vim.api.nvim_buf_delete(buf, {force = true})
    return 0
  end
  local tree = ts_parser:parse()[1]
  local root = tree:root()
  local math_node = nil
  for child in root:iter_children() do
    if child:type() == "math" then
      math_node = child
      break
    end
  end
  if not math_node then
    vim.api.nvim_buf_delete(buf, {force = true})
    return 0
  end
  local exp = typst.parse_math_node(math_node, buf)
  vim.api.nvim_buf_delete(buf, {force = true})
  if exp then
    local succ, g = pcall(ascii.to_ascii, {exp}, 1)
    if not succ then print(g); return 0 end
    if not g or g == "" then return 0 end
    local drawing = {}
    for row in vim.gsplit(tostring(g), "\n") do
      table.insert(drawing, row)
    end
    return drawing
  end
  return 0
end

local function gen_drawing_latex_ts(text)
  local latex_ts = require("nabla.latex_ts")
  local ascii = require("nabla.ascii")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {"$" .. text .. "$"})
  local ok, ts_parser = pcall(vim.treesitter.get_parser, buf, "latex")
  if not ok or not ts_parser then
    vim.api.nvim_buf_delete(buf, {force = true})
    return 0
  end
  local tree = ts_parser:parse()[1]
  local root = tree:root()
  local formula_node = nil
  for child in root:iter_children() do
    if child:type() == "inline_formula" or child:type() == "displayed_equation" then
      formula_node = child
      break
    end
  end
  if not formula_node then
    vim.api.nvim_buf_delete(buf, {force = true})
    return 0
  end
  local ok_parse, exp = pcall(latex_ts.parse_math_node, formula_node, buf)
  vim.api.nvim_buf_delete(buf, {force = true})
  if not ok_parse then return 0 end
  if exp then
    local succ, g = pcall(ascii.to_ascii, {exp}, 1)
    if not succ then print(g); return 0 end
    if not g or g == "" then return 0 end
    local drawing = {}
    for row in vim.gsplit(tostring(g), "\n") do
      table.insert(drawing, row)
    end
    return drawing
  end
  return 0
end

local function popup(overrides)
  if not utils.in_mathzone() then
    return
  end

  local math_node = utils.in_mathzone()
  local buf = vim.api.nvim_get_current_buf()
  local ft = vim.bo[buf].filetype

  local exp
  if ft == "typst" then
    local typst = require("nabla.typst")
    exp = typst.parse_math_node(math_node, buf)
  elseif ft == "markdown" then
    local ok, latex_ts = pcall(require, "nabla.latex_ts")
    if ok then
      local ok_parse, result = pcall(latex_ts.parse_math_node, math_node, buf)
      if ok_parse then exp = result end
    end
    if not exp or (#exp.exps == 0) then
      -- fallback to handwritten parser
      local srow, scol, erow, ecol = ts_utils.get_node_range(math_node)
      local lines = vim.api.nvim_buf_get_text(0, srow, scol, erow, ecol, {})
      local line = table.concat(lines, " ")
      line = line:gsub("%$", "")
      line = line:gsub("\\%[", "")
      line = line:gsub("\\%]", "")
      line = line:gsub("^\\%(", "")
      line = line:gsub("\\%)$", "")
      line = vim.trim(line)
      if line == "" then return end
      local success, result = pcall(parser.parse_all, line)
      if not success then print(result); return end
      exp = result
    end
  else
    local srow, scol, erow, ecol = ts_utils.get_node_range(math_node)
    local lines = vim.api.nvim_buf_get_text(0, srow, scol, erow, ecol, {})
    local line = table.concat(lines, " ")
    line = line:gsub("%$", "")
    line = line:gsub("\\%[", "")
    line = line:gsub("\\%]", "")
    line = line:gsub("^\\%(", "")
    line = line:gsub("\\%)$", "")
    line = vim.trim(line)
    if line == "" then return end
    local success, result = pcall(parser.parse_all, line)
    if not success then print(result); return end
    exp = result
  end

  if exp then
    local succ, g = pcall(ascii.to_ascii, {exp}, 1)
    if not succ then
      print(g)
      return 0
    end

    if not g or g == "" then
      vim.api.nvim_echo({{"Empty expression detected.", "ErrorMsg"}}, false, {})
      return 0
    end

    local drawing = {}
    for row in vim.gsplit(tostring(g), "\n") do
    	table.insert(drawing, row)
    end
    if whitespace then
    	for i=1,#drawing do
    		drawing[i] = whitespace .. drawing[i]
    	end
    end

    local floating_default_options = {
      wrap = false,
      focusable = false,
      border = 'single',
    	stylize_markdown=false
    }
    local bufnr_float, winr_float = vim.lsp.util.open_floating_preview(drawing, 'markdown', vim.tbl_deep_extend('force', floating_default_options, overrides or {}))
    local ns_id = vim.api.nvim_create_namespace("")
    colorize(g, 0, 0, 0, ns_id, drawing, 0, 0, bufnr_float)
  end

end

function enable_virt(opts)
  local buf = vim.api.nvim_get_current_buf()
  virt_enabled[buf] = true
  local ft = vim.bo[buf].filetype

  if mult_virt_ns[buf] == nil then
    mult_virt_ns[buf] = vim.api.nvim_create_namespace("nabla.nvim")
  end

  local formula_nodes = utils.get_all_mathzones(opts)
  local formulas_loc = {}
  for _, node in ipairs(formula_nodes) do
    local srow, scol, erow, ecol = ts_utils.get_node_range(node)
    table.insert(formulas_loc, {srow, scol, erow, ecol})
  end

  -- Parse formulas and generate drawings
  local line_formulas = {}
  for loc_idx, loc in ipairs(formulas_loc) do
    local srow, scol, erow, ecol = unpack(loc)

    local exp
    if ft == "typst" then
      local typst = require("nabla.typst")
      exp = typst.parse_math_node(formula_nodes[loc_idx], buf)
    elseif ft == "markdown" then
      local ok, latex_ts = pcall(require, "nabla.latex_ts")
      if ok then
        local ok_parse, result = pcall(latex_ts.parse_math_node, formula_nodes[loc_idx], buf)
        if ok_parse then exp = result end
      end
      if not exp or (#exp.exps == 0) then
        local succ, texts = pcall(vim.api.nvim_buf_get_text, buf, srow, scol, erow, ecol, {})
        if succ then
          local line = table.concat(texts, " ")
          line = line:gsub("%$", "")
          line = line:gsub("\\%[", "")
          line = line:gsub("\\%]", "")
          line = line:gsub("^\\%(", "")
          line = line:gsub("\\%)$", "")
          line = vim.trim(line)
          local success, result = pcall(parser.parse_all, line)
          if success and result then exp = result end
        end
      end
    else
      local succ, texts = pcall(vim.api.nvim_buf_get_text, buf, srow, scol, erow, ecol, {})
      if succ then
        local line = table.concat(texts, " ")
        line = line:gsub("%$", "")
        line = line:gsub("\\%[", "")
        line = line:gsub("\\%]", "")
        line = line:gsub("^\\%(", "")
        line = line:gsub("\\%)$", "")
        line = vim.trim(line)
        local success, result = pcall(parser.parse_all, line)
        if success and result then exp = result end
      end
    end

    if exp then
      local succ, g = pcall(ascii.to_ascii, {exp}, 1)
      if not succ then print(g); return 0 end
      if not g or g == "" then
        vim.api.nvim_echo({{"Empty expression detected.", "ErrorMsg"}}, false, {})
        return 0
      end

      local drawing = {}
      for row in vim.gsplit(tostring(g), "\n") do
        table.insert(drawing, row)
      end

      local drawing_virt = {}
      for j = 1, #drawing do
        local len = vim.str_utfindex(drawing[j])
        local new_virt_line = {}
        for i = 1, len do
          local a = vim.str_byteindex(drawing[j], i - 1)
          local b = vim.str_byteindex(drawing[j], i)
          table.insert(new_virt_line, { drawing[j]:sub(a + 1, b), "Normal" })
        end
        table.insert(drawing_virt, new_virt_line)
      end
      colorize_virt(g, drawing_virt, 0, 0, 0)

      if not line_formulas[srow] then line_formulas[srow] = {} end
      table.insert(line_formulas[srow], {
        scol = scol, ecol = ecol, srow = srow, erow = erow,
        drawing_virt = drawing_virt, g_my = g.my,
      })
    else
      if not (opts and opts.silent) then print(exp) end
    end
  end

  -- Set conceallevel BEFORE rendering so Neovim evaluates wrap correctly
  local win = vim.api.nvim_get_current_win()
  saved_conceallevel[win] = vim.wo[win].conceallevel
  saved_concealcursor[win] = vim.wo[win].concealcursor
  saved_wrap[win] = vim.wo[win].wrap
  vim.wo[win].conceallevel = 2
  vim.wo[win].concealcursor = ""
  vim.wo[win].wrap = false

  -- Toggle preview on insert mode: restore original settings on enter,
  -- re-apply nabla settings on leave.
  if mode_autocmd[buf] then
    vim.api.nvim_del_autocmd(mode_autocmd[buf])
  end
  mode_autocmd[buf] = vim.api.nvim_create_autocmd({"InsertEnter", "InsertLeave"}, {
    buffer = buf,
    desc = "nabla.nvim: toggle preview on insert mode",
    callback = function(args)
      if args.event == "InsertEnter" then
        local w = vim.api.nvim_get_current_win()
        if saved_conceallevel[w] then
          vim.wo[w].conceallevel = saved_conceallevel[w]
        end
        if saved_wrap[w] ~= nil then
          vim.wo[w].wrap = saved_wrap[w]
        end
      else
        autogen_flag = true
        disable_virt()
        autogen_flag = false
        enable_virt()
      end
    end
  })

  -- Conceal baselines and place virt_lines
  local ns = mult_virt_ns[buf]
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  -- Helper: display width of a virt_line chunk list
  local function vline_width(vline)
    local w = 0
    for _, chunk in ipairs(vline) do
      w = w + vim.fn.strdisplaywidth(chunk[1])
    end
    return w
  end

  for row, formulas in pairs(line_formulas) do
    table.sort(formulas, function(a, b) return a.scol < b.scol end)

    local line_text = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
    if not line_text then goto continue_row end

    -- Build conceal info for formula bytes
    -- Row 0: use first row of drawing (top row visible on buffer line)
    -- Other rows: use baseline row of drawing
    local conceal_chars = {}
    local conceal_hls = {}
    for _, f in ipairs(formulas) do
      local is_multiline = f.erow and f.erow ~= row
      local conceal_dv
      if is_multiline then
        conceal_dv = nil
      elseif row == 0 then
        conceal_dv = f.drawing_virt[1]
      else
        conceal_dv = f.drawing_virt[f.g_my + 1]
      end
      local end_col = is_multiline and #line_text or f.ecol
      -- Find character range for this formula
      local char_start = 0
      do
        local p = 0
        while p < f.scol do
          char_start = char_start + 1
          p = vim.str_byteindex(line_text, char_start)
        end
      end
      local char_end = char_start
      do
        local p = vim.str_byteindex(line_text, char_start)
        while p < end_col do
          char_end = char_end + 1
          p = vim.str_byteindex(line_text, char_end)
        end
      end
      -- Set conceal per character
      for ci = char_start, char_end - 1 do
        local a = vim.str_byteindex(line_text, ci)
        local next_a = vim.str_byteindex(line_text, ci + 1)
        local idx = ci - char_start + 1
        local c = ""
        local hl = nil
        if conceal_dv and idx <= #conceal_dv then
          c = conceal_dv[idx][1]
          hl = conceal_dv[idx][2]
        end
        conceal_chars[a] = c
        conceal_hls[a] = hl
        -- Subsequent bytes of multi-char: empty (width 0)
        for b = a + 1, next_a - 1 do
          conceal_chars[b] = ""
          conceal_hls[b] = nil
        end
      end
    end

    -- Compute visible column at each byte position using strdisplaywidth
    local vis_col_at = {}
    local col = 0
    local utf_len = vim.str_utfindex(line_text or "")
    for ui = 0, utf_len - 1 do
      local a = vim.str_byteindex(line_text, ui)
      local next_a = vim.str_byteindex(line_text, ui + 1)
      if next_a == a then break end

      local char_width
      if conceal_chars[a] ~= nil then
        char_width = vim.fn.strdisplaywidth(conceal_chars[a] or "")
      else
        char_width = vim.fn.strdisplaywidth(line_text:sub(a + 1, next_a))
      end

      vis_col_at[a] = col
      col = col + char_width
    end
    -- Build char_widths: per-character {col, width} for matched padding
    local char_widths = {}
    do
      local c = 0
      for ui2 = 0, utf_len - 1 do
        local a = vim.str_byteindex(line_text, ui2)
        local na = vim.str_byteindex(line_text, ui2 + 1)
        if na == a then break end
        local w
        if conceal_chars[a] ~= nil then
          w = vim.fn.strdisplaywidth(conceal_chars[a] or "")
        else
          w = vim.fn.strdisplaywidth(line_text:sub(a + 1, na))
        end
        table.insert(char_widths, {col = c, width = w})
        c = c + w
      end
    end

    -- Build padding chunks matching baseline character widths
    -- so split_into_blocks produces the same block boundaries.
    local function matched_padding(from_col, to_col)
      local chunks = {}
      for _, cw in ipairs(char_widths) do
        if cw.col >= to_col then break end
        if cw.col >= from_col then
          table.insert(chunks, {string.rep(" ", cw.width), "Normal"})
        end
      end
      local total = from_col
      for _, ch in ipairs(chunks) do
        total = total + vim.fn.strdisplaywidth(ch[1])
      end
      while total < to_col do
        table.insert(chunks, {" ", "Normal"})
        total = total + 1
      end
      return chunks
    end
    local total_vis_col = col

    for _, f in ipairs(formulas) do
      local is_multiline = f.erow and f.erow ~= row
      local conceal_dv
      if is_multiline then
        conceal_dv = nil
      elseif row == 0 then
        conceal_dv = f.drawing_virt[1]
      else
        conceal_dv = f.drawing_virt[f.g_my + 1]
      end
      local end_col = is_multiline and #line_text or f.ecol
      -- Find character range
      local char_start = 0
      do
        local p = 0
        while p < f.scol do
          char_start = char_start + 1
          p = vim.str_byteindex(line_text, char_start)
        end
      end
      local char_end = char_start
      do
        local p = vim.str_byteindex(line_text, char_start)
        while p < end_col do
          char_end = char_end + 1
          p = vim.str_byteindex(line_text, char_end)
        end
      end
      -- Set extmark per character (covers full multi-byte range)
      for ci = char_start, char_end - 1 do
        local a = vim.str_byteindex(line_text, ci)
        local next_a = vim.str_byteindex(line_text, ci + 1)
        local idx = ci - char_start + 1
        local c, hl = "", nil
        if conceal_dv and idx <= #conceal_dv then
          c = conceal_dv[idx][1]
          hl = conceal_dv[idx][2]
        end
        local mark_opts = {
          end_row = row, end_col = next_a,
          conceal = c, strict = false,
        }
        if hl and hl ~= "Normal" then mark_opts.hl_group = hl end
        vim.api.nvim_buf_set_extmark(buf, ns, row, a, mark_opts)
      end
    end

    -- Build above_list and below_list (formula drawing rows, padded to column)
    local above_list = {}
    local below_list = {}
    if row == 0 then
      -- Row 0: buffer line shows first row; rows 2..N go below.
      -- Multi-line formulas: all rows go below (buffer can't show drawing).
      local row0_below = {}
      local max_r = 0
      for _, f in ipairs(formulas) do
        if #f.drawing_virt > max_r then max_r = #f.drawing_virt end
        local fcol = vis_col_at[f.scol] or 0
        local is_multiline = f.erow and f.erow ~= row
        local start_r = is_multiline and 1 or 2
        for r = start_r, #f.drawing_virt do
          local vline = row0_below[r] or {}
          local current_w = vline_width(vline)
          if current_w < fcol then
            local chunks = matched_padding(current_w, fcol)
            for _, chunk in ipairs(chunks) do table.insert(vline, chunk) end
          end
          vim.list_extend(vline, f.drawing_virt[r])
          row0_below[r] = vline
        end
      end
      for r = 1, max_r do
        if row0_below[r] then table.insert(below_list, row0_below[r]) end
      end
    else
      -- Non-row-0: baseline on buffer line, above/below as virt_lines.
      local above_map = {}
      local below_map = {}
      for _, f in ipairs(formulas) do
        local fcol = vis_col_at[f.scol] or 0
        local conceal_row_idx = f.g_my + 1
        local is_multiline = f.erow and f.erow ~= row
        for r = 1, #f.drawing_virt do
          if is_multiline then
            -- Multi-line: all rows go below (baseline concealed to empty)
            local vline = below_map[r] or {}
            local current_w = vline_width(vline)
            if current_w < fcol then
              local chunks = matched_padding(current_w, fcol)
              for _, chunk in ipairs(chunks) do table.insert(vline, chunk) end
            end
            vim.list_extend(vline, f.drawing_virt[r])
            below_map[r] = vline
          elseif r ~= conceal_row_idx then
            local target, relrow
            if r < conceal_row_idx then
              relrow = conceal_row_idx - r
              target = above_map
            else
              relrow = r - conceal_row_idx
              target = below_map
            end
            local vline = target[relrow] or {}
            local current_w = vline_width(vline)
            if current_w < fcol then
              local chunks = matched_padding(current_w, fcol)
              for _, chunk in ipairs(chunks) do table.insert(vline, chunk) end
            end
            vim.list_extend(vline, f.drawing_virt[r])
            target[relrow] = vline
          end
        end
      end
      local max_above = 0
      for k, _ in pairs(above_map) do if k > max_above then max_above = k end end
      local max_below = 0
      for k, _ in pairs(below_map) do if k > max_below then max_below = k end end
      for i = max_above, 1, -1 do
        if above_map[i] then table.insert(above_list, above_map[i]) end
      end
      for i = 1, max_below do
        if below_map[i] then table.insert(below_list, below_map[i]) end
      end
    end

    -- Build baseline virt_line using vis_col positions
    -- Always use baseline drawing (not row 0's first-row drawing)
    local baseline_conceal = {}
    for _, f in ipairs(formulas) do
      local conceal_dv = f.drawing_virt[f.g_my + 1]
      local is_multiline = f.erow and f.erow ~= row
      if is_multiline then conceal_dv = nil end
      local end_col = is_multiline and #line_text or f.ecol
      local char_start = 0
      do
        local p = 0
        while p < f.scol do
          char_start = char_start + 1
          p = vim.str_byteindex(line_text, char_start)
        end
      end
      local char_end = char_start
      do
        local p = vim.str_byteindex(line_text, char_start)
        while p < end_col do
          char_end = char_end + 1
          p = vim.str_byteindex(line_text, char_end)
        end
      end
      for ci = char_start, char_end - 1 do
        local a = vim.str_byteindex(line_text, ci)
        local next_a = vim.str_byteindex(line_text, ci + 1)
        local idx = ci - char_start + 1
        if conceal_dv and idx <= #conceal_dv then
          baseline_conceal[a] = conceal_dv[idx][1]
        else
          baseline_conceal[a] = ""
        end
        for b = a + 1, next_a - 1 do
          baseline_conceal[b] = ""
        end
      end
    end
    local baseline_flat = {}
    for c = 0, total_vis_col - 1 do
      baseline_flat[c] = {" ", "Normal"}
    end
    local utf_len2 = vim.str_utfindex(line_text)
    for ui = 0, utf_len2 - 1 do
      local a = vim.str_byteindex(line_text, ui)
      local next_a = vim.str_byteindex(line_text, ui + 1)
      if next_a == a then break end
      local vc = vis_col_at[a]
      if vc == nil then goto continue_bl end
      local char_str
      if baseline_conceal[a] ~= nil then
        char_str = baseline_conceal[a]
      else
        char_str = line_text:sub(a + 1, next_a)
        if char_str == "$" then char_str = nil end
      end
      if char_str and char_str ~= "" then
        baseline_flat[vc] = {char_str, "Normal"}
        -- Wide chars occupy multiple vis_col positions; fill with empty
        local cw = vim.fn.strdisplaywidth(char_str)
        for i = 1, cw - 1 do
          if vc + i < total_vis_col then
            baseline_flat[vc + i] = {"", "Normal"}
          end
        end
      end
      ::continue_bl::
    end
    local baseline_vline = {}
    for c = 0, total_vis_col - 1 do
      table.insert(baseline_vline, baseline_flat[c])
    end

    -- Get screen width for splitting
    local textoff = vim.fn.getwininfo(win)[1].textoff
    local text_width = vim.api.nvim_win_get_width(win) - textoff

    -- Split a virt_line into screen-width blocks
    local function split_into_blocks(vline, width)
      local blocks = {}
      local block = {}
      local col = 0
      for _, chunk in ipairs(vline) do
        local cw = vim.fn.strdisplaywidth(chunk[1])
        -- Width 0 chars (combining, zero-width) piggyback on previous
        if cw <= 0 then
          if #block > 0 then
            local prev = block[#block]
            block[#block] = {prev[1] .. chunk[1], prev[2]}
          else
            table.insert(block, chunk)
          end
          goto next_chunk
        end
        if col + cw > width and col > 0 then
          -- Pad to width and flush
          while col < width do
            table.insert(block, {" ", "Normal"})
            col = col + 1
          end
          table.insert(blocks, block)
          block = {}
          col = 0
        end
        table.insert(block, chunk)
        col = col + cw
        ::next_chunk::
      end
      if #block > 0 then
        while col < width do
          table.insert(block, {" ", "Normal"})
          col = col + 1
        end
        table.insert(blocks, block)
      end
      if #blocks == 0 then
        local empty = {}
        for _ = 1, width do table.insert(empty, {" ", "Normal"}) end
        table.insert(blocks, empty)
      end
      return blocks
    end

    -- Split all virt_lines into blocks
    local above_blocks = {}
    for _, vline in ipairs(above_list) do
      local blocks = split_into_blocks(vline, text_width)
      for b, block in ipairs(blocks) do
        if not above_blocks[b] then above_blocks[b] = {} end
        table.insert(above_blocks[b], block)
      end
    end
    local below_blocks = {}
    for _, vline in ipairs(below_list) do
      local blocks = split_into_blocks(vline, text_width)
      for b, block in ipairs(blocks) do
        if not below_blocks[b] then below_blocks[b] = {} end
        table.insert(below_blocks[b], block)
      end
    end
    local baseline_blocks = split_into_blocks(baseline_vline, text_width)

    -- Build final virt_lines: block 0 above, then block 0 below,
    -- then block 1+ (above + baseline + below interleaved)
    local final_above = {}
    local final_below = {}

    -- Block 0 above rows
    if above_blocks[1] then
      for _, vl in ipairs(above_blocks[1]) do
        table.insert(final_above, vl)
      end
    end

    -- Block 0 below rows
    if below_blocks[1] then
      for _, vl in ipairs(below_blocks[1]) do
        table.insert(final_below, vl)
      end
    end

    -- Block 1+ (above + baseline + below, interleaved, empty rows omitted)
    local max_block = math.max(
      #baseline_blocks,
      above_blocks[#above_blocks] and #above_blocks or 0,
      below_blocks[#below_blocks] and #below_blocks or 0
    )
    for b = 2, max_block do
      if above_blocks[b] then
        for _, vl in ipairs(above_blocks[b]) do
          local has_content = false
          for _, chunk in ipairs(vl) do if chunk[1] ~= " " then has_content = true; break end end
          if has_content then table.insert(final_below, vl) end
        end
      end
      if baseline_blocks[b] then
        local has_content = false
        for _, chunk in ipairs(baseline_blocks[b]) do if chunk[1] ~= " " then has_content = true; break end end
        if has_content then table.insert(final_below, baseline_blocks[b]) end
      end
      if below_blocks[b] then
        for _, vl in ipairs(below_blocks[b]) do
          local has_content = false
          for _, chunk in ipairs(vl) do if chunk[1] ~= " " then has_content = true; break end end
          if has_content then table.insert(final_below, vl) end
        end
      end
    end

    -- Place virt_lines
    if #final_above > 0 then
      vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
        virt_lines = final_above,
        virt_lines_above = true,
      })
    end
    if #final_below > 0 then
      vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
        virt_lines = final_below,
        virt_lines_overflow = "scroll",
      })
    end

    ::continue_row::
  end

  -- Conceal multi-line formula bytes on non-starting rows
  for _, formulas in pairs(line_formulas) do
    for _, f in ipairs(formulas) do
      if f.erow and f.erow > f.srow then
        for r = f.srow + 1, f.erow do
          local lt = vim.api.nvim_buf_get_lines(buf, r, r + 1, false)[1]
          if lt then
            local end_col = (r == f.erow) and f.ecol or #lt
            if end_col > 0 then
              vim.api.nvim_buf_set_extmark(buf, ns, r, 0, {
                end_row = r, end_col = end_col,
                conceal = "", strict = false,
              })
            end
          end
        end
      end
    end
  end

  if opts and opts.autogen then
    autogen_autocmd[buf] = vim.api.nvim_create_autocmd({"InsertLeave", "TextChanged"}, {
      buffer = buf,
      desc = "nabla.nvim: Regenerates virt_lines automatically when the user exists insert mode",
      callback = function()
        autogen_flag = true
        disable_virt()
        autogen_flag = false
        enable_virt()
      end
    })
  end
end

function disable_virt()
  local buf = vim.api.nvim_get_current_buf()
  virt_enabled[buf] = false

  if mult_virt_ns[buf] then
    vim.api.nvim_buf_clear_namespace(buf, mult_virt_ns[buf], 0, -1)
    mult_virt_ns[buf] = nil
  end
  local win = vim.api.nvim_get_current_win()
  if saved_conceallevel[win] then
    vim.wo[win].conceallevel = saved_conceallevel[win]
  end
  if saved_concealcursor[win] then
    vim.wo[win].concealcursor = saved_concealcursor[win]
  end
  if saved_wrap[win] ~= nil then
    vim.wo[win].wrap = saved_wrap[win]
  end
  if not autogen_flag and autogen_autocmd[buf] then
    vim.api.nvim_del_autocmd(autogen_autocmd[buf])
    autogen_autocmd[buf] = nil
  end
  if mode_autocmd[buf] then
    vim.api.nvim_del_autocmd(mode_autocmd[buf])
    mode_autocmd[buf] = nil
  end
end

function toggle_virt(opts)
  local buf = vim.api.nvim_get_current_buf()
  if virt_enabled[buf] then
    disable_virt()
  else
    enable_virt(opts)
  end
end

function is_virt_enabled(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  return virt_enabled[buf] == true
end



return {
	gen_drawing = gen_drawing,
	gen_drawing_typst = gen_drawing_typst,
	gen_drawing_latex_ts = gen_drawing_latex_ts,
	popup= popup,
	enable_virt = enable_virt,
	disable_virt = disable_virt,
	toggle_virt = toggle_virt,
	is_virt_enabled = is_virt_enabled,
}

