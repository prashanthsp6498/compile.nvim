local M = {}

local state = {
  buf = nil,
  win = nil,
  job = nil,
  origin_win = nil,
  cwd = nil,
  command = nil,
  run_id = 0,
  output = {},
  code = -1
}

local function is_valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function is_valid_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

local function shell_argv(cmd)
  local shell = vim.o.shell
  local flag = vim.o.shellcmdflag
  local argv = { shell }
  for part in string.gmatch(flag, "%S+") do
    table.insert(argv, part)
  end
  table.insert(argv, cmd)
  return argv
end

local function normalize_path(path, cwd)
  if path == "" then
    return path
  end

  path = path:match("%a.*")
  if path:match("^%a:[/\\]") or path:sub(1, 1) == "/" then
    return path
  end

  if vim.fs and vim.fs.normalize then
    return vim.fs.normalize(vim.fs.joinpath(cwd, path))
  end

  return vim.fn.fnamemodify(vim.fn.getcwd() .. "/" .. path, ":p")
end

local function parse_location(line)
  if line:find("://", 1, true) then
    return nil
  end

  local file, lnum, col = line:match("^(.-):(%d+):(%d+):")
  if file then
    return {
      file = file,
      lnum = tonumber(lnum),
      col = tonumber(col),
    }
  end

  file, lnum, col = line:match("^(.-):(%d+):(%d+)")

  if file then
      return {
          file = file,
          lnum = tonumber(lnum),
          col = tonumber(col),
      }
  end

  file, lnum = line:match("^(.-):(%d+):")
  if file then
    return {
      file = file,
      lnum = tonumber(lnum),
      col = 1,
    }
  end

  return nil
end

local function set_buffer_text(buf, lines)
  if not is_valid_buf(buf) then
    return
  end

  vim.bo[buf].modifiable = true
  local end_line = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_buf_set_lines(buf, end_line, end_line, false, lines)
  vim.bo[buf].modifiable = false
end

local function follow_output()
  if not is_valid_win(state.win) or not is_valid_buf(state.buf) then
    return
  end

  local line_count = math.max(1, vim.api.nvim_buf_line_count(state.buf))
  pcall(vim.api.nvim_win_set_cursor, state.win, { line_count, 0 })
end

local function clear_buffer(buf)
  if not is_valid_buf(buf) then
    return
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
  vim.bo[buf].modifiable = false
  vim.b[buf].compile_entries = {}
end

local function ensure_window()
  if is_valid_win(state.win) and is_valid_buf(state.buf) then
    return
  end

  if not is_valid_buf(state.buf) then
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.buf].buftype = "nofile"
    vim.bo[state.buf].bufhidden = "wipe"
    vim.bo[state.buf].swapfile = false
    vim.bo[state.buf].modifiable = false
    vim.bo[state.buf].filetype = "compile-output"
    vim.bo[state.buf].undofile = false
    vim.bo[state.buf].readonly = false
    vim.b[state.buf].compile_entries = {}
  end

  vim.cmd("botright 12split")
  state.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.win, state.buf)
  vim.wo[state.win].number = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn = "no"
  vim.wo[state.win].wrap = false
  vim.wo[state.win].cursorline = false 
  vim.wo[state.win].foldcolumn = "0"
  vim.wo[state.win].winfixheight = true

  local function map(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, {
      buffer = state.buf,
      nowait = true,
      silent = true,
      desc = desc,
    })
  end

  map("q", function()
    if is_valid_win(state.win) then
      vim.api.nvim_win_close(state.win, true)
    end
  end, "Close compile window")
  map("r", function() M.run(state.command) end, "re-run last command")

  map("+", function()
    if not is_valid_win(state.win) then
      return
    end

    local height = vim.api.nvim_win_get_height(state.win)
    vim.api.nvim_win_set_height(state.win, height + 2)
  end, "Increase compile window height")

  map("-", function()
    if not is_valid_win(state.win) then
      return
    end

    local height = vim.api.nvim_win_get_height(state.win)
    vim.api.nvim_win_set_height(state.win, math.max(4, height - 2))
  end, "Decrease compile window height")

  map("<CR>", function()
    if not is_valid_buf(state.buf) then
      return
    end

    local row = vim.api.nvim_win_get_cursor(state.win)[1]
    local entries = vim.b[state.buf].compile_entries or {}
    local entry = entries[row]
    if not entry then
      return
    end

    local target = normalize_path(entry.file, state.cwd or vim.fn.getcwd())
    if is_valid_win(state.origin_win) then
      vim.api.nvim_set_current_win(state.origin_win)
    end

    vim.cmd.edit(vim.fn.fnameescape(target))
    if entry.lnum then
      vim.api.nvim_win_set_cursor(0, { entry.lnum, math.max(0, (entry.col or 1) - 1) })
      vim.cmd("normal! zvzz")
    end
  end, "Jump to compile target")
end

local function update_state(lines)
    for _, line in ipairs(lines) do
        table.insert(state.output, line)
    end
end

local function append_output(lines)
  if not is_valid_buf(state.buf) then
    return
  end

  local entries = vim.b[state.buf].compile_entries or {}
  local base_line = vim.api.nvim_buf_line_count(state.buf)
  local chunk = {}

  for _, line in ipairs(lines) do
    local entry = parse_location(line)
    if entry then
      entries[base_line + #chunk + 1] = {
        file = entry.file,
        lnum = entry.lnum,
        col = entry.col,
      }
    end
    table.insert(chunk, line)
  end

  vim.b[state.buf].compile_entries = entries
  set_buffer_text(state.buf, chunk)
  follow_output()
end

local function append_header(command)
  clear_buffer(state.buf)
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, {
    string.format("Compile: %s", command),
    string.format("CWD: %s", state.cwd or vim.fn.getcwd()),
    "",
  })
  vim.bo[state.buf].modifiable = false
  follow_output()
end

local function stop_job()
  if state.job and state.job > 0 then
    pcall(vim.fn.jobstop, state.job)
  end
  state.job = nil
end

local function reset_state()
  state.buf = nil
  state.win = nil
  state.job = nil
  state.origin_win = nil
  state.cwd = nil
  state.command = nil
  state.output = nil
  state.code = 0
end

local function close_output_window()
  if is_valid_win(state.win) then
    pcall(vim.api.nvim_win_close, state.win, true)
  elseif is_valid_buf(state.buf) then
    pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
  end
end

local function sanitize_data(data)
  if not data or #data == 0 then
    return nil
  end

  local lines = vim.list_slice(data, 1, #data)
  local has_content = false
  for _, line in ipairs(lines) do
    if line ~= "" then
      has_content = true
      break
    end
  end

  if not has_content then
    return nil
  end

  if #lines > 1 and lines[#lines] == "" then
    table.remove(lines, #lines)
  end

  return lines
end

function M.run(cmd)
  local command = vim.trim(cmd or "")
  if command == "" then
    command = vim.o.makeprg
  end

  if vim.trim(command) == "" then
    vim.notify("Compile: no command to run", vim.log.levels.WARN)
    return
  end

  state.origin_win = vim.api.nvim_get_current_win()
  state.cwd = vim.fn.getcwd()
  state.command = command
  state.run_id = state.run_id + 1
  local run_id = state.run_id

  stop_job()
  ensure_window()
  append_header(command)

  local argv = shell_argv(command)
  local job_id = vim.fn.jobstart(argv, {
    cwd = state.cwd,
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data)
      if run_id ~= state.run_id then
        return
      end
      local lines = sanitize_data(data)
      if not lines then
        return
      end
      vim.schedule(function()
        if run_id == state.run_id then
          update_state(lines)
          append_output(lines)
        end
      end)
    end,
    on_stderr = function(_, data)
      if run_id ~= state.run_id then
        return
      end
      local lines = sanitize_data(data)
      if not lines then
        return
      end
      vim.schedule(function()
        if run_id == state.run_id then
          update_state(lines)
          append_output(lines)
        end
      end)
    end,
    on_exit = function(_, code)
      if run_id ~= state.run_id then
        return
      end
      vim.schedule(function()
        if run_id ~= state.run_id or not is_valid_buf(state.buf) then
          return
        end
        state.code = code
        local marker = code == 0 and "Compile finished successfully" or string.format("Compile exited with code %d", code)
        set_buffer_text(state.buf, { marker })
        follow_output()
        if code ~= 0 then
          vim.notify(marker, vim.log.levels.ERROR)
        end
      end)
    end,
  })

  if job_id <= 0 then
    vim.notify("Compile: failed to start job", vim.log.levels.ERROR)
    return
  end

  state.job = job_id
end


function M.reload()
  state.run_id = state.run_id + 1
  stop_job()
  close_output_window()
  reset_state()
  package.loaded["compile"] = nil
  vim.notify("Compile plugin reloaded", vim.log.levels.INFO)
end

function M.openLast()
    if state.code == -1 then
        vim.notify("No command executed previously.", vim.log.levels.INFO)
        return
    end
    ensure_window()
    append_header(state.command)
    append_output(state.output)
    local marker = state.code == 0 and "Compile finished successfully" or string.format("Compile exited with code %d", code)
    set_buffer_text(state.buf, { marker })
    follow_output()
    if state.code ~= 0 then
        vim.notify(marker, vim.log.levels.ERROR)
    end

end

return M
