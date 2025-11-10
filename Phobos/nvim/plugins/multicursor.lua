-- multi cursors
vim.defer_fn(function()
  local mc = require("multicursor-nvim")
    mc.setup()
    
    vim.keymap.set({"n", "x"}, "<S-c>", function() mc.lineAddCursor(1) end)
    vim.keymap.set({"n", "x"}, "<S-m>", function() mc.matchAddCursor(1) end)
    vim.keymap.set({"n", "x"}, "<C-M>", function() mc.matchSkipCursor(1) end)

    vim.keymap.set("n", "<c-leftmouse>", mc.handleMouse)
    vim.keymap.set("n", "<c-leftdrag>", mc.handleMouseDrag)
    vim.keymap.set("n", "<c-leftrelease>", mc.handleMouseRelease)

    mc.addKeymapLayer(function(layerSet)
      layerSet("n", "<esc>", function()
        if not mc.cursorsEnabled() then
          mc.enableCursors()
        else
          mc.clearCursors()
        end
      end)
    end)
end, 0)
