local symbols = require('nabla.symbols')
local grid = require('nabla.grid')

local style = symbols.style
local greek_etc = symbols.greek_etc
local special_nums = symbols.special_nums
local special_syms = symbols.special_syms
local sub_letters = symbols.sub_letters
local frac_set = symbols.frac_set
local sup_letters = symbols.sup_letters
local mathbb = symbols.mathbb
local mathcal = symbols.mathcal
local mathfrak = symbols.mathfrak
local plain_functions = symbols.plain_functions

local to_ascii

local function utf8len(str)
	return vim.str_utfindex(str)
end

local function is_sym_needing_spacing(sym)
	return not string.match(sym, "^%a")
		and not string.match(sym, "^%d")
		and not string.match(sym, "^%s+$")
		and sym ~= "/"
		and sym ~= special_syms["partial"]
		and sym ~= "["
		and sym ~= "]"
		and sym ~= "'"
		and sym ~= "|"
		and sym ~= "."
		and sym ~= ","
		and sym ~= special_syms["Vert"]
end

local function combine_brackets(res)
  local left_content, right_content = {}, {}
  if res.h > 1 then
    for y=1,res.h do
      if y == 1 then
        table.insert(left_content, style.matrix_upper_left)
        table.insert(right_content, style.matrix_upper_right)
      elseif y == res.h then
        table.insert(left_content, style.matrix_lower_left)
        table.insert(right_content, style.matrix_lower_right)
      else
        table.insert(left_content, style.matrix_vert_left)
        table.insert(right_content, style.matrix_vert_right)
      end
    end
  else
    left_content = { style.matrix_single_left }
    right_content = { style.matrix_single_right }
  end
  local leftbracket = grid:new(1, res.h, left_content)
  local rightbracket = grid:new(1, res.h, right_content)
  res = leftbracket:join_hori(res, true)
  res = res:join_hori(rightbracket, true)
  return res
end

local function stack_subsup(explist, i, g)
  i = i + 1
  while i <= #explist do
    local exp = explist[i]
    if exp.kind == "subexp" then
      i = i + 1
    	local my = g.my
    	local subgrid = to_ascii({explist[i]}, 1)
    	g = g:join_vert(subgrid)
    	g.my = my
      i = i + 1
    elseif exp.kind == "supexp" then
      i = i + 1
    	local my = g.my
    	local supgrid = to_ascii({explist[i]}, 1)
    	g = supgrid:join_vert(g)
    	g.my = my + supgrid.h
      i = i + 1
    else
      break
    end
  end
  return g, i - 1
end

local function grid_of_exps(explist)
  local cellsgrid, maxheight = {}, 0
  local i, rowgrid = 1, {}
  while i <= #explist do
  	local cell_list = { kind = "explist", exps = {} }
  	while i <= #explist do
  		if explist[i].kind == "symexp" and explist[i].sym == "&" then
  			local cellgrid = to_ascii({cell_list}, 1)
  			table.insert(rowgrid, cellgrid)
  			maxheight = math.max(maxheight, cellgrid.h)
  			i = i+1; break
  		elseif explist[i].kind == "funexp" and explist[i].sym == "\\" then
  			local cellgrid = to_ascii({cell_list}, 1)
  			table.insert(rowgrid, cellgrid)
  			maxheight = math.max(maxheight, cellgrid.h)
  			table.insert(cellsgrid, rowgrid)
  			rowgrid = {}
  			i = i+1; break
  		else
  			table.insert(cell_list.exps, explist[i])
  			i = i+1
  		end
  		if i > #explist then
  			local cellgrid = to_ascii({cell_list}, 1)
  			table.insert(rowgrid, cellgrid)
  			maxheight = math.max(maxheight, cellgrid.h)
  			table.insert(cellsgrid, rowgrid)
  		end
  	end
  end
  return cellsgrid, maxheight
end

local function combine_matrix_grid(cellsgrid, maxheight)
  local res
  local row_heights, baselines = {}, {}
  for i=1,#cellsgrid do
    local height_below, height_above, baseline = 0, 0, 0
    for j=1,#cellsgrid[i] do
      local cell = cellsgrid[i][j]
      height_below = math.max(cell.my, height_below)
      height_above = math.max(cell.h - cell.my - 1, height_above)
      baseline = math.max(baseline, cell.my)
    end
    row_heights[i] = height_below + height_above + 1
    baselines[i] = baseline
  end
  for i=1,#cellsgrid[1] do
    local col
    for j=1,#cellsgrid do
      local cell = cellsgrid[j][i]
      local sup = baselines[j] - cell.my
      local sdown = row_heights[j] - cell.h - sup
      if sup > 0 then cell = grid:new(cell.w, sup):join_vert(cell) end
      if sdown > 0 then cell = cell:join_vert(grid:new(cell.w, sdown)) end
      if i < #cellsgrid[1] then
        local spacer = grid:new(1, cell.h)
        spacer.my = cell.my
        cell = cell:join_hori(spacer)
      end
      col = col and col:join_vert(cell, true) or cell
    end
    res = res and res:join_hori(col, true) or col
  end
  return res
end

local function unpack_explist(exp)
  while exp.kind == "explist" do
    assert(#exp.exps == 1, "explist must be length 1")
    exp = exp.exps[1]
  end
  return exp
end

--- Try to build a Unicode subscript/superscript string from a list of exps.
--- Returns (string, type) on success, or nil if any exp can't be rendered inline.
local function expr_to_unicode(exps, letter_table)
  local str, t = "", nil
  if #exps == 1 and exps[1].kind == "numexp" or (exps[1].kind == "symexp" and string.match(exps[1].sym, "^%d+$")) then
    t = "num"
  elseif exps[1].kind == "symexp" and string.match(exps[1].sym, "^%a+$") then
    t = "var"
  else
    t = "sym"
  end
  for _, exp in ipairs(exps) do
    if exp.kind == "numexp" and math.floor(exp.num) == exp.num then
      local num = exp.num
      if num == 0 then
        str = str .. letter_table["0"]
      else
        if num < 0 then
          str = "₋" .. str
          num = math.abs(num)
        end
        local digits = ""
        while num ~= 0 do
          digits = letter_table[tostring(num%10)] .. digits
          num = math.floor(num / 10)
        end
        str = str .. digits
      end
    elseif exp.kind == "symexp" then
      if letter_table[exp.sym] and not exp.sub and not exp.sup then
        str = str .. letter_table[exp.sym]
      else
        return nil
      end
    else
      return nil
    end
  end
  return str, t
end

--- Try to render a frac sub/sup as a compact Unicode fraction (e.g. ½).
local function try_unicode_frac(exps)
  if #exps ~= 1 then return nil end
  local exp = exps[1]
  if exp.kind ~= "funexp" or exp.sym ~= "frac" then return nil end
  assert(#exp.args == 2, "frac must have 2 arguments")
  local numerator, denominator = exp.args[1].exps, exp.args[2].exps
  if #numerator ~= 1 or numerator[1].kind ~= "numexp" then return nil end
  if #denominator ~= 1 or denominator[1].kind ~= "numexp" then return nil end
  local A, B = numerator[1].num, denominator[1].num
  if frac_set[A] and frac_set[A][B] then
    return grid:new(1, 1, { frac_set[A][B] })
  end
  local num_str, den_str = "", ""
  if math.floor(A) == A then
    local s = tostring(A)
    for i=1,#s do num_str = num_str .. sup_letters[s:sub(i,i)] end
  end
  if math.floor(B) == B then
    local s = tostring(B)
    for i=1,#s do den_str = den_str .. sub_letters[s:sub(i,i)] end
  end
  if #num_str > 0 and #den_str > 0 then
    local frac_str = num_str .. "⁄" .. den_str
    return grid:new(utf8len(frac_str), 1, { frac_str })
  end
  return nil
end

local function put_subsup_aside(g, sub, sup)
  if not (sub and sup) then return g end
  -- sub and sup are exchanged to make the most compact expression
  local sub_str, sub_t = expr_to_unicode(sup.exps, sub_letters)
  local sup_str, sup_t = expr_to_unicode(sub.exps, sup_letters)
  if sub_str and sup_str then
    local sup_g = grid:new(utf8len(sub_str), 1, { sub_str }, sub_t)
    local sub_g = grid:new(utf8len(sup_str), 1, { sup_str }, sup_t)
    return g:join_sub_sup(sub_g, sup_g)
  end
  return g:join_sub_sup(to_ascii({sub}, 1), to_ascii({sup}, 1))
end

local function put_if_only_sub(g, sub, sup)
  if not (sub and not sup) then return g end
  local sub_str, sub_t = expr_to_unicode(sub.exps, sub_letters)
  if sub_str and #sub_str > 0 then
    return g:join_hori(grid:new(utf8len(sub_str), 1, { sub_str }, sub_t))
  end
  local subgrid = try_unicode_frac(sub.exps) or to_ascii({sub}, 1)
  return g:combine_sub(subgrid)
end

local function put_if_only_sup(g, sub, sup)
  if not (sup and not sub) then return g end
  local sup_str, sup_t = expr_to_unicode(sup.exps, sup_letters)
  if sup_str and #sup_str > 0 then
    return g:join_hori(grid:new(utf8len(sup_str), 1, { sup_str }, sup_t), true)
  end
  local supgrid = try_unicode_frac(sup.exps) or to_ascii({sup}, 1)
  return g:join_super(supgrid)
end


-- Lookup tables for table-driven dispatch
local op_symbols = {
	["int"]    = "∫",
	["iint"]   = "∬",
	["iiint"]  = "∭",
	["oint"]   = "∮",
	["oiint"]  = "∯",
	["oiiint"] = "∰",
	["sum"]    = "∑",
	["prod"]   = "∏",
}

local accent_chars = {
	["dddot"]  = "…",
	["ddot"]   = "‥",
	["dot"]    = ".",
	["hat"]    = "^",
	["tilde"]  = "~",
	["grave"]  = "`",
	["acute"]  = "´",
	["breve"]  = "˘",
	["caron"]  = "ˇ",
	["circle"] = "∘",
}

local passthrough_names = {
	["mathbf"] = true,
	["mathit"] = true,
	["mathtt"] = true,
	["boldsymbol"] = true,
	["upright"] = true,
	["sans"] = true,
	["scr"] = true,
	["mid"] = true,
}

local bracket_decorators = {
	["lfloor"] = { "⌊", "⌋", "bottom" },
	["lceil"]  = { "⌈", "⌉", "top" },
	["floor"]  = { "⌊", "⌋", "bottom" },
	["ceil"]   = { "⌈", "⌉", "top" },
	["round"]  = { "⌊", "⌉", "bottom" },
}

local over_decorators = {
	["overbracket"] = { "⎡", "⎤", "top" },
	["overparen"]   = { "⎛", "⎞", "top" },
	["overshell"]   = { "⎡", "⎤", "top" },
}

local under_decorators = {
	["underbracket"] = { "⎣", "⎦", "bottom" },
	["underparen"]   = { "⎝", "⎠", "bottom" },
	["undershell"]   = { "⎣", "⎦", "bottom" },
}

local font_commands = {
	["mathbb"]   = mathbb,
	["mathcal"]  = mathcal,
	["mathfrak"] = mathfrak,
}

local block_enclosures = {
	["matrix"]  = function(r) return r end,
	["align"]   = function(r) return r end,
	["aligned"] = function(r) return r end,
	["pmatrix"] = function(r) return r:enclose_paren() end,
	["bmatrix"] = function(r) return combine_brackets(r) end,
	["cases"]   = function(r) return r:enclose_bracket() end,
	["binom"]   = function(r) return r:enclose_paren() end,
	["vec"]     = function(r) return r:enclose_paren() end,
}

local overbrace_char = "⏞"
local underbrace_char = "⏟"
local cancel_char = "─"
--- Build the √ / root radical with bars and top bracket
local function make_radical(toroot)
  local left_content = {}
  for y=1,toroot.h do
    table.insert(left_content, y < toroot.h
      and (" " .. style.root_vert_bar)
      or (style.root_bottom .. style.root_vert_bar))
  end
  local left_root = grid:new(2, toroot.h, left_content, "sym")
  left_root.my = toroot.my
  local up_str = " " .. style.root_upper_left
  for _=1,toroot.w do up_str = up_str .. style.root_upper end
  up_str = up_str .. style.root_upper_right
  local top_root = grid:new(toroot.w+2, 1, { up_str }, "sym")
  local res = left_root:join_hori(toroot)
  res = top_root:join_vert(res)
  res.my = top_root.h + toroot.my
  return res
end

local function make_accent_grid(name, explist, exp_i)
  local belowgrid = to_ascii({explist[exp_i+1]}, 1)
  local accent = grid:new(1, 1, { accent_chars[name] })
  local g = accent:join_vert(belowgrid)
  g.my = belowgrid.my + 1
  return g, exp_i + 1
end

local function make_bar_decoration(bar_char, belowgrid)
  local bar = ""
  for _=1,belowgrid.w do bar = bar .. bar_char end
  return grid:new(belowgrid.w, 1, { bar })
end

local function make_bracket_enclosure(left_c, right_c, ingrid)
  local lb = grid:new(1, ingrid.h, left_c)
  local rb = grid:new(1, ingrid.h, right_c)
  return lb:join_hori(ingrid, true):join_hori(rb, true)
end

local function make_over_under_decor(decor_info, content_grid, is_under)
  local left_c, right_c, pos = decor_info[1], decor_info[2], decor_info[3]
  local w = content_grid.w
  local bracket_left, bracket_right = {}, {}
  for y=1,content_grid.h do
    local match = (pos == "top" and y == 1) or (pos == "bottom" and y == content_grid.h)
    table.insert(bracket_left, match and left_c or " ")
    table.insert(bracket_right, match and right_c or " ")
  end
  local lb = grid:new(1, content_grid.h, bracket_left)
  local rb = grid:new(1, content_grid.h, bracket_right)
  local spacer = grid:new(w, 1, { string.rep(" ", w) })
  local row = lb:join_hori(spacer, true):join_hori(rb, true)
  return is_under and content_grid:join_vert(row) or row:join_vert(content_grid)
end

local function make_font_grid(font_table, explist, exp_i)
  local sym = unpack_explist(explist[exp_i+1])
  exp_i = exp_i + 1
  if sym.kind == "symexp" or sym.kind == "numexp" then
    local s = tostring(sym.sym or sym.num)
    local cell = ""
    for i=1,#s do
      local mapped = font_table[s:sub(i,i)]
      assert(mapped, "font: " .. s:sub(i,i) .. " not found")
      cell = cell .. mapped
    end
    return grid:new(#s, 1, { cell }), exp_i
  elseif sym.kind == "funexp" then
    return to_ascii({explist[exp_i]}, 1), exp_i
  end
  error("font: unsupported kind " .. (sym.kind or "nil"))
end


function to_ascii(explist, exp_i)
  local gs = {}
  while exp_i <= #explist do
    local exp = explist[exp_i]
    local g

    if exp.kind == "numexp" then
    	g = grid:new(#tostring(exp.num), 1, { tostring(exp.num) }, "num")

    elseif exp.kind == "symexp" then
    	local sym = exp.sym
    	if is_sym_needing_spacing(sym) and not (exp_i == 1 and sym == "-") then
    		sym = " " .. sym .. " "
    	end
    	g = grid:new(utf8len(sym), 1, { sym }, "sym")

    elseif exp.kind == "explist" then
      g = to_ascii(exp.exps, 1)

    elseif exp.kind == "funexp" then
    	local name = exp.sym

    	if name == "frac" then
    		local leftgrid = to_ascii({explist[exp_i+1]}, 1)
    		local rightgrid = to_ascii({explist[exp_i+2]}, 1)
    		exp_i = exp_i + 2
    		local w = math.max(leftgrid.w, rightgrid.w)
    		local bar = string.rep(style.div_middle_bar, w)
    		local opgrid = grid:new(w, 1, { bar })
    		local c2 = leftgrid:join_vert(opgrid):join_vert(rightgrid)
    		c2.my = leftgrid.h
    		g = c2

    	elseif bracket_decorators[name] then
    	  local ingrid = to_ascii({explist[exp_i+1]}, 1)
    	  exp_i = exp_i + 1
    	  local info = bracket_decorators[name]
    	  local left_c, right_c = {}, {}
    	  local vert_l = ingrid.h > 1 and style.matrix_vert_left or " "
    	  local vert_r = ingrid.h > 1 and style.matrix_vert_right or " "
    	  for y=1,ingrid.h do
    	    local match = (info[3] == "bottom" and y == ingrid.h)
    	              or (info[3] == "top" and y == 1)
    	              or (info[3] == "all")
    	    table.insert(left_c, match and info[1] or vert_l)
    	    table.insert(right_c, match and info[2] or vert_r)
    	  end
    	  g = make_bracket_enclosure(left_c, right_c, ingrid)

    	elseif name == "Vert" then
    	  if exp_i + 1 <= #explist then
    	    local ingrid = to_ascii({explist[exp_i+1]}, 1)
    	    exp_i = exp_i + 1
    	    local bars = {}
    	    for _=1,ingrid.h do table.insert(bars, "‖") end
    	    g = make_bracket_enclosure(bars, bars, ingrid)
    	  else
    	    g = grid:new(1, 1, { "‖" }, "sym")
    	  end

    	elseif special_syms[name] or special_nums[name] or greek_etc[name] then
    		local sym = special_syms[name] or special_nums[name] or greek_etc[name]
    	  local t
    	  if special_syms[name] then
    	    t = "sym"
    	  	if is_sym_needing_spacing(sym) then
    	  		sym = " " .. sym .. " "
    	  	elseif #sym > 1 and string.match(sym, "^%a+$") then
    	  		local next_exp = explist[exp_i+1]
    	  		if not (next_exp and (next_exp.kind == "parexp" or next_exp.kind == "braexp")) then
    	  			sym = sym .. " "
    	  		end
    	  	end
    	  elseif special_nums[name] then
    	    t = "num"
    	  else
    	    t = "var"
    	  end
    		g = grid:new(utf8len(sym), 1, { sym }, t)

    	elseif name == "sqrt" or name == "root" then
    	  local degree_exp, radicand_exps
    	  if name == "root" then
    	    local arg1, arg2 = explist[exp_i+1], explist[exp_i+2]
    	    if arg2 and arg2.kind == "explist" then
    	      degree_exp = arg1
    	      radicand_exps = arg2.exps
    	      exp_i = exp_i + 2
    	    else
    	      radicand_exps = arg1.exps or {arg1}
    	      exp_i = exp_i + 1
    	    end
    	  else
    	    radicand_exps = {explist[exp_i+1]}
    	    exp_i = exp_i + 1
    	  end
    	  local toroot = to_ascii(radicand_exps, 1)
    	  g = make_radical(toroot)
    	  if degree_exp then
    	    local dg = to_ascii({degree_exp}, 1)
    	    local pad = {}
    	    for y=1,dg.h do table.insert(pad, dg.content[y]) end
    	    for _=1,g.h - dg.h do table.insert(pad, string.rep(" ", dg.w)) end
    	    local deg_col = grid:new(dg.w, g.h, pad)
    	    deg_col.my = g.my
    	    g = deg_col:join_hori(g)
    	  end

    	elseif op_symbols[name] then
    		g = grid:new(1, 1, { op_symbols[name] }, "sym")
    	  g, exp_i = stack_subsup(explist, exp_i, g)
    		if g then g = g:join_hori(grid:new(1, 1, { " " })) end

    	elseif name == "lim" then
    	  g = grid:new(3, 1, { "lim" }, "op")
    	  g, exp_i = stack_subsup(explist, exp_i, g)
    		if g then g = g:join_hori(grid:new(1, 1, { " " })) end

    	elseif accent_chars[name] then
    		g, exp_i = make_accent_grid(name, explist, exp_i)

    	elseif name == "bar" then
    	  local ingrid = to_ascii({explist[exp_i+1]}, 1)
    	  exp_i = exp_i + 1
    	  local bars = {}
    	  for _=1,ingrid.h do table.insert(bars, style.root_vert_bar) end
    	  g = make_bracket_enclosure(bars, bars, ingrid)

    	elseif font_commands[name] then
    	  g, exp_i = make_font_grid(font_commands[name], explist, exp_i)

    	elseif plain_functions[name] then
    		local next_exp = explist[exp_i+1]
    		if next_exp and (next_exp.kind == "parexp" or next_exp.kind == "braexp") then
    			g = grid:new(#name, 1, {name})
    		else
    			g = grid:new(#name + 1, 1, {name .. " "})
    		end

    	elseif passthrough_names[name] then
    		g = to_ascii({explist[exp_i+1]}, 1)
    		exp_i = exp_i + 1

    	elseif name == "overline" or name == "dash" then
    	  local belowgrid = to_ascii({explist[exp_i+1]}, 1)
    	  exp_i = exp_i + 1
    	  local ch = name == "overline" and style.div_low_bar or style.div_middle_bar
    	  g = make_bar_decoration(ch, belowgrid):join_vert(belowgrid)
    	  g.my = belowgrid.my + 1

    	elseif name == "vec" then
    	  local belowgrid = to_ascii({explist[exp_i+1]}, 1)
    	  exp_i = exp_i + 1
    	  local txt = string.rep(style.div_middle_bar, belowgrid.w - 1) .. style.vec_arrow
    	  g = grid:new(belowgrid.w, 1, {txt}):join_vert(belowgrid)
    	  g.my = belowgrid.my + 1

    	elseif name == "cancel" or name == "strike" then
    	  local ingrid = to_ascii({explist[exp_i+1]}, 1)
    	  exp_i = exp_i + 1
    	  local mid = ingrid.my + 1
    	  if mid >= 1 and mid <= ingrid.h then
    	    -- Append U+0335 (combining short stroke overlay) to each character
    	    ingrid.content[mid] = ingrid.content[mid]:gsub(".", "%1\204\181")
    	    -- Recalculate width (combining chars don't add display width)
    	    -- Width stays the same since combining chars have 0 display width
    	  end
    	  g = ingrid

    	elseif name == "underline" then
    	  local ingrid = to_ascii({explist[exp_i+1]}, 1)
    	  exp_i = exp_i + 1
    	  g = ingrid:join_vert(make_bar_decoration(style.div_low_bar, ingrid))

    	elseif over_decorators[name] then
    	  local belowgrid = to_ascii({explist[exp_i+1]}, 1)
    	  exp_i = exp_i + 1
    	  g = make_over_under_decor(over_decorators[name], belowgrid, false)
    	  g.my = belowgrid.my + 1

    	elseif under_decorators[name] then
    	  local abovegrid = to_ascii({explist[exp_i+1]}, 1)
    	  exp_i = exp_i + 1
    	  g = make_over_under_decor(under_decorators[name], abovegrid, true)

    	elseif name == "overbrace" or name == "underbrace" then
    	  local content = to_ascii({explist[exp_i+1]}, 1)
    	  exp_i = exp_i + 1
    	  local ch = name == "overbrace" and overbrace_char or underbrace_char
    	  local brace = grid:new(content.w, 1, { ch .. string.rep(" ", content.w - 1) })
    	  if name == "overbrace" then
    	    g = brace:join_vert(content)
    	    g.my = content.my + 1
    	  else
    	    g = content:join_vert(brace)
    	  end

      elseif name == "{" then
        local inside_bra = {}
        while exp_i+1 <= #explist do
          if explist[exp_i+1].kind == "funexp" and explist[exp_i+1].sym == "}" then break end
          table.insert(inside_bra, explist[exp_i+1])
          exp_i = exp_i + 1
        end
        assert(explist[exp_i+1] and explist[exp_i+1].kind == "funexp" and explist[exp_i+1].sym == "}", "No matching closing bracket")
      	g = to_ascii(inside_bra, 1):enclose_bracket()
      	exp_i = exp_i + 1

    	else
    		g = grid:new(utf8len("\\" .. name), 1, { "\\" .. name })
    	end

    elseif exp.kind == "parexp" then
    	g = to_ascii({exp.exp}, 1):enclose_paren()

    elseif exp.kind == "blockexp" then
      local sym = unpack_explist(exp.first)
      exp_i = exp_i + 1
      local name = sym.sym
      local enclosure = block_enclosures[name]
      if not enclosure then error("Unknown block expression " .. name) end
      local cellsgrid, maxheight = grid_of_exps(exp.content.exps)
      local res = combine_matrix_grid(cellsgrid, maxheight)
      res.my = math.floor(res.h/2)
      g = enclosure(res)

    elseif exp.kind == "supexp" or exp.kind == "subexp" then
      assert(#gs >= 1, "No expression preceding '^'")
      local sub, sup
      while exp_i <= #explist do
        if explist[exp_i].kind == "subexp" then
          sub = explist[exp_i+1]; exp_i = exp_i + 2
        elseif explist[exp_i].kind == "supexp" then
          sup = explist[exp_i+1]; exp_i = exp_i + 2
        else break end
      end
      exp_i = exp_i - 1

      local function ensure_explist(val)
        if val.kind == "explist" then return val end
        if val.kind == "funexp" and explist[exp_i+1] and explist[exp_i+1].kind == "explist" then
          exp_i = exp_i + 1
          return { kind = "explist", exps = { val, explist[exp_i] } }
        end
        return { kind = "explist", exps = { val } }
      end
      if sup then sup = ensure_explist(sup) end
      if sub then sub = ensure_explist(sub) end

      local last_g = gs[#gs]
      last_g = put_subsup_aside(last_g, sub, sup)
      last_g = put_if_only_sub(last_g, sub, sup)
      last_g = put_if_only_sup(last_g, sub, sup)
      gs[#gs] = last_g

    elseif exp.kind == "chosexp" then
      local leftgrid = to_ascii({exp.left}, 1)
      local rightgrid = to_ascii({exp.right}, 1)
    	local w = math.max(leftgrid.w, rightgrid.w)
    	local opgrid = grid:new(w, 1, { string.rep(" ", w) })
    	local c2 = leftgrid:join_vert(opgrid):join_vert(rightgrid)
    	c2.my = leftgrid.h
      g = c2:enclose_paren()

    elseif exp.kind == "braexp" then
    	g = combine_brackets(to_ascii({exp.exp}, 1))

    elseif exp.kind == "barexp" then
      local ingrid = to_ascii({exp.exp}, 1)
      local bars = {}
      for _=1,ingrid.h do table.insert(bars, "‖") end
      g = make_bracket_enclosure(bars, bars, ingrid)

    else
      assert(false, "Unrecognized token")
    end

    table.insert(gs, g)
    exp_i = exp_i + 1
  end

  local concat_g = grid:new()
  for _, g in ipairs(gs) do
    if g then concat_g = concat_g:join_hori(g) end
  end
	return concat_g
end


return {
  to_ascii = to_ascii,
}
