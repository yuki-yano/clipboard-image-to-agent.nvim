local M = {}

local uv = vim.loop

---@class ClipboardImageToAgentCommand
---@field command string[]
---@field output '"file"'|'"stdout"'
---@field description? string

---@class ClipboardImageToAgentFallbackResult
---@field text string
---@field trailing_space? boolean

---@class ClipboardImageToAgentOptions
---@field cache_dir? string
---@field filename_prefix? string
---@field commands? ClipboardImageToAgentCommand[]
---@field trailing_space? boolean
---@field fallback? fun(err: string): string|ClipboardImageToAgentFallbackResult|nil

---@class ClipboardImageToAgentConfig : ClipboardImageToAgentOptions
---@field cache_dir string
---@field filename_prefix string
---@field commands ClipboardImageToAgentCommand[]
---@field trailing_space boolean

---@type ClipboardImageToAgentCommand[]
local default_commands = {
  {
    command = { 'pngpaste', '$OUTPUT' },
    output = 'file',
    description = 'pngpaste (macOS)',
  },
  {
    command = { 'wl-paste', '--type', 'image/png' },
    output = 'stdout',
    description = 'wl-paste (Wayland)',
  },
  {
    command = { 'xclip', '-selection', 'clipboard', '-t', 'image/png', '-o' },
    output = 'stdout',
    description = 'xclip (X11)',
  },
}

local function default_cache_dir()
  local tmpdir = vim.env.TMPDIR
  if tmpdir and tmpdir ~= '' then
    return vim.fs.normalize(vim.fs.joinpath(tmpdir, 'clipboard-images'))
  end

  if uv and uv.os_tmpdir then
    local uv_tmpdir = uv.os_tmpdir()
    if uv_tmpdir and uv_tmpdir ~= '' then
      return vim.fs.normalize(vim.fs.joinpath(uv_tmpdir, 'clipboard-images'))
    end
  end

  local fallback = vim.fn.stdpath('cache')
  return vim.fs.normalize(vim.fs.joinpath(fallback, 'clipboard-images'))
end

---@type ClipboardImageToAgentConfig
local config = {
  cache_dir = default_cache_dir(),
  filename_prefix = 'clipboard-image-to-agent',
  commands = default_commands,
  trailing_space = true,
  fallback = nil,
}

local function deepcopy(tbl)
  if type(tbl) ~= 'table' then
    return tbl
  end
  local res = {}
  for k, v in pairs(tbl) do
    res[k] = deepcopy(v)
  end
  return res
end

local function ensure_dir(dir)
  if vim.fn.isdirectory(dir) == 1 then
    return dir
  end
  vim.fn.mkdir(dir, 'p')
  return dir
end

local function unique_image_path()
  local dir = ensure_dir(config.cache_dir)
  local stamp = os.date('%Y%m%d%H%M%S')
  local suffix
  if uv and uv.hrtime then
    suffix = tostring(uv.hrtime()):sub(-9)
  else
    suffix = tostring(math.random(0, 1000000000))
  end
  return string.format('%s/%s-%s-%s.png', dir, config.filename_prefix, stamp, suffix)
end

local function expand_command(command, dest)
  local expanded = {}
  for _, part in ipairs(command) do
    if part == '$OUTPUT' then
      table.insert(expanded, dest)
    else
      table.insert(expanded, part)
    end
  end
  return expanded
end

local function write_file(path, bytes)
  local file, err = io.open(path, 'wb')
  if not file then
    return false, err
  end
  if bytes and #bytes > 0 then
    file:write(bytes)
  else
    file:write('')
  end
  file:close()
  return true
end

local function system_run(cmd, opts)
  opts = opts or {}
  local system = vim.system
  if not system then
    error('clipboard-image-to-agent.nvim requires Neovim 0.10 or newer (vim.system)')
  end
  return system(cmd, opts):wait()
end

local function try_capture(entry, dest)
  local exe = entry.command[1]
  if vim.fn.executable(exe) ~= 1 then
    return nil, string.format('%s is not executable', exe)
  end

  local args = expand_command(entry.command, dest)
  if entry.output == 'file' then
    local result = system_run(args, { text = true })
    if result.code ~= 0 then
      local reason = result.stderr
      if reason and reason ~= '' then
        reason = vim.trim(reason)
      else
        reason = string.format('%s exited with code %d', exe, result.code)
      end
      return nil, reason
    end
    return dest
  end

  local result = system_run(args, { text = false })
  if result.code ~= 0 then
    local reason = result.stderr
    if reason and reason ~= '' then
      reason = vim.trim(reason)
    else
      reason = string.format('%s exited with code %d', exe, result.code)
    end
    return nil, reason
  end
  local ok, err = write_file(dest, result.stdout)
  if not ok then
    return nil, err
  end
  return dest
end

local function validate_file(path)
  if not uv or not uv.fs_stat then
    return true
  end
  local stat = uv.fs_stat(path)
  return stat and (stat.size or 0) > 0
end

local function insert_text(text)
  local win = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_get_current_buf()
  local row, col = unpack(vim.api.nvim_win_get_cursor(win))
  local lines = vim.split(text, '\n', true)
  vim.api.nvim_buf_set_text(bufnr, row - 1, col, row - 1, col, lines)
  local last = lines[#lines]
  local new_row = row + #lines - 1
  local new_col = (#lines == 1) and (col + #last) or #last
  vim.api.nvim_win_set_cursor(win, { new_row, new_col })
end

local function with_trailing_space(text, override)
  local trailing = config.trailing_space
  if override ~= nil then
    trailing = override
  end
  if trailing then
    return text .. ' '
  end
  return text
end

local function run_fallback(err)
  local fallback = config.fallback
  if not fallback then
    return false, err
  end

  local ok, res = pcall(fallback, err)
  if not ok then
    return false, string.format('fallback handler errored: %s', res)
  end

  local text, trailing_override = res, nil
  if type(res) == 'table' then
    text = res.text
    trailing_override = res.trailing_space
  end

  if not text or text == '' then
    return false, err
  end

  local to_insert = with_trailing_space(text, trailing_override)
  insert_text(to_insert)
  return true, to_insert
end

---@param opts? ClipboardImageToAgentOptions
function M.setup(opts)
  opts = opts or {}
  if opts.cache_dir then
    config.cache_dir = vim.fs.normalize(opts.cache_dir)
  end
  if opts.filename_prefix then
    config.filename_prefix = opts.filename_prefix
  end
  if opts.commands then
    config.commands = opts.commands
  else
    config.commands = deepcopy(default_commands)
  end
  if opts.trailing_space ~= nil then
    config.trailing_space = opts.trailing_space
  end
  if opts.fallback ~= nil then
    config.fallback = opts.fallback
  end
end

local function capture_image()
  local dest = unique_image_path()
  local errors = {}
  for _, entry in ipairs(config.commands) do
    local ok, err = try_capture(entry, dest)
    if ok then
      if validate_file(dest) then
        return dest
      end
      table.insert(errors, string.format('%s produced empty file', entry.description or entry.command[1]))
    else
      table.insert(errors, string.format('%s: %s', entry.description or entry.command[1], err))
    end
  end
  os.remove(dest)
  return nil, table.concat(errors, '; ')
end

function M.paste()
  local path, err = capture_image()
  if not path then
    return run_fallback(err)
  end
  local abs = with_trailing_space(vim.fs.normalize(path))
  insert_text(abs)
  return true, abs
end

return M
