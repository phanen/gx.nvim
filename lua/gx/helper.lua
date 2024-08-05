local M = {}

-- check that cursor on uri in normal mode
function M.check_if_cursor_on_url(mode, i, j)
  if mode ~= "n" then
    return true
  end

  local col = vim.api.nvim_win_get_cursor(0)[2]
  if i <= (col + 1) and j >= (col + 1) then
    return true
  end

  return false
end

-- find pattern in line and check if cursor on it
function M.find(line, mode, pattern, startIndex)
  startIndex = startIndex or 1
  local i, j, value = string.find(line, pattern, startIndex)

  if not i then
    return nil
  elseif M.check_if_cursor_on_url(mode, i, j) then
    return value
  else
    return M.find(line, mode, pattern, j + 1)
  end
end

-- ternary operator for lua
function M.ternary(cond, T, F)
  if cond then
    return T
  else
    return F
  end
end

---@param result string
local function parse_git_output(result)
  local domain, repository = result:gsub("%.git%s*$", ""):match("@(.*%..*):(.*)$")
  if domain and repository then
    return "https://" .. domain .. "/" .. repository
  end
  local url = result:gsub("%.git%s*$", ""):match("^https?://.+")
  if url then
    return url
  end
end

local function discover_remote(remotes, push, path)
  local url = nil
  for _, remote in ipairs(remotes) do
    local args = { "-C", path, "remote", "get-url", remote }
    if push then
      table.insert(args, "--push")
    end
    local obj = vim.system({ "git", unpack(args) }):wait()
    if obj.code == 0 then
      url = parse_git_output(obj.stdout)
      if url then
        return url
      end
    end
  end
  return url
end

function M.get_remote_url(remotes, push, owner, repo)
  local path = vim.fn.expand("%:p:h")
  local url = discover_remote(remotes, push, path)
  if not url then
    url = discover_remote(remotes, push, vim.api.nvim_get_current_dir())
  end

  if not url and (owner ~= "" and repo ~= "") then -- fallback to github if owner and repo are present
    url = "https://github.com/foo/bar"
  end
  if not url then
    return vim.notify("[gx]: " .. "No remote git repository found!", vim.log.levels.WARN)
  end
  if type(owner) == "string" and owner ~= "" then
    local domain, repository = url:match("^https?://([^/]+)/[^/]+/([^/]*)")
    if repo ~= "" then
      repository = repo
    end
    url = string.format("https://%s/%s/%s", domain, owner, repository)
  end

  return url
end
return M
