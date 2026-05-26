-- Renders hover at a few cursor positions and prints the markdown. Useful for
-- eyeballing what the floating window will actually look like.
--
--   nvim --headless -u test/minimal_init.lua -c 'luafile test/render_smoke.lua' +qa

local bufnr = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(bufnr, '/tmp/bookchoy-render-' .. vim.fn.getpid() .. '.md')
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '中国人民共和国' })
vim.api.nvim_set_option_value('filetype', 'markdown', { buf = bufnr })
vim.api.nvim_set_option_value('buftype', 'nofile', { buf = bufnr })

local cd = require('bookchoy')
require('bookchoy.db').ensure_open(cd.opts, function()

local function show(label, char_col)
  local params = {
    textDocument = { uri = vim.uri_from_bufnr(bufnr) },
    position = { line = 0, character = char_col },
  }
  -- reset state so each call is fresh
  require('bookchoy.state').clear(bufnr)
  local result = require('bookchoy.server')._handle_hover(params, cd.opts)
  io.stdout:write('\n=== ' .. label .. ' ===\n')
  if result then io.stdout:write(result.contents.value .. '\n') else io.stdout:write('<no result>\n') end
end

show('cursor on 中 (col 0)', 0)
show('cursor on 国 (col 1)', 1)
show('cursor on 人 (col 2)', 2)

end)
