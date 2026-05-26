-- End-to-end: open a real markdown buffer, attach, press K (via
-- vim.lsp.buf.hover), wait for the float, verify <C-k> binding exists on the
-- float buffer and that invoking state.step rewrites its lines.

local function fail(msg) io.stderr:write('FAIL: ' .. msg .. '\n'); os.exit(1) end

-- Use a synthetic file on disk so the buftype/name guards pass and we don't
-- depend on the contents of test/sample.md (which users may edit).
local tmp = vim.fn.tempname() .. '.md'
local f = io.open(tmp, 'w'); f:write('中国人民共和国\n'); f:close()
vim.cmd('edit ' .. vim.fn.fnameescape(tmp))
local parent = vim.api.nvim_get_current_buf()

-- Pump the event loop until a predicate holds, or timeout.
local function wait_for(predicate, timeout_ms)
  local deadline = vim.uv.now() + timeout_ms
  while vim.uv.now() < deadline do
    if predicate() then return true end
    vim.wait(20, function() return false end)
  end
  return false
end

-- Wait for the deferred LSP attach.
if not wait_for(function()
  return #vim.lsp.get_clients({ bufnr = parent, name = 'bookchoy' }) > 0
end, 1000) then
  fail('bookchoy LSP never attached')
end

-- Position cursor on 中 (line 1, col 0)
vim.api.nvim_win_set_cursor(0, { 1, 0 })

-- Trigger LSP hover. In headless this runs the in-process server synchronously
-- but the float-open + scheduled keymap attach happen on later ticks.
vim.lsp.buf.hover()

if not wait_for(function()
  local w = vim.b[parent].lsp_floating_preview
  return w and vim.api.nvim_win_is_valid(w)
end, 2000) then
  fail('hover float never opened')
end
local float_win = vim.b[parent].lsp_floating_preview
local float_buf = vim.api.nvim_win_get_buf(float_win)
io.stdout:write('ok hover float opened (win=' .. float_win .. ' buf=' .. float_buf .. ')\n')

-- Wait for the scheduled keymap attachment to run
if not wait_for(function()
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(float_buf, 'n')) do
    if m.lhs == '<C-K>' or m.lhs == '<C-k>' then return true end
  end
  return false
end, 1000) then
  fail('<C-k> never installed on float buffer')
end
io.stdout:write('ok <C-k> installed on float buffer\n')

-- Snapshot float content, invoke cycle, verify content changed
local before = table.concat(vim.api.nvim_buf_get_lines(float_buf, 0, -1, false), '\n')
require('bookchoy.state').step(parent, 1)
local after = table.concat(vim.api.nvim_buf_get_lines(float_buf, 0, -1, false), '\n')
if before == after then fail('float content did not change after step(1)') end
if not after:find('2/', 1, true) then
  fail('expected "2/N" position marker after cycling, got: ' .. after:sub(1, 100))
end
io.stdout:write('ok float rewritten in place to candidate 2\n')

-- And step back
require('bookchoy.state').step(parent, -1)
local back = table.concat(vim.api.nvim_buf_get_lines(float_buf, 0, -1, false), '\n')
if back ~= before then fail('step(-1) did not return to original content') end
io.stdout:write('ok step(-1) returns to candidate 1\n')

-- Parent-buffer mappings also installed while float is visible
local function buf_has_map(buf, lhs)
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
    if (m.lhs == lhs or m.lhs:lower() == lhs:lower()) and (m.desc or ''):find('bookchoy', 1, true) then
      return true
    end
  end
  return false
end

if not buf_has_map(parent, '<C-k>') then fail('parent buffer missing <C-k> while float open') end
if not buf_has_map(parent, '<C-j>') then fail('parent buffer missing <C-j> while float open') end
io.stdout:write('ok parent buffer has <C-k>/<C-j> while float open\n')

-- Close the float and verify cleanup
vim.api.nvim_win_close(float_win, true)
vim.wait(100, function() return false end)
if buf_has_map(parent, '<C-k>') then fail('parent <C-k> not cleaned up after close') end
if buf_has_map(parent, '<C-j>') then fail('parent <C-j> not cleaned up after close') end
io.stdout:write('ok parent buffer mappings removed after float closes\n')

-- Sanity: BookchoyWordRef highlight group is defined (default link).
local hl = vim.api.nvim_get_hl(0, { name = 'BookchoyWordRef' })
if not hl or vim.tbl_isempty(hl) then fail('BookchoyWordRef highlight not defined') end
io.stdout:write('ok BookchoyWordRef highlight registered\n')

io.stdout:write('PASS\n')
