-- use x for visual lines (like helix)
vim.keymap.set("n", "x", "V", { noremap = true, silent = true })
vim.keymap.set("x", "x", "<down>", { noremap = true, silent = true })

-- hide selection highlight on <cr> after search
vim.keymap.set("n", "<cr>", "<cr>:nohlsearch<cr>", { silent = true }) 

-- prefered jumplist keymap 
vim.keymap.set("n", "go", "<C-o>", { silent = true, desc = "Go backward in jumplist" })
vim.keymap.set("n", "gO", "<C-i>", { silent = true, desc = "Go forward in jumplist" })

-- redo with U
vim.keymap.set("n", "U", "<C-r>", { silent = true })

-- move selected lines up and down 
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")

-- keep lines selected after indentation
vim.keymap.set("v", ">", ">gv") 
vim.keymap.set("v", "<", "<gv")

-- keep cursor in place when doing J
vim.keymap.set("n", "J", "mzJ`z") 

-- ge to go to end (like helix)
vim.keymap.set("n", "ge", ":$") 

-- keep match in middle on search
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")

-- quickly split windows etc. 
vim.keymap.set("n", "<space>ws", ":wincmd s<cr>", { silent = true, desc = "Split window horizontally" })
vim.keymap.set("n", "<space>wv", ":wincmd v<cr>", { silent = true, desc = "Split window vertically" })
vim.keymap.set("n", "<space>ww", ":wincmd w<cr>", { silent = true, desc = "Go to next window" })
vim.keymap.set("n", "<space>wW", ":wincmd W<cr>", { silent = true, desc = "Go to previous window" })
