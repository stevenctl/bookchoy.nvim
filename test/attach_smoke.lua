-- Verifies the FileType autocmd actually starts an LSP client on markdown buffers.

local function fail(msg) io.stderr:write('FAIL: ' .. msg .. '\n'); os.exit(1) end

local sample = debug.getinfo(1, 'S').source:sub(2):gsub('attach_smoke%.lua$', 'sample.md')
vim.cmd('edit ' .. vim.fn.fnameescape(sample))
local bufnr = vim.api.nvim_get_current_buf()

-- Attach is deferred via vim.schedule so it doesn't race with snacks/telescope
-- preview-buffer teardown. Wait up to 1s for the client to appear.
local deadline = vim.uv.now() + 1000
while vim.uv.now() < deadline do
  if #vim.lsp.get_clients({ bufnr = bufnr, name = 'bookchoy' }) > 0 then break end
  vim.wait(20, function() return false end)
end
local clients = vim.lsp.get_clients({ bufnr = bufnr, name = 'bookchoy' })
if #clients == 0 then fail('no bookchoy LSP attached to markdown buffer') end
io.stdout:write('ok client attached: id=' .. clients[1].id .. '\n')

-- Verify hoverProvider capability advertised
local caps = clients[1].server_capabilities
if not caps or not caps.hoverProvider then fail('hoverProvider capability missing') end
io.stdout:write('ok hoverProvider advertised\n')

-- We deliberately do NOT add our own K mapping in the parent buffer: Neovim
-- 0.11 installs a default `K -> vim.lsp.buf.hover()` when an LSP advertises
-- hoverProvider. Verify the K we see (if any) is the default, not ours.
local maps = vim.api.nvim_buf_get_keymap(bufnr, 'n')
for _, m in ipairs(maps) do
  if m.lhs == 'K' and (m.desc or ''):find('bookchoy', 1, true) then
    fail('unexpected bookchoy K mapping in parent buffer: ' .. (m.desc or ''))
  end
end
io.stdout:write('ok no bookchoy K mapping shadowing the default\n')

io.stdout:write('PASS\n')
