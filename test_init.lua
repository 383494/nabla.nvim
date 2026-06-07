-- ~/src/nabla/test_init.lua
-- Load user's normal config first
dofile(os.getenv("HOME") .. "/.config/nvim/init.lua")

-- Evict cached nabla modules so require picks up local code
for name, _ in pairs(package.loaded) do
  if name:match("^nabla") then
    package.loaded[name] = nil
  end
end

-- Put local nabla at the front of the search path
local nabla_lua = vim.fn.expand("~/src/nabla/lua")
package.path = nabla_lua .. "/?.lua;" .. nabla_lua .. "/?/init.lua;" .. package.path
