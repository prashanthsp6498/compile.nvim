local function get_compile()
  return require("compile")
end

vim.api.nvim_create_user_command("Compile", function(opts)
  get_compile().run(opts.args)
end, {
  force = true,
  nargs = "*",
  complete = "shellcmd",
  desc = "Run a shell command and show the output in a compile window",
})

vim.api.nvim_create_user_command("CompileReload", function()
  get_compile().reload()
end, {
  force = true,
  desc = "Reload compile.nvim and reset its runtime state",
})

vim.keymap.set("n", "<M-x>", ":Compile ")
