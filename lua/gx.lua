local helper = require('gx.helper')

local M = {}

---@class GxHandler
---@field name string
---@field filetype string?|string[]?
---@field filename string?
---@field handle fun(mode: string, text: string): string?

---@class GxOptions
---@field handlers table<string, GxHandler>
---@field search_engine string
---@field select_for_search boolean
---@field git_remotes string[]
---@field git_remote_push boolean

---@class GxSelection
---@field name string?
---@field url string

---@type GxOptions
---avoid warnings
local options = ...

-- TODO: priority

options = {
  handlers = {
    brewfile = {
      filename = 'Brewfile',
      handle = function(mode, text)
        -- navigate to Homebrew Formulae url
        local brew_pattern = 'brew ["]([^%s]*)["]'
        local cask_pattern = 'cask ["]([^%s]*)["]'
        local brew = helper.find(text, mode, brew_pattern)
        local cask = helper.find(text, mode, cask_pattern)
        if brew then return 'https://formulae.brew.sh/formula/' .. brew end
        if cask then return 'https://formulae.brew.sh/cask/' .. cask end
      end,
    },
    cargo = {
      filename = 'Cargo.toml',
      handle = function(mode, text, _)
        local crate = helper.find(text, mode, '(%w+)%s-=%s')
        if crate then return 'https://crates.io/crates/' .. crate end
      end,
    },
    commit = {
      handle = function(mode, text)
        local pattern = '(%x%x%x%x%x%x%x+)'
        local commit_hash = helper.find(text, mode, pattern)
        if not commit_hash or #commit_hash > 40 then return end

        local remotes = options.git_remotes
        if type(remotes) == 'function' then remotes = remotes(vim.fn.expand('%:p')) end

        local push = options.git_remote_push
        if type(push) == 'function' then push = push(vim.fn.expand('%:p')) end

        local git_url = helper.get_remote_url(remotes, push)
        if not git_url then return end
        return git_url .. '/commit/' .. commit_hash
      end,
    },
    cve = {
      handle = function(mode, text)
        local cve_id = helper.find(text, mode, '(CVE[%d-]+)')
        if not cve_id or #cve_id > 20 then return end
        return 'https://nvd.nist.gov/vuln/detail/' .. cve_id
      end,
    },
    github = {
      handle = function(mode, text)
        local match = helper.find(text, mode, '([%w-_.]+/[%w-_.]+#%d+)')
        if not match then match = helper.find(text, mode, '([%w-_.]+#%d+)') end
        if not match then match = helper.find(text, mode, '(#%d+)') end
        if not match then return end
        local owner, repo, issue = match:match('([^/#]*)/?([^#]*)#(.+)')

        local remotes = options.git_remotes
        if type(remotes) == 'function' then remotes = remotes(vim.fn.expand('%:p')) end

        local push = options.git_remote_push
        if type(push) == 'function' then push = push(vim.fn.expand('%:p')) end

        local git_url = helper.get_remote_url(remotes, push, owner, repo)
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
      handle = function(mode, text)
        local pattern = '%[[%a%d%s.,?!:;@_{}~]*%]%((https?://[a-zA-Z0-9_/%-%.~@\\+#=?&]+)%)'
        return helper.find(text, mode, pattern)
      end,
    },
    nvim_plugin = {
      filetype = { 'lua', 'vim' },
      filename = nil,
      handle = function(mode, text)
        local pattern = '["\']([^%s~/]*/[^%s~/]*)["\']'
        local username_repo = helper.find(text, mode, pattern)
        if username_repo then return 'https://github.com/' .. username_repo end
      end,
    },
    package_json = {
      filetype = { 'json' },
      filename = 'package.json',
      handle = function(mode, text)
        local pattern = '["]([^%s]*)["]:'
        local npm_package = helper.find(text, mode, pattern)
        if not npm_package then return end
        return 'https://www.npmjs.com/package/' .. npm_package
      end,
    },
    search = {
      handle = function(mode, text)
        local search_url = {
          google = 'https://www.google.com/search?q=',
          bing = 'https://www.bing.com/search?q=',
          duckduckgo = 'https://duckduckgo.com/?q=',
          ecosia = 'https://www.ecosia.org/search?q=',
          yandex = 'https://ya.ru/search?text=',
        }

        local char_to_hex = function(c) return string.format('%%%02X', string.byte(c)) end

        local get_search_url_from_engine = function(engine)
          if search_url[engine] == nil then return engine end
          return search_url[engine]
        end

        --- [TODO:description]
        ---@param url string?
        ---@return string?
        local urlencode = function(url)
          if url == nil then return end
          url = url:gsub('\n', '\r\n')
          url = string.gsub(url, '([^%w _%%%-%.~])', char_to_hex)
          url = url:gsub(' ', '+')
          return url
        end

        local search_pattern

        if mode == 'v' or mode == 'c' then
          search_pattern = text
        else
          search_pattern = vim.fn.expand('<cword>')
        end

        local search_engine_url = get_search_url_from_engine(options.search_engine)
        return search_engine_url .. urlencode(search_pattern)
      end,
    },
    url = {
      handle = function(text, mode)
        -- get url from text (with http/s)
        local pattern = '(https?://[a-zA-Z%d_/%%%-%.~@\\+#=?&:–]+)'
        local url = helper.find(text, mode, pattern)

        -- match url without http(s)
        if not url then
          pattern = '([a-zA-Z%d_/%-%.~@\\+#]+%.[a-zA-Z_/%%%-%.~@\\+#=?&:–]+)'
          url = helper.find(text, mode, pattern)
          if url then return 'https://' .. url end
        end
        return url
      end,
    },
  },
  search_engine = 'google',
  select_for_search = false,
  git_remotes = { 'upstream', 'origin' },
  git_remote_push = false,
  leave_visual = true,
}

M.setup = function(opts)
  options = vim.tbl_deep_extend('force', opts or {}, options)
  vim.api.nvim_create_user_command('Browse', function(args)
    ---@type string?
    local text = args.fargs[1]
    return M.open(text)
  end, { nargs = '?' })
end

---@type fun(mode: string, leave_visual: boolean): string?
local get_text = function(mode, leave_visual)
  mode = mode or vim.api.nvim_get_mode().mode

  local text = nil
  if mode == 'n' or mode == 'nt' then
    text = vim.api.nvim_get_current_line()
  elseif vim.tbl_contains({ 'v', 'V', '\022' }, mode) then
    text = table
      .concat(vim.fn.getregion(vim.fn.getpos('.'), vim.fn.getpos('v'), { type = vim.fn.mode() }), '\n')
      :gsub('\n', '')
    if leave_visual then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<esc>', true, false, true), 'x', false)
    end
  end
  return text
end

---@return boolean
local is_visual_mode = function(mode) return vim.tbl_contains({ 'v', 'V', '\022' }, mode) end

---@param text string?
---@return nil
M.open = function(text)
  local mode = vim.api.nvim_get_mode().mode
  text = text or get_text(mode, options.leave_visual)
  if not text then return nil end

  -- way better than tbl_filter, since it handle non-list
  local hs = vim.iter(options.handlers):filter(function(_, h)
    if h.filetype and vim.tbl_contains(h.filetype, vim.bo.filetype) then return true end
    if h.filename and vim.api.nvim_buf_get_name(0):match(h.filename) then return true end
    if not h.filetype and not h.filename then return true end
    return false
  end)

  local exists = {}
  ---@type GxSelection[]
  -- iterate each handler to collect the result
  local urls = hs:fold({}, function(urls, name, h)
    local url = h.handle(mode, text)
    if url and not exists[urls] then
      urls[#urls + 1] = { name = name, url = url }
      exists[url] = true
    end
    return urls
  end)

  -- vim.print(urls)
  -- vim.print(#urls)

  local n_urls = #urls
  if n_urls == 0 then return nil end
  if n_urls == 1 then return vim.ui.open(urls[1].url) end

  -- prefer fzf to enable multi-select
  -- local fzf = require("fzf-lua")

  -- fzf.fzf_exec(urls, {})

  vim.ui.select(urls, {
    prompt = 'Multiple patterns match. Select:',
    format_item = function(item) return ('%s (%s)'):format(item.url, item.name) end,
  }, function(selected)
    print(vim.ui.select)
    if not selected then return end
    return vim.ui.open(selected.url)
  end)
end

return M
