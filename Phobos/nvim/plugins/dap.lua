-- debug adapter protocol support
vim.defer_fn(function()
  local dap = require("dap")
  require("dap-go").setup()
  require("dap-view").setup({
    winbar = {
      controls = { enabled = true }
    },
    auto_toggle = true,
  })

  local opts = { silent = true, noremap = true }

  vim.keymap.set("n", "<space>Gb", dap.toggle_breakpoint,
    vim.tbl_extend("force", opts, { desc = "DAP: Toggle breakpoint" }))

  vim.keymap.set("n", "<space>GB", function()
    vim.ui.input({ prompt = "Breakpoint condition: " }, function(cond)
      if cond then dap.set_breakpoint(cond) end
    end)
  end, vim.tbl_extend("force", opts, { desc = "DAP: Set conditional breakpoint" }))

  vim.keymap.set("n", "<space>Gc", ":DapContinue<cr>",
    vim.tbl_extend("force", opts, { desc = "DAP: Start debugging" }))

end, 0)

