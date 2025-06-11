-- fuzzy pickers for nvim
vim.defer_fn(function()
  local actions = require("telescope.actions")
  require("telescope").setup({
      defaults = {
          mappings = {
              i = {
                  ["<esc>"] = actions.close,
              },
          },
          layout_strategy = "horizontal",
          sorting_strategy = "ascending",
          layout_config = {
            horizontal = {
              prompt_position = "top",
              width = { padding = 6 },
              height = { padding = 2 },
              preview_width = 0.5,
            },
          },
      },
  })

  vim.keymap.set('n', '<space>/', "<cmd>lua require('telescope.builtin').live_grep()<cr>", {noremap = true, silent = true, desc = "Live Grep"})
  vim.keymap.set('n', '<space>D', "<cmd>lua require('telescope.builtin').diagnostics()<cr>", {noremap = true, silent = true, desc = "Diagnostics"})
  vim.keymap.set('n', '<space>d', "<cmd>lua require('telescope.builtin').diagnostics({ bufnr=0 })<cr>", {noremap = true, silent = true, desc = "Diagnostics"})
  vim.keymap.set('n', '<space>f', ":lua require('telescope.builtin').find_files({ find_command = {'rg', '--files', '--hidden', '-g', '!.git' }})<cr>", {noremap = true, silent = true, desc = "Live Grep"})
  vim.keymap.set('n', '<space>b', ":lua require('telescope.builtin').buffers()<cr>", {noremap = true, silent = true, desc = "Buffers"})
  vim.keymap.set('n', 'gr', ":lua require('telescope.builtin').lsp_references()<cr>", {noremap = true, silent = true, desc = "LSP References"})
  vim.keymap.set('n', 'gd', ":lua require('telescope.builtin').lsp_definitions()<cr>", {noremap = true, silent = true, desc = "LSP Definitions"})
  vim.keymap.set('n', 'gD', ":lua require('telescope.builtin').lsp_declarations()<cr>", {noremap = true, silent = true, desc = "LSP Declarations"})
  vim.keymap.set('n', 'gi', ":lua require('telescope.builtin').lsp_implementations()<cr>", {noremap = true, silent = true, desc = "LSP Implementations"})
  vim.keymap.set('n', '<space>s', ":lua require('telescope.builtin').lsp_document_symbols()<cr>", {noremap = true, silent = true, desc = "LSP Implementations"})
  vim.keymap.set('n', '<space>S', ":lua require('telescope.builtin').lsp_workspace_symbols()<cr>", {noremap = true, silent = true, desc = "LSP Implementations"})
  vim.keymap.set('n', '<space>u', ":UndotreeToggle<cr>", {noremap = true, silent = true, desc = "Undo tree"})
end, 0)
