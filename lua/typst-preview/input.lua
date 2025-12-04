local M = {}

-- Global storage for input fields
local input_fields = {}

-- Store current mode for each path to enable restart
local path_modes = {}

---Get current input fields
---@return table
function M.get_inputs()
  return vim.deepcopy(input_fields)
end

---Set input fields
---@param inputs table
function M.set_inputs(inputs)
  input_fields = vim.deepcopy(inputs)
end

---Add or update an input field
---@param key string
---@param value string
function M.set_input(key, value)
  input_fields[key] = value
end

---Clear all input fields
function M.clear_inputs()
  input_fields = {}
end

---Parse input arguments string like "key1=value1 key2=value2"
---@param input_str string
---@return table
function M.parse_input_string(input_str)
  local inputs = {}
  for key_value in input_str:gmatch('([^%s]+)') do
    local key, value = key_value:match('^([^=]+)=(.+)$')
    if key and value then
      inputs[key] = value
    end
  end
  return inputs
end

---Store the mode for a path
---@param path string
---@param mode string
function M.set_path_mode(path, mode)
  path_modes[path] = mode
end

---Get the mode for a path
---@param path string
---@return string|nil
function M.get_path_mode(path)
  return path_modes[path]
end

---Clear the mode for a path
---@param path string
function M.clear_path_mode(path)
  path_modes[path] = nil
end

return M