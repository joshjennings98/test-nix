-- nvim-cmp setup
local luasnip = require("luasnip")
local cmp = require("cmp")
cmp.setup {
  preselect = 'none',
  completion = {
    completeopt = "menu,menuone,noinsert,noselect"
  },
  snippet = {
      expand = function(args)
          luasnip.lsp_expand(args.body)
      end,
  },
  mapping = cmp.mapping.preset.insert({
      ["<CR>"] = cmp.mapping.confirm {
          behavior = cmp.ConfirmBehavior.Replace,
          select = false,
      },
      ["<Tab>"] = cmp.mapping(function(fallback)
          if cmp.visible() then
              cmp.select_next_item()
          elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
          else
              fallback()
          end
      end, { "i", "s" }),
      ["<S-Tab>"] = cmp.mapping(function(fallback)
          if cmp.visible() then
              cmp.select_prev_item()
          elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
          else
              fallback()
          end
      end, { "i", "s" }),
  }),
  sources = {
      { name = "nvim_lsp" },
      { name = "luasnip" },
  },
}

