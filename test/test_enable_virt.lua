-- Test runner for enable_virt mode
-- Tests that formula rendering produces correct conceal extmarks
local fail = false

local info = debug.getinfo(1, "S")
local path
if info and info.source:sub(1, 1) == "@" then
  path = vim.fn.fnamemodify(info.source:sub(2), ":p")
end
path = vim.fn.fnamemodify(path, ":h:h")

local conn = vim.fn.jobstart({vim.v.progpath, '--embed', '--headless'}, {rpc = true})

-- Load nabla in the embedded instance
vim.fn.rpcrequest(conn, "nvim_exec_lua", [[
  local path = ...
  package.path = path .. "/lua/?.lua;" .. path .. "/lua/?/init.lua;" .. package.path
  for name, _ in pairs(package.loaded) do
    if name:match("^nabla") then package.loaded[name] = nil end
  end
  -- Force-load local nabla (bypasses lazy.nvim loader)
  package.loaded["nabla"] = loadfile(path .. "/lua/nabla.lua")()
]], { path })

local test_path = path .. "/test/cases_enable_virt"

local files = {}
local all_files = vim.fn.glob(test_path .. "/*")
for _, file in ipairs(vim.split(all_files, "\n")) do
  if file ~= "" then table.insert(files, file) end
end

if #files == 0 then
  print("NO TEST FILES FOUND in " .. test_path)
  vim.fn.jobstop(conn)
  os.exit(1)
end
for _, file in ipairs(files) do
  local input = {}
  local output = {}
  local in_input = true
  local win_width = 80
  local ft = "tex"
  for line in io.lines(file) do
    if in_input then
      if string.match(line, "^%-%-%-") then
        in_input = false
      elseif string.match(line, "^# width:") then
        win_width = tonumber(string.match(line, "^# width:%s*(%d+)")) or 80
      elseif string.match(line, "^# ft:") then
        ft = string.match(line, "^# ft:%s*(%S+)") or "tex"
      else
        table.insert(input, line)
      end
    else
      table.insert(output, line)
    end
  end

  local name = vim.fn.fnamemodify(file, ":t")

  -- Run enable_virt in embedded nvim and collect extmarks
  local ok, result = pcall(vim.fn.rpcrequest, conn, "nvim_exec_lua", [[
    local formula_lines, win_width, ft = ...

    -- Create a fresh buffer
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, formula_lines)
    vim.bo[buf].filetype = ft

    -- Open in a split so we have a real window
    vim.cmd('split')
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_width(win, win_width)
    vim.api.nvim_win_set_buf(win, buf)
    vim.api.nvim_set_current_win(win)

    -- Give treesitter a moment to parse
    vim.cmd('doautocmd FileType')

    local ok, err = pcall(require("nabla").enable_virt)
    if not ok then
      vim.api.nvim_win_close(win, true)
      vim.api.nvim_buf_delete(buf, {force=true})
      return { error = tostring(err) }
    end

    -- Read extmarks
    local ns = vim.api.nvim_create_namespace("nabla.nvim")
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {details=true})

    -- Collect conceal marks
    local conceals = {}
    for _, m in ipairs(marks) do
      local d = m[4]
      if d.conceal ~= nil then
        table.insert(conceals, {m[3], d.end_col, d.conceal})
      end
    end

    -- Collect virt_lines content
    local vlines = {}
    for _, m in ipairs(marks) do
      if m[4].virt_lines then
        for _, vl in ipairs(m[4].virt_lines) do
          local text = ""
          for _, chunk in ipairs(vl) do text = text .. chunk[1] end
          table.insert(vlines, vim.fn.substitute(text, '\\s\\+$', '', ''))
        end
      end
    end
    -- Collect virt_text content for wide formulas (stored in global)
    local wide_vt = {}
    local nabla_wide_vt = _G._nabla_wide_vt_by_id or {}
    for _, m in ipairs(marks) do
      local mid = m[1]
      if nabla_wide_vt[mid] then
        local text = ""
        for _, chunk in ipairs(nabla_wide_vt[mid]) do text = text .. chunk[1] end
        table.insert(wide_vt, vim.fn.substitute(text, '\\s\\+$', '', ''))
      end
    end

    -- Compute the visible line from conceal marks:
    -- Sort by range size descending so smaller marks overwrite
    table.sort(conceals, function(a, b) return (a[2]-a[1]) > (b[2]-b[1]) end)

    local line_text = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
    local chars = {}
    for i = 1, #line_text do chars[i] = line_text:sub(i, i) end

    for _, c in ipairs(conceals) do
      local sc, ec, cv = c[1], c[2], c[3]
      if cv == "" then
        for i = sc + 1, ec do chars[i] = nil end
      else
        chars[sc + 1] = cv
        for i = sc + 2, ec do chars[i] = nil end
      end
    end

    local visible = ""
    for i = 1, #line_text do
      if chars[i] then visible = visible .. chars[i] end
    end
    visible = vim.fn.substitute(visible, '\\s\\+$', '', '')

    require("nabla").disable_virt()
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(buf, {force=true})

    return { visible = visible, vlines = vlines, wide_vt = wide_vt, error = nil }
  ]], { input, win_width, ft })

  if type(result) ~= "table" or result.error then
    print(name .. " ERROR: " .. tostring(result and result.error or result))
    fail = true
    goto continue
  end

  -- Compare expected output
  -- Supports: visible line, virt_lines (lines after visible), # virt_text: directive
  local expected_visible = nil
  local expected_vlines = {}
  local expected_virt_text = nil
  for _, line in ipairs(output) do
    local vt = string.match(line, "^# virt_text:%s*(.+)$")
    if vt then
      expected_virt_text = vim.fn.substitute(vt, '\\s\\+$', '', '')
    elseif expected_visible == nil then
      expected_visible = vim.fn.substitute(line, '\\s\\+$', '', '')
    else
      table.insert(expected_vlines, vim.fn.substitute(line, '\\s\\+$', '', ''))
    end
  end
  if expected_visible == nil then expected_visible = "" end
  local ok_result = true
  local msgs = {}

  if result.visible ~= expected_visible then
    ok_result = false
    table.insert(msgs, "visible: expected " .. vim.inspect(expected_visible) .. " got " .. vim.inspect(result.visible))
  end

  if #expected_vlines > 0 then
    if #result.vlines ~= #expected_vlines then
      ok_result = false
      table.insert(msgs, "virt_lines count: expected " .. #expected_vlines .. " got " .. #result.vlines)
    else
      for i = 1, #expected_vlines do
        if result.vlines[i] ~= expected_vlines[i] then
          ok_result = false
          table.insert(msgs, "vline " .. i .. ": expected " .. vim.inspect(expected_vlines[i]) .. " got " .. vim.inspect(result.vlines[i]))
        end
      end
    end
  end

  if expected_virt_text then
    local actual_vt = table.concat(result.wide_vt or {}, " ")
    if actual_vt ~= expected_virt_text then
      ok_result = false
      table.insert(msgs, "virt_text: expected " .. vim.inspect(expected_virt_text) .. " got " .. vim.inspect(actual_vt))
    end
  end

  if ok_result then
    print(name .. " OK!")
  else
    print(name .. " FAIL!")
    for _, msg in ipairs(msgs) do print("  " .. msg) end
    fail = true
  end
  ::continue::
end

vim.fn.jobstop(conn)

if not fail then
  print("ALL ENABLE_VIRT TESTS PASSED")
end
