local function completion(arglead, cmdline, cursorpos)
    local before = cmdline:sub(1, cursorpos)
    local parts = vim.split(before, "%s+")
    local argn = #parts - 1

    if argn == 1 then
        return vim.fn.getcompletion(arglead, "shellcmd")
    else
        return vim.fn.getcompletion(arglead, "file")
    end
end

local function get_compile()
    return require("compile")
end

vim.api.nvim_create_user_command("Compile", function(opts)
    get_compile().run(opts.args)
end, {
    force = true,
    nargs = "*",
    complete = completion,
    desc = "Run a shell command and show the output in a compile window",
})

vim.api.nvim_create_user_command("CompileReload", function()
    get_compile().reload()
end, {
    force = true,
    desc = "Reload compile.nvim and reset its runtime state",
})

vim.keymap.set("n", "<M-x>", ":Compile ")
vim.keymap.set("n", "g>", function() get_compile().openLast() end)
