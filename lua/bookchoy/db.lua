local M = {}

local _sqlite = nil
local _db = nil
local _pending = nil

local function load_sqlite()
  if _sqlite then return _sqlite end
  local ok, mod = pcall(require, 'sqlite.db')
  if not ok then
    error("bookchoy requires 'kkharji/sqlite.lua' to be installed")
  end
  _sqlite = mod
  return _sqlite
end

local function flush_pending(ok, err)
  local cbs = _pending
  _pending = nil
  for _, cb in ipairs(cbs) do cb(ok, err) end
end

function M.ensure_open(opts, callback)
  if _db then return callback(true) end

  if _pending then
    _pending[#_pending + 1] = callback
    return
  end

  _pending = { callback }

  local download = require('bookchoy.download')
  download.ensure(opts, function(path, err)
    if not path then return flush_pending(false, err) end

    local sqlite = load_sqlite()
    local ok, dbh = pcall(function()
      return sqlite({ uri = path, opts = { keep_open = true } })
    end)
    if not ok then
      return flush_pending(false, 'failed to open db: ' .. tostring(dbh))
    end
    _db = dbh
    flush_pending(true)
  end)
end

function M.close()
  if _db then
    pcall(function() _db:close() end)
    _db = nil
  end
end

local function sql_quote(s)
  return "'" .. (s:gsub("'", "''")) .. "'"
end

local function in_list(values)
  local quoted = {}
  for i, v in ipairs(values) do quoted[i] = sql_quote(v) end
  return table.concat(quoted, ',')
end

function M.lookup_words(texts)
  if not _db or #texts == 0 then return {} end
  local list = in_list(texts)
  local sql = string.format(
    'SELECT id, jianti, fanti, pinyin, pinyinNum, frequency FROM Word ' ..
    'WHERE jianti IN (%s) OR fanti IN (%s)',
    list, list
  )
  local rows = _db:eval(sql)
  if type(rows) ~= 'table' then return {} end
  return rows
end

function M.lookup_word_by_id(id)
  if not _db or not id or id == '' then return nil end
  local sql = 'SELECT id, jianti, fanti, pinyin, pinyinNum, frequency FROM Word ' ..
              'WHERE id = ' .. sql_quote(id) .. ' LIMIT 1'
  local rows = _db:eval(sql)
  if type(rows) ~= 'table' or #rows == 0 then return nil end
  return rows[1]
end

function M.lookup_definitions(word_ids)
  if not _db or #word_ids == 0 then return {} end
  local sql = string.format(
    'SELECT wordId, text, source FROM WordDefinition WHERE wordId IN (%s)',
    in_list(word_ids)
  )
  local rows = _db:eval(sql)
  if type(rows) ~= 'table' then return {} end
  local by_word = {}
  for _, r in ipairs(rows) do
    by_word[r.wordId] = by_word[r.wordId] or {}
    table.insert(by_word[r.wordId], { text = r.text, source = r.source })
  end
  return by_word
end

return M
