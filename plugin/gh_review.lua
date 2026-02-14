-- gh-review.nvim -- GitHub PR code review plugin for Neovim 0.10+

if vim.g.loaded_gh_review then
  return
end
vim.g.loaded_gh_review = true

if vim.fn.has("nvim-0.10") ~= 1 then
  vim.notify("gh-review.nvim requires Neovim 0.10+", vim.log.levels.ERROR)
  return
end

-- Commands
vim.api.nvim_create_user_command("GHReview", function(opts)
  require("gh_review").open(opts.args)
end, { nargs = "?" })

vim.api.nvim_create_user_command("GHReviewFiles", function()
  require("gh_review").toggle_files()
end, { nargs = 0 })

vim.api.nvim_create_user_command("GHReviewStart", function()
  require("gh_review").start_review()
end, { nargs = 0 })

vim.api.nvim_create_user_command("GHReviewSubmit", function()
  require("gh_review").submit_review()
end, { nargs = 0 })

vim.api.nvim_create_user_command("GHReviewDiscard", function()
  require("gh_review").discard_review()
end, { nargs = 0 })

vim.api.nvim_create_user_command("GHReviewClose", function()
  require("gh_review").close()
end, { nargs = 0 })

-- Highlight groups
vim.api.nvim_set_hl(0, "GHReviewThread", { default = true, ctermfg = "Blue", fg = "#58a6ff" })
vim.api.nvim_set_hl(0, "GHReviewThreadResolved", { default = true, ctermfg = "Green", fg = "#3fb950" })
vim.api.nvim_set_hl(0, "GHReviewThreadPending", { default = true, ctermfg = "Yellow", fg = "#d29922" })
vim.api.nvim_set_hl(0, "GHReviewVirtText", { default = true, ctermfg = "Gray", fg = "#8b949e", italic = true })

-- Fold guard for diff buffers
local fold_guard = vim.api.nvim_create_augroup("gh_review_fold_guard", { clear = true })
vim.api.nvim_create_autocmd("OptionSet", {
  group = fold_guard,
  pattern = "foldmethod",
  callback = function()
    local bufnr = vim.api.nvim_get_current_buf()
    if vim.b[bufnr].gh_review_diff and vim.wo.foldmethod ~= "diff" then
      vim.cmd("noautocmd setlocal foldmethod=diff foldlevel=0")
    end
  end,
})
vim.api.nvim_create_autocmd("OptionSet", {
  group = fold_guard,
  pattern = "foldenable",
  callback = function()
    local bufnr = vim.api.nvim_get_current_buf()
    if vim.b[bufnr].gh_review_diff and not vim.wo.foldenable then
      vim.cmd("noautocmd setlocal foldenable")
    end
  end,
})
