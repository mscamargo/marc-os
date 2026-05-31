-- Single-file Neovim config, kickstart-style.
-- See https://github.com/nvim-lua/kickstart.nvim for the upstream reference.

vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- ---------- options ----------
local opt = vim.opt
opt.number = true
opt.relativenumber = true
opt.expandtab = true
opt.shiftwidth = 4
opt.tabstop = 4
opt.smartindent = true
opt.wrap = false
opt.termguicolors = true
opt.mouse = 'a'
opt.clipboard = 'unnamedplus'
opt.ignorecase = true
opt.smartcase = true
opt.signcolumn = 'yes'
opt.updatetime = 250
opt.timeoutlen = 300
opt.splitright = true
opt.splitbelow = true
opt.scrolloff = 8
opt.undofile = true
opt.completeopt = { 'menu', 'menuone', 'noselect' }

-- ---------- keymaps ----------
local map = vim.keymap.set
map('n', '<leader>w', '<cmd>w<cr>', { desc = 'Write' })
map('n', '<leader>q', '<cmd>q<cr>', { desc = 'Quit' })
map('n', '<Esc>', '<cmd>nohlsearch<cr>')
map('n', '<C-h>', '<C-w>h')
map('n', '<C-j>', '<C-w>j')
map('n', '<C-k>', '<C-w>k')
map('n', '<C-l>', '<C-w>l')

-- ---------- lazy.nvim bootstrap ----------
local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    'git', 'clone', '--filter=blob:none', '--branch=stable',
    'https://github.com/folke/lazy.nvim.git', lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require('lazy').setup({
  -- Colorscheme
  {
    'folke/tokyonight.nvim',
    priority = 1000,
    config = function()
      vim.cmd.colorscheme('tokyonight-night')
    end,
  },

  -- Git signs in the gutter
  { 'lewis6991/gitsigns.nvim', opts = {} },

  -- which-key
  { 'folke/which-key.nvim', event = 'VimEnter', opts = {} },

  -- Telescope (fuzzy finder)
  {
    'nvim-telescope/telescope.nvim',
    branch = '0.1.x',
    dependencies = {
      'nvim-lua/plenary.nvim',
      { 'nvim-telescope/telescope-fzf-native.nvim', build = 'make' },
    },
    config = function()
      local t = require('telescope')
      t.setup({})
      pcall(t.load_extension, 'fzf')
      local b = require('telescope.builtin')
      map('n', '<leader>sf', b.find_files, { desc = 'Search files' })
      map('n', '<leader>sg', b.live_grep,  { desc = 'Search grep' })
      map('n', '<leader>sb', b.buffers,    { desc = 'Search buffers' })
      map('n', '<leader>sh', b.help_tags,  { desc = 'Search help' })
      map('n', '<leader>sd', b.diagnostics, { desc = 'Search diagnostics' })
    end,
  },

  -- Treesitter
  {
    'nvim-treesitter/nvim-treesitter',
    build = ':TSUpdate',
    opts = {
      ensure_installed = {
        'bash', 'lua', 'vim', 'vimdoc', 'python', 'go', 'rust',
        'javascript', 'typescript', 'tsx', 'json', 'yaml', 'toml',
        'html', 'css', 'ruby', 'markdown', 'markdown_inline',
      },
      auto_install = true,
      highlight = { enable = true },
      indent = { enable = true },
    },
    config = function(_, opts)
      require('nvim-treesitter.configs').setup(opts)
    end,
  },

  -- LSP
  {
    'neovim/nvim-lspconfig',
    dependencies = {
      { 'williamboman/mason.nvim', config = true },
      'williamboman/mason-lspconfig.nvim',
      'WhoIsSethDaniel/mason-tool-installer.nvim',
      { 'j-hui/fidget.nvim', opts = {} },
    },
    config = function()
      local servers = {
        lua_ls = {
          settings = {
            Lua = {
              diagnostics = { globals = { 'vim' } },
              workspace = { checkThirdParty = false },
              telemetry = { enable = false },
            },
          },
        },
        gopls = {},
        pyright = {},
        ts_ls = {},
        rust_analyzer = {},
        solargraph = {},
      }

      require('mason').setup()
      require('mason-tool-installer').setup({
        ensure_installed = vim.tbl_keys(servers),
      })
      require('mason-lspconfig').setup({
        handlers = {
          function(name)
            local cfg = servers[name] or {}
            require('lspconfig')[name].setup(cfg)
          end,
        },
      })

      vim.api.nvim_create_autocmd('LspAttach', {
        callback = function(ev)
          local bmap = function(lhs, rhs, desc)
            map('n', lhs, rhs, { buffer = ev.buf, desc = desc })
          end
          bmap('gd', vim.lsp.buf.definition, 'Goto definition')
          bmap('gr', vim.lsp.buf.references, 'Goto references')
          bmap('K',  vim.lsp.buf.hover, 'Hover')
          bmap('<leader>rn', vim.lsp.buf.rename, 'Rename')
          bmap('<leader>ca', vim.lsp.buf.code_action, 'Code action')
          bmap('<leader>e',  vim.diagnostic.open_float, 'Diagnostic float')
        end,
      })
    end,
  },

  -- Completion
  {
    'hrsh7th/nvim-cmp',
    event = 'InsertEnter',
    dependencies = {
      'L3MON4D3/LuaSnip',
      'saadparwaiz1/cmp_luasnip',
      'hrsh7th/cmp-nvim-lsp',
      'hrsh7th/cmp-path',
      'hrsh7th/cmp-buffer',
    },
    config = function()
      local cmp = require('cmp')
      local luasnip = require('luasnip')
      cmp.setup({
        snippet = { expand = function(args) luasnip.lsp_expand(args.body) end },
        mapping = cmp.mapping.preset.insert({
          ['<C-Space>'] = cmp.mapping.complete(),
          ['<CR>']      = cmp.mapping.confirm({ select = true }),
          ['<Tab>']     = cmp.mapping.select_next_item(),
          ['<S-Tab>']   = cmp.mapping.select_prev_item(),
        }),
        sources = cmp.config.sources({
          { name = 'nvim_lsp' },
          { name = 'luasnip' },
          { name = 'path' },
        }, {
          { name = 'buffer' },
        }),
      })
    end,
  },
})
