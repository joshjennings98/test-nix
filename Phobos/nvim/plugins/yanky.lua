-- better clipboard support
vim.defer_fn(function()
  local yanky = require("yanky")
  local utils = require("yanky.utils")
  local mapping = require("yanky.telescope.mapping")
  yanky.setup({
    highlight = {
      on_put = false,
      on_yank = false,
    },
    picker = {
      telescope = {
        mappings = {
          default = mapping.set_register(utils.get_default_register()),
        },
      },
    },
  })
  require("telescope").load_extension("yank_history")
  vim.keymap.set("n", "<space>y", 
    function() 
      require("telescope").extensions.yank_history.yank_history()
    end, 
    { desc = "Open clipboard picker" }
  )
end, 0)
