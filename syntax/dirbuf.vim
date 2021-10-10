" Matches any number of unescaped spaces at the beginning of a line, followed
" by the appropriate signifier.
syntax match DirbufFile /^\([^\\ \t]\|\\[\\ t]\)\+/
syntax match DirbufDirectory /^\([^\\ \t]\|\\[\\ t]\)\+\//me=e-1
syntax match DirbufLink /^\([^\\ \t]\|\\[\\ t]\)\+@/me=e-1
syntax match DirbufFifo /^\([^\\ \t]\|\\[\\ t]\)\+|/me=e-1
syntax match DirbufSocket /^\([^\\ \t]\|\\[\\ t]\)\+=/me=e-1
syntax match DirbufChar /^\([^\\ \t]\|\\[\\ t]\)\+%/me=e-1
syntax match DirbufBlock /^\([^\\ \t]\|\\[\\ t]\)\+#/me=e-1
" Highlight each object according to its color in by ls --color=always
highlight link DifbufFile Normal
exe 'highlight DirbufDirectory ctermbg=4 gui=bold guifg='.g:terminal_color_4
exe 'highlight DirbufLink ctermbg=6 guifg='.g:terminal_color_6
exe 'highlight DirbufFifo ctermbg=3 guifg='.g:terminal_color_2
exe 'highlight DirbufSocket ctermbg=5 guifg='.g:terminal_color_5
exe 'highlight DirbufChar ctermbg=3 gui=bold guifg='.g:terminal_color_3
exe 'highlight DirbufBlock ctermbg=3 gui=bold guifg='.g:terminal_color_3

syntax match DirbufHash /\s#\x\{8}\s*$/ms=s+1
highlight link DirbufHash Special

" ```
" ^\(\(The_Regular_Expression\)\@!.\)*$
" ```
" This finds every except for the regular expression
" See: https://vim.fandom.com/wiki/Search_for_lines_not_containing_pattern_and_other_helpful_searches#Searching_with_.2F
syntax match DirbufMalformedLine /^\(\(\_^\([^\\ \t]\|\\[\\ t]\)\+\s*\(\s#\x\{8}\s*\)\?\_$\)\@!.\)*$/
highlight link DirbufMalformedLine Error
