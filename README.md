# compile.nvim

An Emacs-style `compile` command for Neovim.

## What it does

- Runs any shell command from `:Compile`
- `<M-x>` key for shortcut.
- Make use of vim wildcards like `:Compile git diff %`
- Opens a transient bottom split for the output
- Closes with `q`
- Re-run the last command with `r` (works only if used inside compile buffer)
- Reopen last executed buffer with `g>`
- Resizes the output window with `+` and `-`
- Jumps to source locations with `<CR>` on parsed error lines

## Usage

Run a command:

```vim
:Compile make
:Compile cargo test
:Compile pytest -q
```

If you omit arguments, the plugin falls back to `&makeprg`.

## Notes

- The output window is reused across runs.
- It parses common `file:line:col:` and `file:line:` style diagnostics.
- Jumping uses the directory the command was launched from.
