-- Headless smoke test for the hover handler.
--
-- Run from the plugin root (after test/minimal_init.lua has populated .test-data):
--   nvim --headless -u test/minimal_init.lua -c 'luafile test/hover_smoke.lua' +qa
--
-- Exits with non-zero status on failure.

local function fail(msg)
  io.stderr:write('FAIL: ' .. msg .. '\n')
  os.exit(1)
end

local function ok(msg)
  io.stdout:write('ok ' .. msg .. '\n')
end

-- Scratch buffer (unlisted, no swap file) with a unique name so uri round-trips
local bufnr = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(bufnr, '/tmp/bookchoy-smoke-' .. vim.fn.getpid() .. '.md')
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '中国人民共和国' })
vim.api.nvim_set_option_value('filetype', 'markdown', { buf = bufnr })
vim.api.nvim_set_option_value('buftype', 'nofile', { buf = bufnr })

local cd = require('bookchoy')
require('bookchoy.db').ensure_open(cd.opts, function(ok_db, err)
  if not ok_db then fail('db open: ' .. tostring(err)); return end

  local params = {
    textDocument = { uri = vim.uri_from_bufnr(bufnr) },
    position = { line = 0, character = 0 },
  }

  local result = require('bookchoy.server')._handle_hover(params, cd.opts)
  if not result then fail('no hover result for 中'); return end
  if not result.contents or not result.contents.value then fail('malformed result'); return end
  ok('hover returned markdown')

  local md = result.contents.value
  if not md:find('中', 1, true) then fail('markdown missing 中: ' .. md); return end
  ok('contains 中')

  -- Verify state was populated for in-float cycling
  local state = require('bookchoy.state').get(bufnr)
  if not state or #state.candidates < 2 then
    fail('expected state with >=2 candidates, got ' .. (state and #state.candidates or 0))
  end
  ok('state populated with ' .. #state.candidates .. ' candidates')

  -- Simulate <C-k> cycle: state.step advances; without a float open, it'd open
  -- one, but since we don't have a window in headless we just check the state.
  require('bookchoy.state').advance(bufnr, 1)
  local advanced = require('bookchoy.state').get(bufnr)
  if advanced.index ~= 2 then fail('advance did not move index to 2 (got ' .. advanced.index .. ')') end
  ok('advance moves index forward')

  io.stdout:write('PASS\n')
end)
