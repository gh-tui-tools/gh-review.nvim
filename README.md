# gh-review.nvim

A Neovim 0.10+ plugin for reviewing GitHub pull requests entirely within Neovim.

Side-by-side diffs, review threads, code suggestions, and review submission — all driven by the `gh` CLI.

Also available for Vim 9.0+: [gh-review.vim](https://github.com/gh-tui-tools/gh-review.vim).

## Goal

This plugin — which is designed for the use case where you’ve already identified a specific PR or PR branch you’re ready to review — has just one single goal:

✅ provide the simplest means possible for performing a GitHub PR review within Neovim

Anything beyond that is a non-goal — for example:

❌ GitHub Issues, Notifications, Discussions, or Actions/Workflows\
❌ Managing labels, assignees, or requested reviewers\
❌ Browsing or searching lists of PRs\
❌ Merging or closing PRs

You are expected to perform those tasks using other tooling (for example, [gh-dash](https://github.com/dlvhdr/gh-dash)).

## Requirements

- Neovim 0.10 or later
- [`gh` CLI](https://cli.github.com), authenticated

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{ "gh-tui-tools/gh-review.nvim" }
```

With Neovim’s built-in package manager:

```sh
mkdir -p ~/.local/share/nvim/site/pack/plugins/start
cd ~/.local/share/nvim/site/pack/plugins/start
git clone https://github.com/gh-tui-tools/gh-review.nvim.git
```

No `setup()` call is required — commands register automatically. Call `setup()`
only if you want to customize keymaps or folding.

## Configuration

`setup()` is optional. These are the defaults:

```lua
require("gh_review").setup({
  fold = { enabled = true, level = 0 },
  keymaps = {
    diff = {
      thread_open  = "gt",
      comment      = "gc",
      suggestion   = "gs",
      next_thread  = "]t",
      prev_thread  = "[t",
      preview      = "K",
      toggle_files = "gf",
      goto_file    = "gF",
      close        = "q",
    },
    files = {
      open          = "<CR>",
      toggle_viewed = "<Space>",
      refresh       = "R",
      toggle_files  = "gf",
      close         = "q",
    },
    thread = {
      submit       = "<C-s>",
      resolve      = "<C-r>",
      close        = "q",
      close_insert = "<C-q>",
    },
  },
})
```

Write only the keys you want to change:

```lua
require("gh_review").setup({
  keymaps = {
    diff  = { preview = false },      -- keep K for LSP hover
    files = { toggle_viewed = "v" },  -- keep <Space> for your leader
  },
  fold = { level = 99 },              -- diff folds, but open on arrival
})
```

### Keymaps

A mapping is either a string, which remaps it, or `false`, which drops it.
Omitted keys keep their defaults. An unrecognized surface, action, or value
type is reported through `vim.notify` and the whole `setup()` call is ignored,
so a typo fails loudly rather than half-applying.

The reply hint in the thread buffer names whichever keys you configured, and
omits any action you disabled.

### Folding

| Value | Effect |
|-------|--------|
| `fold = { enabled = true, level = 0 }` | Default. Diff folding, everything closed. |
| `fold = { enabled = true, level = 99 }` | Diff folding, everything open on arrival. |
| `fold = false` | No fold management at all. |

`fold = false` is shorthand for `fold = { enabled = false }`.

Neovim’s `:diffthis` sets `foldmethod=diff` by itself, so disabling folding
means the plugin actively sets `nofoldenable` once. After that it leaves
folding alone entirely — including declining to restore `foldmethod` if
another plugin changes it, which it does do in the other two modes.

## Workflows

The plugin has two main workflows: A “checkout” workflow, and a “no-checkout” workflow.

### Checkout workflow

Typically used by a project maintainer reviewing a contributor’s PR. The branch is checked out locally so the reviewer can make edits, commit fixes, and push directly.

```vim
:GHReview 123          " PR number (checks out the branch)
:GHReview              " auto-detect from current branch
```

- The right/head diff buffer is editable — `:w` writes to the working tree.
- External file changes are detected and the plugin prompts to reload.
- `git push` pushes changes back to the PR branch (works for fork PRs too).

### No-checkout workflow

Typically used by a non-maintainer reviewer who only needs to read the diff and leave comments.

```vim
:GHReview https://git.example.com/owner/repo/pull/123
```

PR URLs can use the GitHub.com host or a GitHub Enterprise host. The plugin routes API requests to the host in the URL or Git remote. When the URL refers to a different repo than the current working directory, no checkout is attempted. The right/head diff buffer is read-only, but comments, suggestions, and review submission all work normally.

## Quick start

```
:GHReview 123           Open PR #123
<CR>                    Open a file’s side-by-side diff
]t / [t                 Jump between review threads
gt                      View a thread
K                       Preview a thread (floating window)
gc                      Add a comment
gF                      Jump to the file with LSP (checkout only)
:GHReviewSubmit         Submit a review
:GHReviewClose          Close all review buffers
```

## Commands

| Command            | Description                                                   |
|--------------------|---------------------------------------------------------------|
| `:GHReview`        | Open a PR (auto-detect, by number, or by URL)                 |
| `:GHReviewFiles`   | Toggle the changed files list                                 |
| `:GHReviewStart`   | Start a pending review (optional — `:GHReviewSubmit` works without it) |
| `:GHReviewSubmit`  | Submit a review (Comment / Approve / Request changes)         |
| `:GHReviewDiscard` | Discard the pending review and all its pending comments       |
| `:GHReviewClose`   | Close all review buffers and reset state                      |

## Files list mappings

| Key       | Action                                     |
|-----------|--------------------------------------------|
| `<CR>`    | Open the file’s side-by-side diff          |
| `<Space>` | Toggle the file’s reviewed state           |
| `R`       | Refresh review threads from GitHub         |
| `gf`      | Close the files list                       |
| `q`       | Close the files list                       |

## Diff mappings

| Key   | Action                                               |
|-------|------------------------------------------------------|
| `gt`  | Open the review thread at the cursor line             |
| `gc`  | Create a new comment (visual mode: multi-line)        |
| `gs`  | Create a suggestion (right buffer only, visual: range)|
| `]t`  | Jump to the next review thread                        |
| `[t`  | Jump to the previous review thread                    |
| `K`   | Preview the thread at cursor (floating window)        |
| `gf`  | Toggle the files list                                 |
| `gF`  | Go to file at cursor line (checkout only)              |
| `q`   | Close the diff view                                   |

## Thread mappings

| Key      | Action                                        |
|----------|-----------------------------------------------|
| `Ctrl-S` | Submit the reply                              |
| `Ctrl-R` | Toggle resolved/unresolved                    |
| `q`      | Close the thread buffer                       |
| `Ctrl-Q` | Close the thread buffer (works in insert mode)|
| `Ctrl-X Ctrl-O` | Complete `@`-mention from thread participants |

## Signs and virtual text

| Sign | Meaning                          |
|------|----------------------------------|
| `CT` | Comment thread (blue)            |
| `CR` | Resolved thread (green)          |
| `CP` | Pending review comment (yellow)  |

Each sign is accompanied by virtual text at end-of-line showing the first comment’s author and a truncated body — giving at-a-glance context without opening the thread.

Comment reactions are displayed as emoji with counts after each comment body in the thread buffer and floating preview.

## `vim.ui` integration

All prompts (submit review, discard review, checkout, file reload) use `vim.ui.select` and `vim.ui.input`. Plugins like [dressing.nvim](https://github.com/stevearc/dressing.nvim) or [fzf-lua](https://github.com/ibhagwan/fzf-lua) that override these hooks will automatically provide their enhanced UIs.

## Statusline

```lua
require("gh_review").statusline()
```

Returns `""` when no review is active, or a summary like `PR #42 · reviewing · 4 threads`. Use it in lualine, heirline, or any statusline plugin.

## Comparison with other plugins

| Feature                          | gh-review.nvim      | [gh-review.vim][]   | [ghlite.nvim][]     | [gh.nvim][]         | [octo.nvim][]       |
|----------------------------------|---------------------|---------------------|---------------------|---------------------|---------------------|
| **Platform**                     | Neovim 0.10+        | Vim 9.0+            | Neovim 0.10+        | Neovim              | Neovim 0.10+        |
| **PR review: side-by-side diff** | Yes                 | Yes                 | Via diffview.nvim   | Yes                 | Yes                 |
| **PR review: comments/threads**  | Yes                 | Yes                 | Yes                 | Yes                 | Yes                 |
| **PR review: code suggestions**  | Yes                 | Yes                 | No                  | No                  | Yes                 |
| **PR review: submit review**     | Yes                 | Yes                 | Yes                 | Yes                 | Yes                 |
| **PR review: resolve threads**   | Yes                 | Yes                 | No                  | Yes                 | Yes                 |
| **PR review: thread signs**      | Yes (+ virtual text)| Yes (+ virtual text)| As diagnostics      | No                  | No                  |
| **Editable diff buffers**        | Yes                 | Yes                 | No                  | Yes (via checkout)  | No                  |
| **External change detection**    | Yes                 | Yes                 | No                  | No                  | No                  |
| **Fork PR push tracking**        | Yes                 | Yes                 | No                  | Yes                 | No                  |
| **PR listing/browsing**          | No (non-goal)       | No (non-goal)       | Yes                 | Yes                 | Yes                 |
| **Merge PRs**                    | No (non-goal)       | No (non-goal)       | Yes                 | No                  | Yes                 |
| **Labels/assignees/reviewers**   | No (non-goal)       | No (non-goal)       | No                  | No                  | Yes                 |
| **GitHub Issues**                | No (non-goal)       | No (non-goal)       | No                  | Yes                 | Yes                 |
| **Notifications**                | No (non-goal)       | No (non-goal)       | No                  | Yes                 | Yes                 |
| **Discussions**                  | No (non-goal)       | No (non-goal)       | No                  | No                  | Yes                 |
| **Actions/Workflows**            | No (non-goal)       | No (non-goal)       | No                  | No                  | Yes                 |
| **Reactions**                    | No (non-goal)       | No (non-goal)       | No                  | No                  | Yes                 |
| **Dependencies**                 | `gh` CLI            | `gh` CLI            | `gh` CLI            | `gh` CLI, litee.nvim| `gh` CLI, plenary.nvim, picker |

[gh-review.vim]: https://github.com/gh-tui-tools/gh-review.vim
[ghlite.nvim]: https://github.com/daliusd/ghlite.nvim
[gh.nvim]: https://github.com/ldelossa/gh.nvim
[octo.nvim]: https://github.com/pwntester/octo.nvim

## Documentation

See `:help gh-review` for full documentation.

See [DESIGN.md](DESIGN.md) for architecture and implementation details.
