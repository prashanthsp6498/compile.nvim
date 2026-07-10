local compile = require("compile")

vim.api.nvim_create_user_command("Compile", function(opts)
  compile.run(opts.args)
end, {
  nargs = "*",
  complete = "shellcmd",
  desc = "Run a shell command and show the output in a compile window",
})

vim.keymap.set("n", "<M-x>", ":Compile ")
