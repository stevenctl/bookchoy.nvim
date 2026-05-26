if vim.g.loaded_bookchoy then return end
vim.g.loaded_bookchoy = 1

-- Default highlight for word_ref tokens in hover floats. `default = true`
-- means a user-provided override via `vim.api.nvim_set_hl('BookchoyWordRef', ...)`
-- wins. Re-apply on ColorScheme so a `:colorscheme` change doesn't lose it.
local function set_default_hl()
  vim.api.nvim_set_hl(0, 'BookchoyWordRef', { link = '@markup.link', default = true })
end
set_default_hl()
vim.api.nvim_create_autocmd('ColorScheme', { callback = set_default_hl })

vim.api.nvim_create_user_command('BookchoyAttach', function()
  require('bookchoy').attach(0)
end, { desc = 'Attach the bookchoy LSP to the current buffer' })

vim.api.nvim_create_user_command('BookchoyNext', function()
  require('bookchoy').next_match()
end, { desc = 'Show the next candidate for the current Chinese word' })

vim.api.nvim_create_user_command('BookchoyPrev', function()
  require('bookchoy').prev_match()
end, { desc = 'Show the previous candidate for the current Chinese word' })

vim.api.nvim_create_user_command('BookchoyReload', function()
  require('bookchoy').reload()
end, { desc = 'Reopen the dictionary database' })

local group = vim.api.nvim_create_augroup('Bookchoy', { clear = true })

vim.api.nvim_create_autocmd('FileType', {
  group = group,
  callback = function(args)
    -- Filetype matches first (cheap, before any plugin requires).
    local opts = require('bookchoy').opts
    if not opts.filetypes then return end
    local match = false
    for _, ft in ipairs(opts.filetypes) do
      if ft == args.match then match = true; break end
    end
    if not match then return end

    -- Defer the attach: snacks picker / telescope previewers fire FileType
    -- on transient buffers that they immediately tear down. Attaching here
    -- races with their nvim_buf_delete and crashes Neovim's LSP changetracking
    -- on nil buf_state. Schedule, then re-check that the buffer is still a
    -- real file buffer at that point.
    local bufnr = args.buf
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then return end
      if not vim.api.nvim_buf_is_loaded(bufnr) then return end
      if vim.bo[bufnr].buftype ~= '' then return end           -- skip nofile, help, qf, prompt, etc.
      if vim.api.nvim_buf_get_name(bufnr) == '' then return end -- skip unnamed (preview-y)
      require('bookchoy').attach(bufnr)
    end)
  end,
})

vim.api.nvim_create_autocmd('CursorMoved', {
  group = group,
  callback = function(args)
    require('bookchoy.state').clear(args.buf)
  end,
})

vim.api.nvim_create_autocmd({ 'BufDelete', 'BufWipeout' }, {
  group = group,
  callback = function(args)
    require('bookchoy.state').clear(args.buf)
  end,
})
