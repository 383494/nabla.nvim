local M = {}

local function get_text(node, buf)
  return vim.treesitter.get_node_text(node, buf)
end

local function get_cmd_name(cmd_node, buf)
  for child in cmd_node:iter_children() do
    if child:type() == "command_name" then
      return get_text(child, buf):gsub("^\\", "")
    end
  end
  return nil
end

local function get_curly_args(cmd_node)
  local args = {}
  for child in cmd_node:iter_children() do
    if child:type() == "curly_group" then
      table.insert(args, child)
    end
  end
  return args
end

local function get_bracket_args(cmd_node)
  local args = {}
  for child in cmd_node:iter_children() do
    if child:type() == "bracket_group" then
      table.insert(args, child)
    end
  end
  return args
end

-- Forward declarations
local walk_node
local walk_generic_command
local walk_text_node

--- Walk children of a curly_group, handling both named and unnamed nodes.
--- Skips the outer { and } delimiters but processes (, ), [, ], =, etc.
local function walk_curly_content(node, buf)
  local result = {}
  local children = {}
  for child in node:iter_children() do
    table.insert(children, child)
  end

  local i = 1
  while i <= #children do
    local child = children[i]
    local t = child:type()

    if t == "{" or t == "}" then
      i = i + 1
    elseif not child:named() then
      if t == "(" then
        local inner = {}
        local depth = 1
        i = i + 1
        while i <= #children and depth > 0 do
          local c = children[i]
          if not c:named() then
            if c:type() == "(" then depth = depth + 1
            elseif c:type() == ")" then
              depth = depth - 1
              if depth == 0 then
                i = i + 1
                break
              end
            end
          end
          local nodes = walk_node(c, buf)
          for _, n in ipairs(nodes) do
            table.insert(inner, n)
          end
          i = i + 1
        end
        table.insert(result, { kind = "parexp", exp = { kind = "explist", exps = inner } })
      elseif t == "[" then
        local inner = {}
        local depth = 1
        i = i + 1
        while i <= #children and depth > 0 do
          local c = children[i]
          if not c:named() then
            if c:type() == "[" then depth = depth + 1
            elseif c:type() == "]" then
              depth = depth - 1
              if depth == 0 then
                i = i + 1
                break
              end
            end
          end
          local nodes = walk_node(c, buf)
          for _, n in ipairs(nodes) do
            table.insert(inner, n)
          end
          i = i + 1
        end
        table.insert(result, { kind = "braexp", exp = { kind = "explist", exps = inner } })
      elseif t == "=" then
        table.insert(result, { kind = "symexp", sym = "=" })
        i = i + 1
      else
        i = i + 1
      end
    else
      local nodes = walk_node(child, buf)
      for _, n in ipairs(nodes) do
        table.insert(result, n)
      end
      i = i + 1
    end
  end
  return result
end

local function walk_word(node, buf)
  local text = get_text(node, buf)
  local result = {}

  local parts = {}
  local current = ""
  for i = 1, #text do
    local c = text:sub(i, i)
    if c == "'" then
      if current ~= "" then
        table.insert(parts, current)
        current = ""
      end
      table.insert(parts, "'")
    else
      current = current .. c
    end
  end
  if current ~= "" then
    table.insert(parts, current)
  end

  for _, part in ipairs(parts) do
    if part == "'" then
      -- Merge consecutive primes into one superscript
      if #result >= 2 and result[#result].kind == "symexp"
        and result[#result].sym:match("^'+$") and result[#result - 1].kind == "supexp" then
        result[#result] = { kind = "symexp", sym = result[#result].sym .. "'" }
      else
        table.insert(result, { kind = "supexp" })
        table.insert(result, { kind = "symexp", sym = "'" })
      end
    elseif part:match("^%d+%.?%d*$") then
      table.insert(result, { kind = "numexp", num = tonumber(part) })
    else
      table.insert(result, { kind = "symexp", sym = part })
    end
  end

  return result
end

--- Walk sup/sub content and return a single expression for to_ascii.
--- If content has multiple expressions, wrap in explist.
--- If content is from a curly_group with a single expression, still wrap in explist
--- to match the handwritten parser's {expr} → explist behavior.
local function walk_sup_sub_content(node, buf, skip_type)
  local has_curly = false
  local result = {}
  for child in node:iter_children() do
    if child:type() == skip_type then
      -- skip ^ or _
    elseif child:type() == "curly_group" then
      has_curly = true
      local content = walk_curly_content(child, buf)
      for _, n in ipairs(content) do
        table.insert(result, n)
      end
    else
      local nodes = walk_node(child, buf)
      for _, n in ipairs(nodes) do
        table.insert(result, n)
      end
    end
  end

  if has_curly or #result > 1 then
    return { kind = "explist", exps = result }
  elseif #result == 1 then
    return result[1]
  else
    return { kind = "explist", exps = {} }
  end
end

walk_text_node = function(node, buf)
  local result = {}
  local choose_ref = nil

  local children = {}
  for child in node:iter_children() do
    if child:named() then
      table.insert(children, child)
    end
  end

  local function add(n)
    if choose_ref then
      choose_ref.right = n
      choose_ref = nil
    else
      table.insert(result, n)
    end
  end

  local i = 1
  while i <= #children do
    local child = children[i]
    local ntype = child:type()

    if ntype == "word" then
      local word_nodes = walk_word(child, buf)
      for _, n in ipairs(word_nodes) do
        add(n)
      end
      i = i + 1
    elseif ntype == "superscript" then
      add({ kind = "supexp" })
      add(walk_sup_sub_content(child, buf, "^"))
      i = i + 1
    elseif ntype == "subscript" then
      add({ kind = "subexp" })
      add(walk_sup_sub_content(child, buf, "_"))
      i = i + 1
    elseif ntype == "operator" then
      local text = get_text(child, buf)
      if text == "/" and i + 1 <= #children and children[i + 1]:type() == "operator" and get_text(children[i + 1], buf) == "/" then
        add({ kind = "symexp", sym = "//" })
        i = i + 2
      else
        add({ kind = "symexp", sym = text })
        i = i + 1
      end
    elseif ntype == "generic_command" then
      local cmd_name = get_cmd_name(child, buf)
      if cmd_name == "choose" then
        assert(#result > 0, "\\choose with no preceding expression")
        local left = result[#result]
        table.remove(result)
        local chosexp = { kind = "chosexp", left = left, right = nil }
        table.insert(result, chosexp)
        choose_ref = chosexp
      else
        local nodes = walk_generic_command(child, buf)
        for _, n in ipairs(nodes) do
          add(n)
        end
      end
      i = i + 1
    elseif ntype == "letter" then
      add({ kind = "symexp", sym = get_text(child, buf) })
      i = i + 1
    elseif ntype == "number" then
      add({ kind = "numexp", num = tonumber(get_text(child, buf)) })
      i = i + 1
    else
      add({ kind = "symexp", sym = get_text(child, buf) })
      i = i + 1
    end
  end

  return result
end

walk_generic_command = function(node, buf)
  local cmd_name = get_cmd_name(node, buf)
  if not cmd_name then return {} end

  local args = get_curly_args(node)

  -- Two-arg commands
  if cmd_name == "frac" or cmd_name == "dfrac" or cmd_name == "cfrac" then
    local result = { { kind = "funexp", sym = "frac" } }
    if #args >= 1 then
      table.insert(result, { kind = "explist", exps = walk_curly_content(args[1], buf) })
    else
      table.insert(result, { kind = "explist", exps = {} })
    end
    if #args >= 2 then
      table.insert(result, { kind = "explist", exps = walk_curly_content(args[2], buf) })
    else
      table.insert(result, { kind = "explist", exps = {} })
    end
    return result

  -- One-arg commands (accents, decorations, fonts)
  elseif cmd_name == "sqrt" or cmd_name == "hat" or cmd_name == "tilde"
    or cmd_name == "dot" or cmd_name == "ddot" or cmd_name == "dddot"
    or cmd_name == "bar" or cmd_name == "vec"
    or cmd_name == "overline" or cmd_name == "underline"
    or cmd_name == "cancel" or cmd_name == "strike"
    or cmd_name == "mathbb" or cmd_name == "mathbf" or cmd_name == "mathcal" or cmd_name == "mathfrak"
    or cmd_name == "mathscr" or cmd_name == "mathsf" or cmd_name == "mathtt"
    or cmd_name == "overbrace" or cmd_name == "underbrace"
    or cmd_name == "binom" or cmd_name == "pmod"
    or cmd_name == "operatorname" or cmd_name == "mathrm"
    or cmd_name == "texttt" or cmd_name == "textit" or cmd_name == "textbf" then
    local result = { { kind = "funexp", sym = cmd_name } }
    if #args >= 1 then
      table.insert(result, { kind = "explist", exps = walk_curly_content(args[1], buf) })
    end
    return result

  -- \xrightarrow / \xleftarrow: optional [below] + mandatory {above}
  elseif cmd_name == "xrightarrow" or cmd_name == "xleftarrow" then
    local result = { { kind = "funexp", sym = cmd_name } }
    local bracket_args = get_bracket_args(node)
    if #bracket_args >= 1 then
      table.insert(result, { kind = "explist", exps = walk_curly_content(bracket_args[1], buf) })
    end
    if #args >= 1 then
      table.insert(result, { kind = "explist", exps = walk_curly_content(args[1], buf) })
    end
    return result


  -- \text{...} - extract raw text preserving whitespace
  elseif cmd_name == "text" then
    if #args >= 1 then
      local raw = get_text(args[1], buf)
      -- Strip outer { and }
      local inner = raw:gsub("^%{", ""):gsub("%}$", "")
      return { { kind = "symexp", sym = inner } }
    end
    return {}

  -- Spacing commands
  elseif cmd_name == "quad" then
    return { { kind = "symexp", sym = "       " } }
  elseif cmd_name == "qquad" then
    return { { kind = "symexp", sym = "        " } }
  elseif cmd_name == "," then
    return { { kind = "symexp", sym = " " } }
  elseif cmd_name == ";" then
    return { { kind = "symexp", sym = "     " } }
  elseif cmd_name == ":" then
    return { { kind = "symexp", sym = "    " } }
  elseif cmd_name == " " then
    return { { kind = "symexp", sym = "      " } }

  -- Bar/Vert pair delimiter (handled at formula level via barmatch)
  elseif cmd_name == "|" then
    return { { kind = "funexp", sym = "Vert" } }

  -- Line break (in matrices)
  elseif cmd_name == "\\" then
    return { { kind = "funexp", sym = "\\" } }

  -- Curly brace literals
  elseif cmd_name == "{" then
    return { { kind = "funexp", sym = "{" } }
  elseif cmd_name == "}" then
    return { { kind = "funexp", sym = "}" } }

  -- \choose handled in walk_text_node
  elseif cmd_name == "choose" then
    return { { kind = "funexp", sym = "choose" } }

  -- Default: emit as funexp (Greek letters, symbols, operators, etc.)
  else
    return { { kind = "funexp", sym = cmd_name } }
  end
end

local function walk_math_delimiter(node, buf)
  local open_char, close_char
  local content_children = {}

  for child in node:iter_children() do
    local t = child:type()
    if t == "\\left" or t == "\\right" then
      -- skip markers
    elseif t == "command_name" then
      -- command-based delimiters like \langle, \rangle
      local cmd_text = get_text(child, buf):gsub("^\\", "")
      if cmd_text == "langle" or cmd_text == "rangle" then
        if not open_char then
          open_char = cmd_text
        else
          close_char = cmd_text
        end
      else
        table.insert(content_children, child)
      end
    elseif not child:named() then
      if not open_char then
        open_char = t
      else
        close_char = t
      end
    elseif child:named() then
      table.insert(content_children, child)
    end
  end

  local inner_exps = {}
  for _, child in ipairs(content_children) do
    local nodes = walk_node(child, buf)
    for _, n in ipairs(nodes) do
      table.insert(inner_exps, n)
    end
  end

  local inner = { kind = "explist", exps = inner_exps }

  if open_char == "[" and close_char == "]" then
    return { kind = "braexp", exp = inner }
  elseif open_char == "langle" or close_char == "rangle" then
    return { kind = "angexp", exp = inner }
  else
    return { kind = "parexp", exp = inner }
  end
end

local function walk_environment(node, buf)
  local env_name
  local content_children = {}

  for child in node:iter_children() do
    local t = child:type()
    if t == "begin" then
      for gc in child:iter_children() do
        if gc:type() == "curly_group_text" then
          for cc in gc:iter_children() do
            if cc:named() then
              env_name = get_text(cc, buf)
              break
            end
          end
        end
      end
    elseif t ~= "end" then
      table.insert(content_children, child)
    end
  end

  -- Walk content, splitting at \\ for matrix rows
  local rows = { {} }

  for ci = 1, #content_children do
    local child = content_children[ci]
    local ntype = child:type()

    if ntype == "generic_command" then
      local cmd = get_cmd_name(child, buf)
      if cmd == "\\" then
        table.insert(rows, {})
      else
        local nodes = walk_node(child, buf)
        for _, n in ipairs(nodes) do
          table.insert(rows[#rows], n)
        end
      end
    elseif ntype == "delimiter" and get_text(child, buf) == "&" then
      table.insert(rows[#rows], { kind = "symexp", sym = "&" })
    elseif ntype == "=" then
      table.insert(rows[#rows], { kind = "symexp", sym = "=" })
    else
      local nodes = walk_node(child, buf)
      for _, n in ipairs(nodes) do
        table.insert(rows[#rows], n)
      end
    end
  end

  local content_exps = {}
  for ri, row in ipairs(rows) do
    for _, exp in ipairs(row) do
      table.insert(content_exps, exp)
    end
    if ri < #rows then
      table.insert(content_exps, { kind = "funexp", sym = "\\" })
    end
  end

  return {
    {
      kind = "blockexp",
      first = { kind = "explist", exps = { { kind = "symexp", sym = env_name or "?" } } },
      content = { kind = "explist", exps = content_exps },
    },
  }
end

walk_node = function(node, buf)
  local ntype = node:type()
  local text = get_text(node, buf)

  if ntype == "text" then
    return walk_text_node(node, buf)
  elseif ntype == "generic_command" then
    return walk_generic_command(node, buf)
  elseif ntype == "text_mode" then
    for child in node:iter_children() do
      if child:type() == "curly_group" then
        local raw = get_text(child, buf)
        local inner = raw:gsub("^%{", ""):gsub("%}$", "")
        return { { kind = "symexp", sym = inner } }
      end
    end
    return { { kind = "symexp", sym = text } }
  elseif ntype == "math_delimiter" then
    return { walk_math_delimiter(node, buf) }
  elseif ntype == "generic_environment" or ntype == "math_environment" then
    return walk_environment(node, buf)
  elseif ntype == "word" then
    return walk_word(node, buf)
  elseif ntype == "operator" then
    return { { kind = "symexp", sym = text } }
  elseif ntype == "letter" then
    return { { kind = "symexp", sym = text } }
  elseif ntype == "number" then
    return { { kind = "numexp", num = tonumber(text) } }
  elseif ntype == "curly_group" then
    return walk_curly_content(node, buf)
  elseif ntype == "delimiter" then
    return { { kind = "symexp", sym = text } }
  elseif ntype == "superscript" then
    return { { kind = "supexp" }, walk_sup_sub_content(node, buf, "^") }
  elseif ntype == "subscript" then
    return { { kind = "subexp" }, walk_sup_sub_content(node, buf, "_") }
  elseif ntype == "=" then
    return { { kind = "symexp", sym = "=" } }
  else
    if not node:named() then
      if text == "(" then
        return { { kind = "symexp", sym = "(" } }
      elseif text == ")" then
        return { { kind = "symexp", sym = ")" } }
      end
    end
    return { { kind = "symexp", sym = text } }
  end
end

--- Post-process result list: pair Vert markers into barexp
local function pair_bars(result)
  -- First, recursively process nested explists
  for i, exp in ipairs(result) do
    if exp.kind == "explist" and exp.exps then
      exp.exps = pair_bars(exp.exps)
    end
  end

  -- Then pair Vert markers at this level
  local paired = {}
  local barmatch
  for _, exp in ipairs(result) do
    if exp.kind == "funexp" and exp.sym == "Vert" then
      if barmatch then
        -- closing \|
        local first = barmatch
        local inner = {}
        for k = first, #paired do
          table.insert(inner, paired[k])
        end
        for k = #paired, first, -1 do
          table.remove(paired, k)
        end
        table.insert(paired, {
          kind = "barexp",
          exp = { kind = "explist", exps = inner },
        })
        barmatch = nil
      else
        -- opening \|
        barmatch = #paired + 1
      end
    else
      table.insert(paired, exp)
    end
  end

  -- Unmatched opening \|
  if barmatch then
    table.insert(paired, barmatch, { kind = "funexp", sym = "Vert" })
    barmatch = nil
  end

  return paired
end

function M.parse_math_node(math_node, buf)
  local ntype = math_node:type()
  local formula_node

  if ntype == "source_file" then
    for child in math_node:iter_children() do
      local ct = child:type()
      if ct == "inline_formula" or ct == "displayed_equation" then
        formula_node = child
        break
      end
    end
  elseif ntype == "inline_formula" or ntype == "displayed_equation" then
    formula_node = math_node
  else
    formula_node = math_node
  end

  if not formula_node then
    return { kind = "explist", exps = {}, lnum = 1 }
  end

  local result = {}
  local children = {}
  for child in formula_node:iter_children() do
    table.insert(children, child)
  end

  local i = 1
  while i <= #children do
    local child = children[i]
    local ct = child:type()

    if not child:named() then
      if ct == "$" then
        i = i + 1
      elseif ct == "(" then
        local inner = {}
        local depth = 1
        i = i + 1
        while i <= #children and depth > 0 do
          local c = children[i]
          if not c:named() then
            if c:type() == "(" then
              depth = depth + 1
            elseif c:type() == ")" then
              depth = depth - 1
              if depth == 0 then break end
            end
          end
          local nodes = walk_node(c, buf)
          for _, n in ipairs(nodes) do
            table.insert(inner, n)
          end
          i = i + 1
        end
        table.insert(result, { kind = "parexp", exp = { kind = "explist", exps = inner } })
        if i <= #children and not children[i]:named() and children[i]:type() == ")" then
          i = i + 1
        end
      elseif ct == ")" then
        i = i + 1
      elseif ct == "[" then
        local inner = {}
        local depth = 1
        i = i + 1
        while i <= #children and depth > 0 do
          local c = children[i]
          if not c:named() then
            if c:type() == "[" then
              depth = depth + 1
            elseif c:type() == "]" then
              depth = depth - 1
              if depth == 0 then break end
            end
          end
          local nodes = walk_node(c, buf)
          for _, n in ipairs(nodes) do
            table.insert(inner, n)
          end
          i = i + 1
        end
        table.insert(result, { kind = "braexp", exp = { kind = "explist", exps = inner } })
        if i <= #children and not children[i]:named() and children[i]:type() == "]" then
          i = i + 1
        end
      elseif ct == "]" then
        i = i + 1
      elseif ct == "=" then
        table.insert(result, { kind = "symexp", sym = "=" })
        i = i + 1
      elseif ct == "," then
        table.insert(result, { kind = "symexp", sym = "," })
        i = i + 1
      else
        i = i + 1
      end
    elseif ct == "text" then
      local text_nodes = walk_text_node(child, buf)
      for _, n in ipairs(text_nodes) do
        table.insert(result, n)
      end
      i = i + 1
      -- Check if the last result was \sqrt with no args, followed by [degree]{radicand}
      if #result >= 1 and result[#result].kind == "funexp" and result[#result].sym == "sqrt"
        and i <= #children and not children[i]:named() and children[i]:type() == "[" then
        table.remove(result) -- remove the bare funexp("sqrt")
        local degree_exps = {}
        i = i + 1 -- skip [
        while i <= #children do
          local c = children[i]
          if not c:named() and c:type() == "]" then
            i = i + 1 -- skip ]
            break
          end
          local nodes = walk_node(c, buf)
          for _, n in ipairs(nodes) do
            table.insert(degree_exps, n)
          end
          i = i + 1
        end
        if i <= #children and children[i]:type() == "curly_group" then
          local radicand_exps = walk_curly_content(children[i], buf)
          table.insert(result, { kind = "funexp", sym = "root" })
          table.insert(result, { kind = "explist", exps = degree_exps })
          table.insert(result, { kind = "explist", exps = radicand_exps })
          i = i + 1
        else
          table.insert(result, { kind = "funexp", sym = "sqrt" })
          table.insert(result, { kind = "explist", exps = degree_exps })
        end
      end
      -- Check if the last result was \xrightarrow/\xleftarrow with no args, followed by [below]{above}
      if #result >= 1 and result[#result].kind == "funexp"
        and (result[#result].sym == "xrightarrow" or result[#result].sym == "xleftarrow")
        and i <= #children and not children[i]:named() and children[i]:type() == "[" then
        local arrow_name = result[#result].sym
        table.remove(result) -- remove the bare funexp
        local below_exps = {}
        i = i + 1 -- skip [
        while i <= #children do
          local c = children[i]
          if not c:named() and c:type() == "]" then
            i = i + 1 -- skip ]
            break
          end
          local nodes = walk_node(c, buf)
          for _, n in ipairs(nodes) do
            table.insert(below_exps, n)
          end
          i = i + 1
        end
        if i <= #children and children[i]:type() == "curly_group" then
          local above_exps = walk_curly_content(children[i], buf)
          table.insert(result, { kind = "funexp", sym = arrow_name })
          table.insert(result, { kind = "explist", exps = below_exps })
          table.insert(result, { kind = "explist", exps = above_exps })
          i = i + 1
        else
          table.insert(result, { kind = "funexp", sym = arrow_name })
          table.insert(result, { kind = "explist", exps = below_exps })
        end
      end
    elseif ct == "generic_command" then
      local cmd_name = get_cmd_name(child, buf)
      local cmd_args = get_curly_args(child)

      -- Handle \sqrt[n]{x} where [n] and {x} are siblings (not children)
      if cmd_name == "sqrt" and #cmd_args == 0 and i + 1 <= #children then
        local next_child = children[i + 1]
        if not next_child:named() and next_child:type() == "[" then
          -- Consume [degree]
          local degree_exps = {}
          i = i + 1 -- skip \sqrt
          i = i + 1 -- skip [
          while i <= #children do
            local c = children[i]
            if not c:named() and c:type() == "]" then
              i = i + 1 -- skip ]
              break
            end
            local nodes = walk_node(c, buf)
            for _, n in ipairs(nodes) do
              table.insert(degree_exps, n)
            end
            i = i + 1
          end
          -- Consume {radicand}
          if i <= #children and children[i]:type() == "curly_group" then
            local radicand_exps = walk_curly_content(children[i], buf)
            table.insert(result, { kind = "funexp", sym = "root" })
            table.insert(result, { kind = "explist", exps = degree_exps })
            table.insert(result, { kind = "explist", exps = radicand_exps })
            i = i + 1
          else
            -- No curly_group after [degree], just emit sqrt with degree as arg
            table.insert(result, { kind = "funexp", sym = "sqrt" })
            table.insert(result, { kind = "explist", exps = degree_exps })
          end
        else
          -- \sqrt{x} (args as children) or \sqrt with no args
          local nodes = walk_generic_command(child, buf)
          for _, n in ipairs(nodes) do
            table.insert(result, n)
          end
          i = i + 1
        end
      elseif (cmd_name == "xrightarrow" or cmd_name == "xleftarrow")
        and i + 1 <= #children and not children[i + 1]:named() and children[i + 1]:type() == "[" then
        -- Consume optional [below]
        local below_exps = {}
        i = i + 1 -- skip command
        i = i + 1 -- skip [
        while i <= #children do
          local c = children[i]
          if not c:named() and c:type() == "]" then
            i = i + 1 -- skip ]
            break
          end
          local nodes = walk_node(c, buf)
          for _, n in ipairs(nodes) do
            table.insert(below_exps, n)
          end
          i = i + 1
        end
        -- Consume mandatory {above}
        if i <= #children and children[i]:type() == "curly_group" then
          local above_exps = walk_curly_content(children[i], buf)
          table.insert(result, { kind = "funexp", sym = cmd_name })
          table.insert(result, { kind = "explist", exps = below_exps })
          table.insert(result, { kind = "explist", exps = above_exps })
          i = i + 1
        else
          -- No curly_group after [below], just emit with below only
          table.insert(result, { kind = "funexp", sym = cmd_name })
          table.insert(result, { kind = "explist", exps = below_exps })
        end
      else
        local nodes = walk_generic_command(child, buf)
        for _, n in ipairs(nodes) do
          table.insert(result, n)
        end
        i = i + 1
      end
    elseif ct == "text_mode" then
      for cc in child:iter_children() do
        if cc:type() == "curly_group" then
          local raw = get_text(cc, buf)
          local inner = raw:gsub("^%{", ""):gsub("%}$", "")
          table.insert(result, { kind = "symexp", sym = inner })
        end
      end
      i = i + 1
    elseif ct == "math_delimiter" then
      table.insert(result, walk_math_delimiter(child, buf))
      i = i + 1
    elseif ct == "generic_environment" or ct == "math_environment" then
      local env_nodes = walk_environment(child, buf)
      for _, n in ipairs(env_nodes) do
        table.insert(result, n)
      end
      i = i + 1
    elseif ct == "curly_group" then
      local content = walk_curly_content(child, buf)
      for _, n in ipairs(content) do
        table.insert(result, n)
      end
      i = i + 1
    elseif ct == "superscript" then
      table.insert(result, { kind = "supexp" })
      table.insert(result, walk_sup_sub_content(child, buf, "^"))
      i = i + 1
    elseif ct == "subscript" then
      table.insert(result, { kind = "subexp" })
      table.insert(result, walk_sup_sub_content(child, buf, "_"))
      i = i + 1
    else
      table.insert(result, { kind = "symexp", sym = get_text(child, buf) })
      i = i + 1
    end
  end

  -- Post-process: pair \| delimiters
  result = pair_bars(result)

  if #result == 0 then
    return { kind = "explist", exps = {}, lnum = 1 }
  end

  return { kind = "explist", exps = result, lnum = 1 }
end

return M
