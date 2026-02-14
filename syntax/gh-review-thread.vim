if exists('b:current_syntax')
  finish
endif

" Header: "Thread on path:N  [Status]" or "New comment on path:N  [New]"
syntax match ghThreadHeader '\v^(Thread on|New comment on) .*$' contains=ghThreadStatus
syntax match ghThreadStatus '\v\[(Active|Resolved|New)\]' contained

" Separator lines (solid horizontal rules)
syntax match ghThreadSeparator '\v^─+$'

" Reply separator
syntax match ghThreadReplySep '\v^── Reply below.*──$'

" Code context: "  42 + │ code"
syntax match ghThreadCodeContext '\v^  \d+ [+-] │.*$' contains=ghThreadCodeLineNr,ghThreadCodeDiffMark,ghThreadCodeBar
syntax match ghThreadCodeLineNr '\v^\s+\d+' contained
syntax match ghThreadCodeDiffMark '\v [+-] ' contained
syntax match ghThreadCodeBar '│' contained

" Author line: "alice (2025-01-15 10:30):"
syntax match ghThreadAuthor '\v^\S+.*\(\d{4}-\d{2}-\d{2}.*\):$'

highlight default ghThreadHeader ctermfg=4 guifg=#61afef
highlight default ghThreadStatus ctermfg=3 guifg=#e5c07b cterm=bold gui=bold
highlight default ghThreadSeparator ctermfg=8 guifg=#5c6370
highlight default ghThreadReplySep ctermfg=8 guifg=#5c6370 cterm=italic gui=italic
highlight default ghThreadCodeContext ctermfg=8 guifg=#5c6370
highlight default ghThreadCodeLineNr ctermfg=8 guifg=#5c6370
highlight default ghThreadCodeDiffMark ctermfg=6 guifg=#56b6c2
highlight default ghThreadCodeBar ctermfg=8 guifg=#5c6370
highlight default ghThreadAuthor ctermfg=2 guifg=#98c379 cterm=bold gui=bold

let b:current_syntax = 'gh-review-thread'
