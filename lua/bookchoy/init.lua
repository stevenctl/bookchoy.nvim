local M = {}

local defaults = {
  db_path = nil,
  db_url = nil,
  filetypes = { 'markdown', 'text' },
  pinyin_format = 'accented',
  max_window = 8,
  border = 'single',
  next_key = '<C-k>',   -- inside the hover float: cycle to next candidate
  prev_key = '<C-j>',   -- inside the hover float: cycle to previous candidate
  max_width = 80,       -- soft-wrap the float at this width; set to nil for no cap
}

local function plugin_root()
  local source = debug.getinfo(1, 'S').source:sub(2)
  return vim.fn.fnamemodify(source, ':h:h:h')
end

local function default_db_path()
  return vim.fn.stdpath('data') .. '/bookchoy/zh_en_dictionary.sqlite3'
end

M.opts = vim.tbl_deep_extend('force', defaults, { db_path = default_db_path() })

function M.setup(opts)
  M.opts = vim.tbl_deep_extend('force', defaults, { db_path = default_db_path() }, opts or {})
end

function M.attach(bufnr)
  if not bufnr or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end

  -- Defensive: never start an LSP for a buffer that's gone or unloaded;
  -- Neovim's changetracking will crash with nil buf_state on the next
  -- send_changes / detach if we do.
  if not vim.api.nvim_buf_is_valid(bufnr) then return nil end
  if not vim.api.nvim_buf_is_loaded(bufnr) then return nil end

  local existing = vim.lsp.get_clients({ bufnr = bufnr, name = 'bookchoy' })
  if #existing > 0 then
    return existing[1].id
  end

  local db = require('bookchoy.db')
  db.ensure_open(M.opts, function(ok, err)
    if not ok then
      vim.notify('bookchoy: ' .. err, vim.log.levels.ERROR)
      return
    end

    if not vim.api.nvim_buf_is_valid(bufnr) then return end
    if not vim.api.nvim_buf_is_loaded(bufnr) then return end

    local server = require('bookchoy.server')
    vim.lsp.start({
      name = 'bookchoy',
      cmd = server.make_cmd(M.opts),
      root_dir = vim.fn.getcwd(),
    }, { bufnr = bufnr })
  end)
end

function M.next_match()
  require('bookchoy.state').step(0, 1)
end

function M.prev_match()
  require('bookchoy.state').step(0, -1)
end

function M.reload()
  require('bookchoy.db').close()
  require('bookchoy.db').ensure_open(M.opts, function(ok, err)
    if not ok then
      vim.notify('bookchoy reload: ' .. err, vim.log.levels.ERROR)
    else
      vim.notify('bookchoy: reloaded', vim.log.levels.INFO)
    end
  end)
end

return M
