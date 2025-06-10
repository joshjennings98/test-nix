-- Load .vimrc
vim.cmd([[runtime .vimrc]])

-- Neovim specific settings
vim.o.icm = 'split'
vim.opt.foldtext = "v:lua.vim.treesitter.foldtext()"

vim.o.showmode = false


vim.opt.listchars = {
    tab = "│ ",
    trail = " ",
    precedes = " ",
    extends = " ",
    space = " ",
    nbsp = " ",
}

-- Use rg
vim.o.grepprg = [[rg --glob "!.git" --no-heading --vimgrep --follow $*]]
vim.opt.grepformat = vim.opt.grepformat ^ { "%f:%l:%c:%m" }

vim.fn.sign_define("DiagnosticSignError", {text = "E", hl = "DiagnosticSignError", texthl = "DiagnosticSignError", culhl = "DiagnosticSignErrorLine"})
vim.fn.sign_define("DiagnosticSignWarn", {text = "W", hl = "DiagnosticSignWarn", texthl = "DiagnosticSignWarn", culhl = "DiagnosticSignWarnLine"})
vim.fn.sign_define("DiagnosticSignInfo", {text = "I", hl = "DiagnosticSignInfo", texthl = "DiagnosticSignInfo", culhl = "DiagnosticSignInfoLine"})
vim.fn.sign_define("DiagnosticSignHint", {text = "H", hl = "DiagnosticSignHint", texthl = "DiagnosticSignHint", culhl = "DiagnosticSignHintLine"})

-- Make <Tab> work for snippets
vim.keymap.set({ 'i', 's' }, '<Tab>', function()
   if vim.snippet.active({ direction = 1 }) then
     return '<cmd>lua vim.snippet.jump(1)<cr>'
   else
     return '<Tab>'
   end
 end, { expr = true })

-----

-- hide selection highlight on <cr> after search
vim.keymap.set("n", "<cr>", "<cr>:nohlsearch<cr>", { silent = true }) 

-- prefered jumplist keymap 
vim.keymap.set("n", "go", "<C-o>", { silent = true, desc = "Go backward in jumplist" })
vim.keymap.set("n", "gO", "<C-i>", { silent = true, desc = "Go forward in jumplist" })

-- redo with U
vim.keymap.set("n", "U", "<C-r>", { silent = true })

-- toggle undotree
vim.keymap.set("n", "<leader>u", ":UndotreeToggle<cr>", { desc = "Toggle UndoTree" } )

-- move selected lines up and down 
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")

-- keep lines selected after indentation
vim.keymap.set("v", ">", ">gv") 
vim.keymap.set("v", "<", "<gv")

-- keep cursor in place when doing J
vim.keymap.set("n", "J", "mzJ`z") 

-- keep match in middle on search
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")

