# gh-review.nvim Design

## Overview

gh-review.nvim is a Neovim 0.10+ plugin for reviewing GitHub pull requests entirely within Neovim. It is the Neovim counterpart to [gh-review.vim](https://github.com/gh-tui-tools/gh-review.vim); the two plugins share a common design, each implemented idiomatically for its editor. gh-review.nvim provides side-by-side diffs, review thread viewing and commenting, commit suggestions, and review submission — all driven by the `gh` CLI and the GitHub GraphQL/REST APIs.

### Scope

The goal of this plugin is to provide the simplest means possible for performing GitHub PR reviews. Anything beyond that is a non-goal — for example, providing any means for dealing with GitHub Issues, Notifications, Discussions, or Actions/Workflows, or even providing any means for other PR-related tasks such as browsing lists of PRs or managing labels, assignees, or requested reviewers. The user is expected to perform those tasks using other tooling.

This plugin is intentionally targeted at the use case where a user has already identified a specific PR or PR branch they are ready to review.

### Shared design

[gh-review.nvim](https://github.com/gh-tui-tools/gh-review.nvim) and [gh-review.vim](https://github.com/gh-tui-tools/gh-review.vim) are parallel implementations of a single design, each using its editor’s native APIs. The UX features — virtual text indicators, floating thread preview, help discovery, better prompts, a statusline component, `@`-mention completion, and a context bar — were designed once and implemented in both plugins simultaneously.

Where they differ is in the APIs they call, not in what the user sees:

| Feature | Neovim | Vim |
|---------|--------|-----|
| Thread indicators | Extmarks with `virt_text` | `prop_add()` virtual text |
| Signs | Extmarks with `sign_text` | `sign_define`/`sign_place` |
| Floating preview | `nvim_open_win(relative=“cursor”)` | `popup_atcursor()` |
| Keymap discovery | `desc` fields (which-key.nvim) | `g?` popup help card |
| Prompts | `vim.ui.select`, `vim.ui.input` | `popup_menu()`, `confirm()` |
| Context bar | `vim.wo.winbar` | Window-local `&statusline` |
| Async | `vim.system()` + `vim.schedule()` | `job_start()` + `timer_start(0, ...)` |
| Omnifunc | Module-local function | Global `def g:GHReviewThreadOmnifunc()` |

### Dependencies

The plugin uses only what Neovim 0.10 provides out of the box — no treesitter, no LSP, no picker plugins, no UI frameworks, no async libraries. The sole external dependency is the `gh` CLI. Diff buffers use `syntax=` (not `filetype=`) specifically to avoid triggering FileType autocmds that would attach LSP clients, linters, and treesitter highlighting to ephemeral review buffers. This is a deliberate choice to keep both the implementation and the user experience as minimal and straightforward as possible — just what’s needed to get the job done.

## Workflows

The plugin is designed around two main workflows that reflect different user roles and intent.

### Checkout workflow

The user is in a clone of the PR’s repo (or has already checked out the PR branch). They run `:GHReview` with no argument, `:GHReview <number>`, or `:GHReview <URL>` where the URL refers to the same repo.

- If the user is already on the PR branch (detected by comparing the current branch name against the PR’s head ref), the plugin skips straight to loading the UI with no checkout prompt.
- If the user is on a different branch but the repo matches, the plugin prompts: “Check out branch feature-x? (Y/n)”. On “Yes”, the branch is fetched via `git fetch origin pull/N/head` and checked out with `git checkout -B`. Push tracking is configured automatically (origin for same-repo PRs; a new remote for fork PRs, matching the SSH/HTTPS protocol of origin).
- If the user declines the checkout, or the checkout fails (e.g., dirty working tree), the plugin falls back to the no-checkout workflow below.
- When checked out, the right/head diff buffer is **editable** — the user can modify files locally and save with `:w`, which writes directly to the working tree. The user can `git push` to push changes back to the PR branch.

### No-checkout workflow

The user may not be in the repo’s clone directory at all, or may be reviewing a PR from a different repo. They run `:GHReview <URL>` where the URL refers to a different repo than the current working directory. This workflow also activates as a fallback when the user declines a checkout or when a checkout fails.

- The plugin detects that the URL’s owner/repo does **not** match the local origin remote (or there is no git repo at all). No checkout is offered or attempted.
- All diff content is fetched via `git show` (falling back to GraphQL blob queries if the ref is not available locally).
- The right/head diff buffer is **read-only** (`buftype=nofile`, `nomodifiable`).
- The user can still add comments, commit suggestions, and manage reviews through the GitHub API.

The checkout workflow is typically used by a project maintainer reviewing a contributor’s PR — they check out the branch so they can make edits, commit fixes, and push directly. The no-checkout workflow is more typical of a non-maintainer reviewer who only needs to read the diff and leave comments.

### What differs between the workflows

| Capability                       | Checkout        | No checkout |
|----------------------------------|-----------------|-------------|
| Right/head buffer                | Editable (`buftype=acwrite`) | Read-only |
| `:w` writes to working tree      | Yes             | No          |
| External change detection        | Yes (mtime tracking) | N/A    |
| Push changes to PR branch        | Yes (`git push`) | No         |
| Add review comments              | Yes             | Yes         |
| Commit suggestions (`gs`)        | Yes             | Yes         |
| Resolve/unresolve threads        | Yes             | Yes         |
| Start/submit/discard reviews     | Yes             | Yes         |

The `state.is_local_checkout()` flag controls this distinction. It is set to `true` when the branch is checked out (or was already checked out), and `false` otherwise. `setup_diff_buffer()` checks this flag to decide whether the right buffer is editable or read-only.

## Architecture

### Module structure

```
plugin/gh_review.lua          Entry point: commands, highlights, fold guard
lua/gh_review/
  init.lua                    Top-level orchestration (open, close, review lifecycle)
  api.lua                     Async wrapper around the gh CLI
  graphql.lua                 GraphQL query/mutation constants
  state.lua                   Centralized state management
  files.lua                   Changed files list buffer
  diff.lua                    Side-by-side diff view with extmarks and virtual text
  thread.lua                  Thread/comment buffer for viewing and replying
syntax/
  gh-review-files.vim         Syntax highlighting for the files list
  gh-review-thread.vim        Syntax highlighting for the thread buffer
```

### State management (`state.lua`)

All plugin state lives in module-local variables in `state.lua`, accessed through exported getter/setter functions. This includes:

- **PR metadata**: id, number, title, state, base/head refs and OIDs, head repository owner/name (guarded against `vim.NIL` for deleted forks), merge base OID.
- **Repo info**: owner and name, detected from `git remote get-url origin` or provided via URL argument.
- **Changed files**: list of tables with path, additions, deletions, changeType.
- **Review threads**: indexed by thread ID in a table. Threads are the central data structure — they drive sign placement, files list thread counts, and the thread buffer content.
- **Buffer/window IDs**: files list, left diff, right diff, thread buffer and window.
- **UI state**: current diff path, local checkout flag, pending review ID.

An `ns` namespace (via `nvim_create_namespace`) is exported for extmarks used by `diff.lua` for sign placement and virtual text.

`get_participants()` extracts unique, sorted `author.login` values from all thread comments, used by the thread buffer’s omnifunc for `@`-mention completion.

A `get(t, key, default)` helper handles `vim.NIL` (which `vim.json.decode()` produces for JSON null) by treating it as equivalent to `nil` when checking for missing values.

`reset()` clears everything, called by `:GHReviewClose`.

### Async API layer (`api.lua`)

All external commands run asynchronously via `vim.system()`:

- **`run_cmd_async(cmd, callback)`**: runs an arbitrary command. Callback receives `(stdout, stderr, exit_status)`.
- **`run_async(cmd, callback)`**: prepends `"gh"` to the command. Callback receives `(stdout, stderr)`.
- **`graphql(query, variables, callback)`**: builds the `gh api graphql` command with `-f`/`-F` flags (string vs. JSON), runs it, parses the response, checks for GraphQL errors, and calls back with the parsed table.

All callbacks are wrapped in `vim.schedule()` to ensure Neovim API calls run on the main thread (required by Neovim’s event loop — calling `nvim_*` functions from a `vim.system()` on_exit callback without scheduling would error).

### GraphQL queries (`graphql.lua`)

Constants for all API operations, using `[[ ]]` multiline string literals:

- `QUERY_PR_DETAILS`: fetches PR metadata, files (first 100), review threads (first 100) with comments (first 50), and pending reviews.
- `QUERY_REVIEW_THREADS`: lighter query for refreshing threads only.
- Mutations for: starting a review, submitting a review, creating and submitting a review in one step, adding a thread, replying to a thread, resolving/unresolving threads, deleting a review.

### Opening a PR (`init.lua: open()`)

The `open()` function orchestrates the full startup sequence:

1. **Parse input**: accepts a PR number, a full GitHub PR URL, or nothing (auto-detect from current branch via `gh pr view`). URLs are parsed with Lua patterns to extract owner, repo name, and PR number.

2. **Determine repo**: if a URL specifies a repo, use it; otherwise detect from `git remote get-url origin`. Sets `should_checkout` based on whether the URL’s repo matches the local origin.

3. **Fetch PR details**: GraphQL query for metadata, files, threads. Response is validated before use (guards against missing/empty data).

4. **Checkout decision**:
   - If already on the PR branch — skip straight to loading the UI.
   - If local repo matches — prompt to check out.
   - If different repo or user declines — set `is_local_checkout = false`.

5. **Checkout sequence** (when proceeding):
   - `git fetch origin pull/N/head` (via `run_cmd_async`)
   - `git checkout -B <branch> FETCH_HEAD` (via `run_cmd_async`)
   - `setup_push_tracking()` configures the branch’s remote and merge ref.
   - `load_ui()` is called only **after** checkout completes (or fails), not in parallel with it.

6. **Load UI**: `fetch_merge_base()` then `files.open()`.

### Merge base resolution (`fetch_merge_base()`)

Determines the correct merge base for accurate diffs:

1. Try `git merge-base origin/<base> origin/<head>` locally.
2. If that fails, fall back to the REST API compare endpoint.
3. If both fail, use the base OID as a last resort (with a warning that the diff may be inaccurate).

Doing this after checkout is intentional — the fetch brings down the refs, making the local `git merge-base` more likely to succeed.

### Push tracking (`setup_push_tracking()`)

Configures `git push` to work correctly after checkout:

- **Same-repo PRs**: sets the branch’s remote to `origin`.
- **Fork PRs**: adds a remote for the fork (named after the fork owner), matching the SSH/HTTPS protocol of `origin`. Sets the branch’s remote to the fork remote and merge ref to the fork’s branch.

Each git command checks exit status and warns on failure.

### Files list (`files.lua`)

A bottom split showing changed files with diff stats and thread counts:

```
https://github.com/owner/repo/pull/123: Fix the widget
Files changed (3)

  +12 -3   M  src/main.rs         [2 threads]
  +45 -0   A  src/new_file.rs
  +0  -22  D  src/old_file.rs
```

- Opens in a `botright` split, 12 lines high, with `winfixheight`.
- Buffer type is `nofile` with `bufhidden=hide` (content survives when the window is closed and reopened via toggle).
- `<CR>` opens the side-by-side diff for the file under the cursor.
- `R` refreshes threads from GitHub and rerenders.
- `q` / `gf` closes the files list.
- When the files list closes, `wincmd =` equalizes window heights, then a scroll nudge (`Ctrl-E` / `Ctrl-Y`) in each diff window forces scrollbind viewports to update.

### Side-by-side diff (`diff.lua`)

Two vertically split buffers in Neovim’s native diff mode:

- **Left buffer** (`gh-review://LEFT/<path>`): base version at the merge base commit. Always read-only.
- **Right buffer** (`gh-review://RIGHT/<path>`): head version at the PR’s head commit. Editable when `is_local_checkout` is true; read-only otherwise.

#### Content fetching

File content is fetched asynchronously, with a two-step fallback:

1. `git show <ref>:<path>` via `vim.system()` (fast, works when refs are available locally).
2. GraphQL blob query via the GitHub API (works for cross-repo reviews where refs aren’t local).

Both sides are fetched in parallel. `show_diff()` is called via `vim.schedule()` once both complete.

#### Editable buffers (checkout workflow)

When `is_local_checkout` is true, the right buffer is set up with:

- `buftype=acwrite` — Neovim delegates `:w` to the `BufWriteCmd` autocmd.
- `BufWriteCmd` calls `write_buffer()`, which:
  - Writes buffer content to the working tree via `vim.fn.writefile()`.
  - Updates the stored mtime to prevent false external-change detection.
  - Echoes a confirmation message matching Neovim’s native format.
- `FocusGained` / `BufEnter` / `CursorHold` autocmds call `check_external_change()`, which:
  - Compares the file’s current mtime against the stored mtime.
  - If changed, prompts the user to reload.
  - On reload, updates buffer content, runs `diffupdate`, and redraws.

#### Syntax highlighting

`setup_diff_buffer()` sets `syntax=<lang>` based on the file extension, using `syntax=` instead of `filetype=` to avoid triggering FileType autocmds (which would cause LSP/linter plugins to attach). A map covers common extensions; unrecognized extensions fall through to the extension name itself.

#### Concealing

Syntax concealing (e.g., hiding markdown link URLs) works when `conceallevel` is set and the syntax file defines `conceal` rules. However, both Vim and Neovim have a rendering bug where `foldmethod=diff` with closed folds prevents concealing from rendering on visible lines — even though the conceal rules are active and `conceallevel` is set (vim/vim#19423, neovim/neovim#37893).

`show_diff()` works around this by deferring a fold cycle after the initial render: open all folds (`zR`), force a `redraw`, then re-close all folds (`zM`). The redraw between open and close is essential — without it, the workaround has no effect. This runs via `vim.defer_fn(..., 50)` to let the initial diff render complete first.

#### Fold guard

Plugins (LSP, linters) may asynchronously override `foldmethod` on diff buffers. A global `OptionSet` autocmd in `plugin/gh_review.lua` restores `foldmethod=diff` whenever it changes on buffers marked with `vim.b.gh_review_diff`.

#### Extmarks and virtual text

Review threads are indicated via extmarks (replacing the legacy `sign_define`/`sign_place` API):

- `CT` (blue, `GHReviewThread`) — normal thread (last comment state is `COMMENTED`).
- `CR` (green, `GHReviewThreadResolved`) — resolved thread.
- `CP` (yellow, `GHReviewThreadPending`) — thread with a pending review comment.

Each extmark also carries virtual text at end-of-line showing the first comment’s author and a truncated body (up to 60 characters), highlighted with `GHReviewVirtText` (dim italic). This gives at-a-glance context without opening the thread.

`place_signs()` iterates threads for the current file and places extmarks on the appropriate side (left or right buffer) at the thread’s line number. For outdated threads where `line` is null, it falls back to `originalLine`.

`refresh_signs()` clears the namespace and replaces all extmarks for the current diff path.

#### Floating thread preview

The `K` keymap opens a floating window (`nvim_open_win` with `relative="cursor"`, `border="rounded"`) showing the full thread content at the cursor line. The preview is read-only and closes on `q`, `<Esc>`, or `BufLeave`. Only one preview can be open at a time. This is lighter than `gt` — no split, no reply area.

#### Winbar

Both diff windows display a winbar showing `PR #N · path · base/head (short OID)`, providing persistent context about what’s being reviewed.

#### Keymaps

All keymaps include `desc` fields, making them discoverable via which-key.nvim and `:map`.

| Key   | Action                                              |
|-------|-----------------------------------------------------|
| `gt`  | Open thread at cursor line                          |
| `gc`  | Create new comment (visual mode: multi-line)        |
| `gs`  | Create suggestion (right buffer only, visual: range) |
| `]t`  | Jump to next thread sign                            |
| `[t`  | Jump to previous thread sign                        |
| `K`   | Preview thread at cursor (floating window)          |
| `gf`  | Toggle the files list                               |
| `q`   | Close the diff view                                 |

### Thread buffer (`thread.lua`)

A horizontal split at the bottom for viewing and replying to threads:

```
Thread on src/main.rs:42  [Active]
────────────────────────────────────────────────────────────
  42 + │ let x = foo();
────────────────────────────────────────────────────────────

alice (2025-01-15):
  Looks good

── Reply below (Ctrl-S to submit, Ctrl-R to resolve, Ctrl-Q to cancel) ──

```

#### Layout

- Opens in a `botright` split, 15 lines high, with `winfixheight`.
- The header area (everything above the reply separator) is **read-only**, enforced by a `CursorMoved`/`CursorMovedI` autocmd that toggles `nomodifiable` based on cursor position relative to `vim.b.gh_review_reply_start`.
- The reply area (below the separator) is editable.
- Buffer type is `acwrite` so `:w` submits the reply.

#### Code context

The thread buffer shows the code line(s) being commented on, pulled from the left or right diff buffer depending on the thread’s `diffSide`. Lines are prefixed with `+` (right/head) or `-` (left/base) and the line number. Multi-line threads show the full range from `startLine` to `line`.

#### Submitting replies

Three paths depending on context:

1. **New thread**: `addPullRequestReviewThread` mutation. If a pending review is active, the thread is attached to it.
2. **Reply with active review**: `addPullRequestReviewComment` mutation using the pending review ID.
3. **Standalone reply** (no pending review): first tries the REST API (`POST .../comments/<id>/replies`). If that fails (e.g., node ID not accepted), falls back to creating a temporary review, adding the comment, and immediately submitting it as `COMMENT`.

#### Keymaps

| Key      | Action                                       |
|----------|----------------------------------------------|
| `Ctrl-S` | Submit reply (works in normal and insert mode) |
| `Ctrl-R` | Toggle resolved/unresolved                   |
| `q`      | Close thread buffer                          |
| `Ctrl-Q` | Close thread buffer (works in insert mode)   |

#### @-mention completion

The thread buffer sets `omnifunc` to a custom function that completes `@`-mentions from thread participants. `state.get_participants()` provides the candidate list. Users trigger completion with `Ctrl-X Ctrl-O` (standard Neovim omni-completion).

### Statusline component

`require("gh_review").statusline()` returns an empty string when no review is active, or a summary like `PR #42 · reviewing · 4 threads`. Users can integrate this into their statusline plugin (lualine, heirline, etc.).

### `vim.ui.select` / `vim.ui.input`

All user prompts (submit review action, review body, discard confirmation, checkout confirmation, external file change reload) use `vim.ui.select` and `vim.ui.input` instead of `vim.fn.inputlist()` / `vim.fn.input()`. This means plugins like dressing.nvim or fzf-lua that override `vim.ui` hooks will automatically provide their enhanced UIs for these prompts.

### Review lifecycle

- **`:GHReviewStart`**: creates a pending review via `addPullRequestReview`. All subsequent comments and replies are attached to this review. This is optional — `:GHReviewSubmit` works without it.
- **`:GHReviewSubmit`**: prompts for action (Comment / Approve / Request changes) and optional body. If a pending review is active, submits it via `submitPullRequestReview`. If no pending review exists, creates and submits a review in one step via `addPullRequestReview` with an `event` parameter.
- **`:GHReviewDiscard`**: prompts for confirmation, then deletes the pending review and all its pending comments via `deletePullRequestReview`.

If a pending review already exists on the PR (from a previous session or the GitHub web UI), it is detected during `set_pr()` and reused.

### Window management

Closing the files list or thread buffer frees vertical space. The plugin:

1. Calls `wincmd =` to equalize window heights.
2. Visits each diff window and performs a scroll nudge (`Ctrl-E` / `Ctrl-Y`) to force Neovim to recompute the visible area in scrollbind/diff mode. Without this nudge, the viewport shows blank space where the closed window was.

`:GHReviewClose` tears down everything: closes the thread buffer, diff view, and files list; wipes all `gh-review://` buffers; resets state.

## Testing

Tests run in headless Neovim (`nvim --clean --headless`) and use a custom `run_test()` harness that wraps each test function in `pcall()` to capture errors. Test files:

| File                  | Coverage                                              |
|-----------------------|-------------------------------------------------------|
| `test_state.lua`      | State setters/getters, set_pr, threads, reset, get_participants |
| `test_diff_logic.lua` | Extmark placement, sign types, mtime tracking         |
| `test_ui.lua`         | Files list rendering, toggle, close, keymaps          |
| `test_thread.lua`     | Thread buffer rendering, metadata, close, omnifunc    |
| `test_navigation.lua` | Extmark placement across sides, refresh, edge cases   |
| `test_graphql.lua`    | GraphQL constant structure validation                 |
| `test_open.lua`       | URL/number parsing                                    |

Headless Neovim constraints:
- `startinsert` crashes in headless mode; tests pass body content directly to `open_new()` instead.
- `vim.o.hidden = true` is needed so tests can switch away from modified buffers without triggering E37.
- `bufhidden=hide` is needed to keep buffer content alive when switching windows.
