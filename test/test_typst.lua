-- Typst test runner for nabla.nvim
local fail = false

local info = debug.getinfo(1, "S")
local path
if info and info.source:sub(1, 1) == "@" then
  path = vim.fn.fnamemodify(info.source:sub(2), ":p")
end
path = vim.fn.fnamemodify(path, ":h:h")

-- Preload modules from local files
package.loaded['nabla.symbols'] = dofile(path .. '/lua/nabla/symbols.lua')
package.loaded['nabla.grid'] = dofile(path .. '/lua/nabla/grid.lua')
package.loaded['nabla.typst'] = dofile(path .. '/lua/nabla/typst.lua')
package.loaded['nabla.utils'] = dofile(path .. '/lua/nabla/utils.lua')
package.loaded['nabla.ascii'] = dofile(path .. '/lua/nabla/ascii.lua')
package.loaded['nabla.latex'] = dofile(path .. '/lua/nabla/latex.lua')
package.loaded['nabla'] = dofile(path .. '/lua/nabla.lua')

local nabla = require('nabla')

local test_path = path .. "/test/cases_typst"

local files = {}
local all_files = vim.fn.glob(test_path .. "/*")
for _, file in ipairs(vim.split(all_files, "\n")) do
  table.insert(files, file)
end

for _, file in ipairs(files) do
  local input = {}
  local output = {}
  local in_input = true
  for line in io.lines(file) do
    if in_input then
      if string.match(line, "^%-%-%-") then
        in_input = false
      else
        table.insert(input, line)
      end
    else
      table.insert(output, line)
    end
  end

  local expr = table.concat(input, " ")
  local ok, result = pcall(nabla.gen_drawing_typst, expr)

  local correct = true
  if ok and type(result) == "table" then
    if #result == #output then
      for i=1,#result do
        if result[i] ~= output[i] then
          correct = false
          break
        end
      end
    else
      correct = false
    end
  else
    result = "NO OUTPUT"
    correct = false
  end

  local name = vim.fn.fnamemodify(file, ":t")
  if correct then
    print(name .. " OK!")
  else
    print(name .. " FAIL!")
    print("Input: " .. vim.inspect(input))
    print("Expected: " .. vim.inspect(output))
    print("Result: " .. vim.inspect(result))
    fail = true
  end
end

if not fail then
  print("ALL TYPST TESTS PASSED")
end
