-- Refactoring plugin
vim.defer_fn(function()
    require("telescope").load_extension("refactoring")
    require('refactoring').setup({
        prompt_func_return_type = {
            go = true,
        },
        prompt_func_param_type = {
            go = true,
        },
        show_success_message = true,
        print_var_statements = {
            go = {
                'fmt.Printf("!!!! DEBUG: %s %%+v\\n", %s)'
            }
        }
    })

    vim.keymap.set("n", "<space>pP",
        function() 
            require("refactoring").debug.printf({below = false}) 
        end,
        { desc = "Debug print to mark function reached this point" }
    )

    vim.keymap.set({"x", "n"}, "<space>pp", 
        function() 
            require("refactoring").debug.print_var() 
        end,
        { desc = "Debug print variable" }
    )

    vim.keymap.set("n", "<space>pc", 
        function() 
            require("refactoring").debug.cleanup({}) 
        end,
        { desc = "Debug cleanup" }
    )

    require("telescope").load_extension("refactoring")

    vim.keymap.set({"n", "x"}, "<space>R", function()
        require('telescope').extensions.refactoring.refactors()
    end, { desc = "Refactoring options" })
end, 0)
