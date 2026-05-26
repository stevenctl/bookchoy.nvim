local M = {}

local uv = vim.uv or vim.loop

local function plugin_root()
  local source = debug.getinfo(1, 'S').source:sub(2)
  return vim.fn.fnamemodify(source, ':h:h:h')
end

local function decompress_bundled(path, callback)
  local gz = plugin_root() .. '/zh_en_dictionary.sqlite3.gz'
  if not uv.fs_stat(gz) then return callback(false) end

  local dir = vim.fn.fnamemodify(path, ':h')
  vim.fn.mkdir(dir, 'p')

  if vim.system then
    vim.system({ 'gunzip', '-k', '-c', gz }, { text = false }, function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          return callback(false, 'gunzip failed: ' .. (result.stderr or 'unknown error'))
        end
        local fd = uv.fs_open(path, 'w', 438)
        if not fd then return callback(false, 'failed to write ' .. path) end
        uv.fs_write(fd, result.stdout)
        uv.fs_close(fd)

        if not uv.fs_stat(path) then
          return callback(false, 'decompression produced no output')
        end

        callback(true)
      end)
    end)
  else
    vim.fn.system('gunzip -k -c ' .. vim.fn.shellescape(gz) .. ' > ' .. vim.fn.shellescape(path))
    if not uv.fs_stat(path) then
      return callback(false, 'decompression produced no output')
    end
    vim.notify('bookchoy: dictionary ready', vim.log.levels.INFO)
    callback(true)
  end
end

function M.ensure(opts, callback)
  local path = opts.db_path
  if not path then
    return callback(nil, 'db_path is not set')
  end

  if uv.fs_stat(path) then
    return callback(path)
  end

  decompress_bundled(path, function(ok, err)
    if ok then return callback(path) end

    if not opts.db_url then
      local msg = 'no dictionary at ' .. path
      if err then msg = msg .. ' (' .. err .. ')' end
      msg = msg .. ' and no db_url configured'
      return callback(nil, msg)
    end

    local dir = vim.fn.fnamemodify(path, ':h')
    vim.fn.mkdir(dir, 'p')

    local tmp = path .. '.part'
    pcall(uv.fs_unlink, tmp)

    local function finish_download(result)
      if result.code ~= 0 then
        pcall(uv.fs_unlink, tmp)
        return callback(nil, 'download failed: ' .. (result.stderr or 'unknown error'))
      end
      local rok, rerr = uv.fs_rename(tmp, path)
      if not rok then
        return callback(nil, 'rename failed: ' .. tostring(rerr))
      end
      callback(path)
    end

    if vim.system then
      vim.system({ 'curl', '-fsSL', '-o', tmp, opts.db_url }, { text = true }, function(result)
        vim.schedule(function() finish_download(result) end)
      end)
    else
      local out = vim.fn.system({ 'curl', '-fsSL', '-o', tmp, opts.db_url })
      finish_download({ code = vim.v.shell_error, stderr = out })
    end
  end)
end

return M
