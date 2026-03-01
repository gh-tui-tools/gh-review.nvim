# Jump to file from diff view

GitHub issue: https://github.com/gh-tui-tools/gh-review.nvim/issues/2

## Summary

In local-checkout reviews, pressing `gF` in the right diff buffer closes the
diff view and opens the corresponding working-tree file at the current cursor
line. This lets users inspect code with full LSP support.

## Decisions

- **Keybinding:** `gF` (uppercase variant of `gf` which toggles the files list)
- **Diff cleanup:** the diff view closes; no back-navigation
- **Side:** right buffer only (the left buffer shows the base revision, which
  has no working-tree counterpart)
- **Guard:** only available in local-checkout reviews (`is_local_checkout`)

## Implementation

New function `M.goto_file()` in `diff.lua`:

1. Guard: cursor must be in the right buffer and `is_local_checkout` must be
   true. Print a message otherwise.
2. Capture `vim.fn.line(".")` and `state.get_diff_path()`.
3. Call `close_diff()` (handles all cleanup: guard flags, left window close,
   diffoff, state reset).
4. In the remaining window, `:edit <path>` and set cursor to the saved line.

Keybinding added in `setup_keymaps()` alongside existing `gf`, `gt`, etc.

Help text updated to document `gF`.
