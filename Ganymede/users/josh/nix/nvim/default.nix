{lib, pkgs, ...}:
{
  home.file.".config/nvim/.vimrc".source = ../../configs/nvim/.vimrc;

  home.activation.mkdirNvimFolders = lib.hm.dag.entryAfter ["writeBoundary"] ''
    mkdir -p $HOME/.config/nvim/backups $HOME/.config/nvim/swaps $HOME/.config/nvim/undo
  '';

  programs.neovim = {
    enable = true;

    extraLuaConfig = lib.fileContents ../../configs/nvim/init.lua;

    plugins = with pkgs.vimPlugins; [
      # UI and Themes
      # =======================================================================
      {
        plugin = gruvbox-nvim;
        type = "lua";
        config = ''
          require("gruvbox").setup({
            overrides = {
              GitSignsAdd    = { link = "GruvboxGreenSign" },
              GitSignsChange = { link = "GruvboxAquaSign" },
              GitSignsDelete = { link = "GruvboxRedSign" },
            }
          })
          vim.cmd("colorscheme gruvbox")
        '';
      }
      {
        plugin = oil-nvim; # Sits on top of netrw to make file actions easy.
        type = "lua";
        config = ''
          require("oil").setup({
            view_options = {
              show_hidden = true
            }
          })
          vim.keymap.set("n", "-", require("oil").open, { desc = "Open parent directory" })
        '';
      }
      {
        plugin = eyeliner-nvim;
        type = "lua";
        config = ''
          require("eyeliner").setup({
            highlight_on_key = true, 
            dim = false,
          })
        '';
      }
      {
        plugin = gitsigns-nvim; # Display git modifications in signcolumn
        type = "lua";
        config = ''
          require('gitsigns').setup({
            signs = {
              add          = { text = '+' },
              change       = { text = '~' },
              delete       = { text = '_' },
              topdelete    = { text = '‾' },
              changedelete = { text = '-' },
              untracked    = { text = '*' },
            },
          })
        '';
      }
      {
        plugin = todo-comments-nvim; # Highlight todo messages
        type = "lua";
        config = ''
        require("todo-comments").setup()
        '';
      }
      {
        plugin = render-markdown-nvim; # Display markdown including docs
        type = "lua";
        config = ''
        require("render-markdown").setup()
        '';
      }
      {
        plugin = telescope-nvim; # UI for pickers
        type = "lua";
        config = ''
          vim.keymap.set('n', '<space>/', "<cmd>lua require('telescope.builtin').live_grep()<cr>", {noremap = true, silent = true, desc = "Live Grep"})
          vim.keymap.set('n', '<space>f', ":lua require('telescope.builtin').find_files({ find_command = {'rg', '--files', '--hidden', '-g', '!.git' }})<cr>", {noremap = true, silent = true, desc = "Live Grep"})
          vim.keymap.set('n', '<space>b', ":lua require('telescope.builtin').buffers()<cr>", {noremap = true, silent = true, desc = "Buffers"})
          vim.keymap.set('n', '<space>z', ":lua require('telescope.builtin').find_files({prompt_title = 'Search ZK', shorten_path = false, cwd = '~/src/wiki'})<cr>", {noremap = true, silent = true, desc = "Wiki"})
        '';
      }
      # Treesitter
      # =======================================================================
      {
        plugin = nvim-treesitter.withAllGrammars; # Treesitter
        type = "lua";
        config = ''
          require'nvim-treesitter.configs'.setup {
            highlight = { enable = true, },
            indent = { enable = true },
          }
        '';
      }
      {
        plugin = nvim-treesitter-textobjects; # helix-style selection of TS tree
        type = "lua";
        config = ''
        require'nvim-treesitter.configs'.setup {
          textobjects = {
            select = {
              enable = true,
              lookahead = true,
              keymaps = {      
                ["af"] = "@function.outer",
                ["if"] = "@function.inner",
                ["ac"] = "@class.outer",
                ["ic"] = "@class.inner",
                ["as"] = { query = "@local.scope", query_group = "locals", desc = "Select language scope" },
              },
            },
            move = {
              enable = true,
              set_jumps = true,
              goto_next = {
                  ["]F"] = "@function.outer",
                  ["]f"] = "@function.inner",
                  ["]C"] = "@class.outer",
                  ["]c"] = "@class.inner",
                  ["]L"] = "@loop.outer",
                  ["]l"] = "@loop.inner",
              },
              goto_previous = {
                  ["[F"] = "@function.outer",
                  ["[f"] = "@function.inner",
                  ["[C"] = "@class.outer",
                  ["[c"] = "@class.inner",
                  ["[L"] = "@loop.outer",
                  ["[l"] = "@loop.inner",
              },
            },
          },
          incremental_selection = {
            enable = true,
            keymaps = {
              init_selection = "<M-o>",
              scope_incremental = "<M-O>",
              node_incremental = "<M-o>",
              node_decremental = "<M-i>",
            },
          },
        }
        '';
      }
      # Utilities and Mini
      # =======================================================================
      {
        plugin = mini-nvim; # Ridiculously complete family of plugins
        type = "lua";
        config = ''
          require('mini.align').setup()      -- aligning
          require('mini.bracketed').setup()  -- unimpaired bindings with TS
          require('mini.comment').setup()    -- TS-wise comments
          require('mini.pairs').setup()      -- pair brackets
          require('mini.statusline').setup({ -- minimal statusline
            use_icons = false,
          })
          require('mini.surround').setup({   -- surround
            custom_surroundings = {
              ['l'] = { output = { left = '[', right = ']()'}}
            }
          })
          require('mini.jump2d').setup({
            mappings = {
              start_jumping = 'G',
            },
          })
          local miniclue = require('mini.clue') -- cute prompts about bindings
          miniclue.setup({                   
            triggers = {
              { mode = 'n', keys = '<Leader>' },
              { mode = 'x', keys = '<Leader>' },
              { mode = 'n', keys = '<space>' },
              { mode = 'x', keys = '<space>' },

              -- Built-in completion
              { mode = 'i', keys = '<C-x>' },

              -- `g` key
              { mode = 'n', keys = 'g' },
              { mode = 'x', keys = 'g' },

              -- Marks
              { mode = 'n', keys = "'" },
              { mode = 'n', keys = '`' },
              { mode = 'x', keys = "'" },
              { mode = 'x', keys = '`' },

              -- Registers
              { mode = 'n', keys = '"' },
              { mode = 'x', keys = '"' },
              { mode = 'i', keys = '<C-r>' },
              { mode = 'c', keys = '<C-r>' },

              -- Window commands
              { mode = 'n', keys = '<C-w>' },

              -- `z` key
              { mode = 'n', keys = 'z' },
              { mode = 'x', keys = 'z' },

              -- Bracketed
              { mode = 'n', keys = '[' },
              { mode = 'n', keys = ']' },
            },
            clues = {
              miniclue.gen_clues.builtin_completion(),
              miniclue.gen_clues.g(),
              miniclue.gen_clues.marks(),
              miniclue.gen_clues.registers(),
              miniclue.gen_clues.windows(),
              miniclue.gen_clues.z(),
            },
            window = {
              delay = 0,
            },
          })
        '';
      }
      targets-vim     # Classic text-objects
      vim-eunuch      # powerful buffer-level file options
      vim-ragtag      # print/execute bindings for template files
      vim-speeddating # incrementing dates and times
      vim-fugitive    # :Git actions
      vim-rhubarb     # github plugins for fugitive
      # LSP and Completion
      # =======================================================================
      cmp-nvim-lsp
      cmp-buffer
      cmp-path
      luasnip
      {
        plugin = nvim-cmp; # Completion engine
        type = "lua";
        config = lib.fileContents ./cmp.lua;
      }
      {
        plugin = nvim-lspconfig; # Interface for LSPs
        type = "lua";
        config = lib.fileContents ./lsp.lua;
      }
    ];
  };
}

