" # Regex Breakdown
" (a) and (b) define all valid character units, so this regex matches one or
" more valid character units at the beginning of a line.
"
" /^\([^\\\t]\|\\[\\t]\)\+/
"     ^^(a)^^  ^^(b)^^
" (a): all valid single-characters (i.e. not tabs or escape sequences).
" (b): all valid escape sequences.
"
" Object suffixes (e.g. / for directories) are this regular expression with
" their appropriate suffix tacked on. The longest regex is the one
" highlighted, so the suffix always controls the color. We include me=e-1 set
" the 'match end' to be one before the normal 'end' so the suffix doesn't get
" highlighted.
"
" The suffixes are taken from `ls --clasisify` and zsh's tab completion.
syntax match DirbufFile /^\([^\\\t]\|\\[\\t]\)\+/
syntax match DirbufDirectory /^\([^\\\t]\|\\[\\t]\)\+\//me=e-1
syntax match DirbufLink /^\([^\\\t]\|\\[\\t]\)\+@/me=e-1
syntax match DirbufFifo /^\([^\\\t]\|\\[\\t]\)\+|/me=e-1
syntax match DirbufSocket /^\([^\\\t]\|\\[\\t]\)\+=/me=e-1
syntax match DirbufChar /^\([^\\\t]\|\\[\\t]\)\+%/me=e-1
syntax match DirbufBlock /^\([^\\\t]\|\\[\\t]\)\+#/me=e-1

" Highlight each object according to its color in by ls --color=always
highlight link DifbufFile Normal
exe 'highlight DirbufDirectory ctermbg=4 gui=bold guifg='.g:terminal_color_4
exe 'highlight DirbufLink ctermbg=6 guifg='.g:terminal_color_6
exe 'highlight DirbufFifo ctermbg=2 guifg='.g:terminal_color_2
exe 'highlight DirbufSocket ctermbg=5 guifg='.g:terminal_color_5
exe 'highlight DirbufChar ctermbg=3 gui=bold guifg='.g:terminal_color_3
exe 'highlight DirbufBlock ctermbg=3 gui=bold guifg='.g:terminal_color_3

" We include `ms=s+1` to not highlight the tab
syntax match DirbufHash /\t#\x\{8}\s*$/ms=s+1
highlight link DirbufHash Special

" ```
" ^\(\(The_Regular_Expression\)\@!.\)*$
" ```
" This finds every except for the regular expression
" See: https://vim.fandom.com/wiki/Search_for_lines_not_containing_pattern_and_other_helpful_searches#Searching_with_.2F
syntax match DirbufMalformedLine /^\(\(\_^\([^\\\t]\|\\[\\t]\)\+\(\t#\x\{8}\)\?\s*\_$\)\@!.\)*$/
highlight link DirbufMalformedLine Error
