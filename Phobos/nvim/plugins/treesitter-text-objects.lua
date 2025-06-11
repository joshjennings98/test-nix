-- add text objects for treesitter additions
vim.defer_fn(function()
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
        init_selection = "V",
        node_incremental = "V",
        node_decremental = "<M-V>",
      },
    },
  }
end, 0)
