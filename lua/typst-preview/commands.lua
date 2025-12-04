local events = require 'typst-preview.events'
local fetch = require 'typst-preview.fetch'
local utils = require 'typst-preview.utils'
local config = require 'typst-preview.config'
local servers = require 'typst-preview.servers'
local input_storage = require 'typst-preview.input'

local M = {}

---Scroll all preview to cursor position.
function M.sync_with_cursor()
  for _, ser in pairs(servers.get_all()) do
    servers.sync_with_cursor(ser)
  end
end

---Create user commands
function M.create_commands()
  local function preview_off()
    local path = utils.get_buf_path(0)

    if path ~= '' and servers.remove(config.opts.get_main_file(path)) then
      utils.print 'Preview stopped'
    else
      utils.print 'Preview not running'
    end
  end

  local function get_path()
    local path = utils.get_buf_path(0)
    if path == '' then
      utils.notify('Can not preview an unsaved buffer.', vim.log.levels.ERROR)
      return nil
    else
      return config.opts.get_main_file(path)
    end
  end

  ---@param mode mode?
  local function preview_on(mode)
    -- check if binaries are available and tell them to fetch first
    for _, bin in pairs(fetch.bins_to_fetch()) do
      if
        not config.opts.dependencies_bin[bin.name] and not fetch.up_to_date(bin)
      then
        utils.notify(
          bin.name
            .. ' not found or out of date\nPlease run :TypstPreviewUpdate first!',
          vim.log.levels.ERROR
        )
        return
      end
    end

    local path = get_path()
    if path == nil then
      return
    end

    mode = mode or 'document'

    local ser = servers.get(path)
    if ser == nil or ser[mode] == nil then
      servers.init(path, mode, function(s)
        events.listen(s)
        input_storage.set_path_mode(path, mode)
      end)
    else
      local s = ser[mode]
      print 'Opening another frontend'
      utils.visit(s.link)
    end
  end

  vim.api.nvim_create_user_command('TypstPreviewUpdate', function()
    fetch.fetch(false)
  end, {})

  vim.api.nvim_create_user_command('TypstPreview', function(opts)
    local mode
    if #opts.fargs == 1 then
      mode = opts.fargs[1]
      if mode ~= 'document' and mode ~= 'slide' then
        utils.notify(
          'Invalid preview mode: "'
            .. mode
            .. '.'
            .. ' Should be one of "document" and "slide"',
          vim.log.levels.ERROR
        )
      end
    else
      assert(#opts.fargs == 0)
      local path = get_path()
      if path == nil then
        return
      end
      local sers = servers.get(path)
      if sers ~= nil then
        mode = servers.get_last_mode(path)
      end
    end

    preview_on(mode)
  end, {
    nargs = '?',
    complete = function(_, _, _)
      return { 'document', 'slide' }
    end,
  })
  vim.api.nvim_create_user_command('TypstPreviewStop', preview_off, {})
  vim.api.nvim_create_user_command('TypstPreviewToggle', function()
    local path = get_path()
    if path == nil then
      return
    end

    if servers.get(path) ~= nil then
      preview_off()
    else
      preview_on(servers.get_last_mode(path))
    end
  end, {})

  vim.api.nvim_create_user_command('TypstPreviewFollowCursor', function()
    config.set_follow_cursor(true)
  end, {})
  vim.api.nvim_create_user_command('TypstPreviewNoFollowCursor', function()
    config.set_follow_cursor(false)
  end, {})
  vim.api.nvim_create_user_command('TypstPreviewFollowCursorToggle', function()
    config.set_follow_cursor(not config.get_follow_cursor())
  end, {})
  vim.api.nvim_create_user_command('TypstPreviewSyncCursor', function()
    M.sync_with_cursor()
  end, {})

  -- TypstPreviewInput command
  vim.api.nvim_create_user_command('TypstPreviewInput', function(opts)
    local current_inputs = input_storage.get_inputs()

    -- Show current inputs if no arguments provided
    if #opts.fargs == 0 then
      if vim.tbl_isempty(current_inputs) then
        utils.print 'No input fields set'
      else
        local input_strs = {}
        for key, value in pairs(current_inputs) do
          table.insert(input_strs, key .. '=' .. value)
        end
        utils.print('Current inputs: ' .. table.concat(input_strs, ' '))
      end
      return
    end

    -- Parse new inputs from command arguments
    local input_str = table.concat(opts.fargs, ' ')
    local new_inputs = input_storage.parse_input_string(input_str)

    if vim.tbl_isempty(new_inputs) then
      utils.notify(
        'Invalid input format. Expected: key=value',
        vim.log.levels.ERROR
      )
      return
    end

    -- Check if inputs actually changed
    local inputs_changed = false
    if vim.tbl_isempty(current_inputs) then
      inputs_changed = not vim.tbl_isempty(new_inputs)
    else
      -- Check if all keys and values match
      for key, value in pairs(new_inputs) do
        if current_inputs[key] ~= value then
          inputs_changed = true
          break
        end
      end
      -- Check if any keys were removed
      if not inputs_changed then
        for key, _ in pairs(current_inputs) do
          if new_inputs[key] == nil then
            inputs_changed = true
            break
          end
        end
      end
    end

    -- Set new inputs
    input_storage.set_inputs(new_inputs)

    -- Show what was set
    local input_strs = {}
    for key, value in pairs(new_inputs) do
      table.insert(input_strs, key .. '=' .. value)
    end
    utils.print('Inputs set: ' .. table.concat(input_strs, ' '))

    -- Restart all running servers if inputs changed
    if inputs_changed then
      local all_servers = servers.get_all()
      local paths_to_restart = {}

      -- Collect unique paths that need restarting
      for _, server in ipairs(all_servers) do
        paths_to_restart[server.path] = true
      end

      -- Stop all servers first
      for path, _ in pairs(paths_to_restart) do
        if servers.remove(path) then
          utils.print('Stopping preview for: ' .. path)
        end
      end

      -- Restart servers with new inputs
      for path, _ in pairs(paths_to_restart) do
        local mode = input_storage.get_path_mode(path) or 'document'
        -- Schedule restart after a short delay to ensure clean shutdown
        vim.defer_fn(function()
          servers.init(path, mode, function(s)
            events.listen(s)
            input_storage.set_path_mode(path, mode)
          end)
          utils.print('Restarted preview for: ' .. path .. ' (mode: ' .. mode .. ')')
        end, 100)
      end
    end
  end, {
    nargs = '*',
    complete = function()
      -- Suggest common input patterns (could be enhanced with project-specific inputs)
      return {}
    end,
  })
end

return M
