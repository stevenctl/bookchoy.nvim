-- Regression: cursor on the SECOND char of a 2-char word should still surface
-- the full word first (lookback should beat shorter starts-at-cursor matches).

local function fail(msg) io.stderr:write('FAIL: ' .. msg .. '\n'); os.exit(1) end

local bufnr = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(bufnr, '/tmp/bookchoy-lookback-' .. vim.fn.getpid() .. '.md')
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '我喜欢中国菜' })
vim.api.nvim_set_option_value('filetype', 'markdown', { buf = bufnr })
vim.api.nvim_set_option_value('buftype', 'nofile', { buf = bufnr })

local cd = require('bookchoy')
require('bookchoy.db').ensure_open(cd.opts, function()

-- cursor on 欢 (3rd char, 0-indexed col 2)
local params = {
  textDocument = { uri = vim.uri_from_bufnr(bufnr) },
  position = { line = 0, character = 2 },
}
require('bookchoy.state').clear(bufnr)
local result = require('bookchoy.server')._handle_hover(params, cd.opts)
if not result then fail('no result on 欢') end

local md = result.contents.value
io.stdout:write(md .. '\n')

if not md:find('喜欢', 1, true) then
  fail('expected 喜欢 in the first candidate (lookback), got: ' .. md:sub(1, 60))
end
io.stdout:write('ok lookback surfaced 喜欢 first when cursor is on 欢\n')
io.stdout:write('PASS\n')

end)
