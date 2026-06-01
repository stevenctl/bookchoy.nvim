-- Regression: a word split across a hard linebreak inside the same paragraph
-- must stay continuous for the mapper, while a blank line (`\n\n`) is a real
-- paragraph break that does NOT join.

local function fail(msg) io.stderr:write('FAIL: ' .. msg .. '\n'); os.exit(1) end

local bufnr = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(bufnr, '/tmp/bookchoy-paragraph-' .. vim.fn.getpid() .. '.md')
-- 工作 is split: 工 ends line 1, 作 begins line 2 (hard wrap, same paragraph).
-- A blank line then separates a second paragraph beginning with 作.
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
  '他来真的太空站工',
  '作。大家都觉得很好。',
  '',
  '作业很难。',
})
vim.api.nvim_set_option_value('filetype', 'markdown', { buf = bufnr })
vim.api.nvim_set_option_value('buftype', 'nofile', { buf = bufnr })

local cd = require('bookchoy')
require('bookchoy.db').ensure_open(cd.opts, function()
  local server = require('bookchoy.server')
  local state = require('bookchoy.state')

  -- Cursor on 工 (last char of line 0, 0-indexed col 7) — 作 is on the next
  -- hard-wrapped line; lookahead across the break should surface 工作.
  state.clear(bufnr)
  local r1 = server._handle_hover({
    textDocument = { uri = vim.uri_from_bufnr(bufnr) },
    position = { line = 0, character = 7 },
  }, cd.opts)
  if not r1 then fail('no result on 工 (end of wrapped line)') end
  if not r1.contents.value:find('工作', 1, true) then
    fail('expected 工作 across the hard linebreak, got: ' .. r1.contents.value:sub(1, 60))
  end
  io.stdout:write('ok 工作 surfaced across a hard linebreak within the paragraph\n')

  -- Cursor on 作 (first char of line 1) — lookback into the previous wrapped
  -- line should also surface 工作.
  state.clear(bufnr)
  local r2 = server._handle_hover({
    textDocument = { uri = vim.uri_from_bufnr(bufnr) },
    position = { line = 1, character = 0 },
  }, cd.opts)
  if not r2 then fail('no result on 作 (start of wrapped line)') end
  if not r2.contents.value:find('工作', 1, true) then
    fail('expected 工作 via lookback across the linebreak, got: ' .. r2.contents.value:sub(1, 60))
  end
  io.stdout:write('ok 工作 surfaced via lookback across a hard linebreak\n')

  -- Cursor on 作 in the SECOND paragraph (line 3, after a blank line). The
  -- blank line is a real break, so 工 from the first paragraph must NOT join;
  -- 作业 (the actual word here) should win, not 工作.
  state.clear(bufnr)
  local r3 = server._handle_hover({
    textDocument = { uri = vim.uri_from_bufnr(bufnr) },
    position = { line = 3, character = 0 },
  }, cd.opts)
  if not r3 then fail('no result on 作 (second paragraph)') end
  if r3.contents.value:find('工作', 1, true) then
    fail('blank line should bound the paragraph; 工作 must not cross it: ' .. r3.contents.value:sub(1, 60))
  end
  io.stdout:write('ok blank line bounded the paragraph (工作 did not cross \\n\\n)\n')

  io.stdout:write('PASS\n')
end)
