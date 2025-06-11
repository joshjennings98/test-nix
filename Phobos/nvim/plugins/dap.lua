-- debug adapter protocol support
vim.defer_fn(function()
local dap = require("dap")
local dapui = require("dapui")

vim.keymap.set("n", "<space>Gc", dap.continue, { desc = "Debug: Start/Continue" })
vim.keymap.set("n", "<space>Gi", dap.step_into, { desc = "Debug: Step Into" })
vim.keymap.set("n", "<space>Gn", dap.step_over, { desc = "Debug: Step Over" })
vim.keymap.set("n", "<space>Go", dap.step_out, { desc = "Debug: Step Out" })
vim.keymap.set("n", "<space>Gt", dap.terminate, { desc = "Debug: Terminate" })
vim.keymap.set("n", "<space>Gb", dap.toggle_breakpoint, { desc = "Toggle breakpoint"})
vim.keymap.set("n", "<space>GB", function()
  dap.set_breakpoint(vim.fn.input "Breakpoint condition: ")
end, { desc = "Toggle breakpoint (condition)" })

dapui.setup({
    icons = { current_frame = ">", expanded = "+", collapsed = "-" },
    controls = {
        icons = {
            pause = "pause",
            play = "play",
            step_into = "into",
            step_over = "over",
            step_out = "out",
            step_back = "back",
            run_last = "last",
            terminate = "stop",
            disconnect = "exit",
        },
    },
})

dap.listeners.after.event_initialized["dapui_config"] = dapui.open
dap.listeners.before.event_terminated["dapui_config"] = dapui.close
dap.listeners.before.event_exited["dapui_config"] = dapui.close

require("dap-go").setup()

require("nvim-dap-virtual-text").setup({
  highlight_changed_variables = false,
  commented = true,
  virt_text_pos = 'eol',
})
end, 0)
