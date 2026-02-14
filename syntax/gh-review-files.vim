if exists('b:current_syntax')
  finish
endif

" Header line 1: URL and PR title
syntax match ghReviewURL  '\vhttps://[^ :]+' contained
syntax match ghReviewTitle '\v: \zs.*$' contained
syntax match ghReviewHeader '\v^https://.*$' contains=ghReviewURL,ghReviewTitle

" Header line 2: Files changed (N)
syntax match ghReviewFilesChanged '\v^Files changed \(\d+\)$'

" File lines: additions, deletions, change type flag, path, thread count
syntax match ghReviewAdditions '\v\+\d+' contained
syntax match ghReviewDeletions '\v-\d+' contained
syntax match ghReviewFlagA '\v\s\zsA\ze\s\s' contained
syntax match ghReviewFlagD '\v\s\zsD\ze\s\s' contained
syntax match ghReviewFlagM '\v\s\zsM\ze\s\s' contained
syntax match ghReviewFlagR '\v\s\zsR\ze\s\s' contained
syntax match ghReviewFlagC '\v\s\zsC\ze\s\s' contained
syntax match ghReviewThreads '\v\[\d+ threads?\]' contained
syntax match ghReviewFileLine '\v^  \+.*$' contains=ghReviewAdditions,ghReviewDeletions,ghReviewFlagA,ghReviewFlagD,ghReviewFlagM,ghReviewFlagR,ghReviewFlagC,ghReviewThreads

highlight default ghReviewURL ctermfg=2 guifg=#98c379 term=underline cterm=underline gui=underline
highlight default link ghReviewTitle Title
highlight default link ghReviewFilesChanged Comment
highlight default ghReviewAdditions ctermfg=2 guifg=#98c379
highlight default ghReviewDeletions ctermfg=1 guifg=#e06c75
highlight default ghReviewFlagA ctermfg=2 guifg=#98c379
highlight default ghReviewFlagD ctermfg=1 guifg=#e06c75
highlight default ghReviewFlagM ctermfg=3 guifg=#e5c07b
highlight default ghReviewFlagR ctermfg=6 guifg=#56b6c2
highlight default ghReviewFlagC ctermfg=6 guifg=#56b6c2
highlight default ghReviewThreads ctermfg=5 guifg=#c678dd

let b:current_syntax = 'gh-review-files'
