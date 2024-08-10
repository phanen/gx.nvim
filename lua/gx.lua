local M = {}

---@class GxHandler
---@field filetype string|string[]?
---@field filename string?
---@field disable boolean
---@field handle string|fun(mode: string, text: string): string?

---@class GxOptions
---@field git_remote_push boolean
---@field git_remotes string[]
---@field leave_visual boolean
---@field search_engine "google"|"bing"|"duckduckgo"|"ecosia"|"yandex"
---@field handlers table<string, GxHandler>

---@class GxSelection
---@field name string
---@field url string

---@type GxOptions
local options = ...
options = {
  git_remote_push = false,
  git_remotes = { 'upstream', 'origin' },
  leave_visual = true,
  search_engine = 'google',
  handlers = {
    brewfile = {
      filename = 'Brewfile',
      handle = function(text)
        -- navigate to Homebrew Formulae url
        local brew_pattern = 'brew ["]([^%s]*)["]'
        local cask_pattern = 'cask ["]([^%s]*)["]'
        local brew = text:match(brew_pattern)
        local cask = text:match(cask_pattern)
        if brew then return 'https://formulae.brew.sh/formula/' .. brew end
        if cask then return 'https://formulae.brew.sh/cask/' .. cask end
      end,
    },
    cargo = {
      filename = 'Cargo.toml',
      handle = function(text)
        local crate = text:match('(%w+)%s-=%s')
        if crate then return 'https://crates.io/crates/' .. crate end
      end,
    },
    commit = {
      handle = function(text)
        local pattern = '(%x%x%x%x%x%x%x+)'
        local commit_hash = text:match(pattern)
        if not commit_hash or #commit_hash > 40 then return end

        local remotes = options.git_remotes
        if type(remotes) == 'function' then remotes = remotes(vim.fn.expand('%:p')) end

        local push = options.git_remote_push
        if type(push) == 'function' then push = push(vim.fn.expand('%:p')) end

        local git_url = u.git.smart_remote_url()
        if not git_url then return end
        return git_url .. '/commit/' .. commit_hash
      end,
    },
    cve = {
      handle = function(text)
        local cve_id = text:match('(CVE[%d-]+)')
        if not cve_id or #cve_id > 20 then return end
        return 'https://nvd.nist.gov/vuln/detail/' .. cve_id
      end,
    },
    github = {
      handle = function(text)
        local match = text:match('([%w-_.]+/[%w-_.]+#%d+)')
        if not match then match = text:match('([%w-_.]+#%d+)') end
        if not match then match = text:match('(#%d+)') end
        if not match then return end
        local owner, repo, issue = match:match('([^/#]*)/?([^#]*)#(.+)')

        local remotes = options.git_remotes
        if type(remotes) == 'function' then remotes = remotes(vim.fn.expand('%:p')) end

        local push = options.git_remote_push
        if type(push) == 'function' then push = push(vim.fn.expand('%:p')) end

        local git_url = u.git.smart_remote_url() -- get_remote_url(remotes, push, owner, repo)
        if not git_url then return end
        return git_url .. '/issues/' .. issue
      end,
    },
    go = {
      filetype = { 'go' },
      handle = function()
        local node = vim.treesitter.get_node()
        if not node then return end
        if node:type() ~= 'import_spec' then
          if node:type() == 'import_declaration' then
            node = node:named_child(0)
          else
            node = node:parent()
          end
          if not node then return end
          if node:type() ~= 'import_spec' then return end
        end

        local path_node = node:field('path')[1]
        local start_line, start_col, end_line, end_col = path_node:range()

        local text = vim.api.nvim_buf_get_lines(0, start_line, end_line + 1, false)[1]
        local pkg = text:sub(start_col + 2, end_col - 1) -- remove quotes
        return 'https://pkg.go.dev/' .. pkg
      end,
    },
    markdown = {
      filetype = { 'markdown' },
      handle = '%[[%a%d%s.,?!:;@_{}~]*%]%((https?://[a-zA-Z0-9_/%-%.~@\\+#=?&]+)%)',
    },
    nvim_plugin = {
      filetype = { 'lua', 'vim' },
      filename = nil,
      handle = function(text)
        local username_repo = text:match('["\']([^%s~/]*/[^%s~/]*)["\']')
        if username_repo then return 'https://github.com/' .. username_repo end
      end,
    },
    package_json = {
      filetype = { 'json' },
      filename = 'package.json',
      handle = function(text)
        local npm_package = text:match('["]([^%s]*)["]:')
        if not npm_package then return end
        return 'https://www.npmjs.com/package/' .. npm_package
      end,
    },
    search = {
      handle = function(text)
        local search_url = setmetatable({
          google = 'https://www.google.com/search?q=',
          bing = 'https://www.bing.com/search?q=',
          duckduckgo = 'https://duckduckgo.com/?q=',
          ecosia = 'https://www.ecosia.org/search?q=',
          yandex = 'https://ya.ru/search?text=',
        }, { __index = function(_, url) return url end })

        ---@param url string?
        ---@return string?
        local urlencode = function(url)
          if url == nil then return end
          url = url:gsub('\n', '\r\n')
          url = string.gsub(url, '([^%w _%%%-%.~])', vim.text.hexdecode)
          url = url:gsub(' ', '+')
          return url
        end

        return search_url[options.search_engine] .. urlencode(text)
      end,
    },
    url_scheme = { -- get url from text (with http/s)
      handle = '(https?://[a-zA-Z%d_/%%%-%.~@\\+#=?&:–]+)',
    },
  },
}

M.setup = function(opts)
  options = vim.tbl_deep_extend('force', opts or {}, options)
  vim.api.nvim_create_user_command('Browse', function(args)
    ---@type string?
    local text = args.fargs[1]
    return M.open(text)
  end, { nargs = '?' })
end

---@type fun(mode: string): string?
local get_text = function(mode)
  mode = mode or vim.api.nvim_get_mode().mode

  local text = nil
  if mode == 'n' or mode == 'nt' then
    -- text = vim.api.nvim_get_current_line()
    text = vim.fn.expand('<cWORD>')
  elseif vim.tbl_contains({ 'v', 'V', '\022' }, mode) then
    text = table
      .concat(vim.fn.getregion(vim.fn.getpos('.'), vim.fn.getpos('v'), { type = vim.fn.mode() }), '\n')
      :gsub('\n', '')
  end
  return text
end

---@param text string?
---@return nil
M.open = function(text)
  local mode = vim.api.nvim_get_mode().mode
  text = text or get_text(mode)
  if not text then return nil end

  -- way better than tbl_filter, since it handle non-list
  local hs = vim.iter(options.handlers):filter(function(_, h)
    if h.filetype and vim.tbl_contains(h.filetype, vim.bo.filetype) then return true end
    if h.filename and vim.api.nvim_buf_get_name(0):match(h.filename) then return true end
    return not h.filetype and not h.filename and not h.disable
  end)

  ---@type GxSelection[]
  ---compounded type?
  -- iterate each handler to collect the result
  -- todo: maybe we can sort by priority
  local urls = hs:fold({}, function(urls, name, h)
    local url
    if type(h.handle) == 'string' then
      url = text:match(h.handle)
    else
      url = h.handle(text)
    end
    if url and not urls[url] then
      local i = #urls + 1
      urls[i] = { name = name, url = url }
      urls[url] = true -- check if we already found this url
      urls[name] = i -- used to remove search optionally laterly
    end
    return urls
  end)

  if options.leave_visual then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<esc>', true, false, true), 'x', false)
  end

  -- just use url if we found scheme
  ---@cast urls table<string, integer>
  if urls.url_scheme then
    local url = urls[urls.url_scheme].url
    return vim.ui.open(url)
  end

  -- ignore "search" handler in this case
  ---@cast urls table<string, integer>
  if #urls >= 2 and urls.search then table.remove(urls, urls.search) end

  local n_urls = #urls
  if n_urls == 0 then return nil end
  if n_urls == 1 then return vim.ui.open(urls[1].url) end

  -- TODO: jump to single result?
  vim.ui.select(urls, {
    prompt = 'Multiple patterns match. Select:',
    format_item = (function()
      local format_len = #'package_json'
      return function(item)
        local pad_str = (' '):rep(format_len - #item.name)
        return ('(%s)%s %s'):format(item.name, pad_str, item.url)
      end
    end)(),
  }, function(selected)
    if not selected then return end
    return vim.ui.open(selected.url)
  end)
end

return M
