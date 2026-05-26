-- Minimal init for trying out bookchoy.nvim without touching your real config.
--
-- Run from the plugin root:
--   nvim --clean -u test/minimal_init.lua test/sample.md
--
-- Override DB_PATH or DB_URL via env vars if you want to test other dictionaries.

local plugin_root = vim.fn.fnamemodify(vim.fn.resolve(vim.fn.expand('<sfile>:p')), ':h:h')
local data_root = plugin_root .. '/.test-data'
local sqlite_path = data_root .. '/sqlite.lua'

vim.fn.mkdir(data_root, 'p')
if vim.fn.isdirectory(sqlite_path) == 0 then
  vim.notify('cloning sqlite.lua…', vim.log.levels.INFO)
  vim.fn.system({ 'git', 'clone', '--depth', '1', 'https://github.com/kkharji/sqlite.lua', sqlite_path })
end

vim.opt.runtimepath:prepend(sqlite_path)
vim.opt.runtimepath:prepend(plugin_root)

require('bookchoy').setup({
  db_path = os.getenv('CHINESE_DICT_DB')
    or '/home/landow/gamedev/chinese_app/data/cidian/prepared/custom/custom_dictionary.sqlite3',
  db_url = os.getenv('CHINESE_DICT_URL'),
  pinyin_format = 'accented',
})

vim.opt.number = true
vim.opt.swapfile = false  -- so headless tests that os.exit() don't leave .swp behind
vim.cmd('syntax on')
