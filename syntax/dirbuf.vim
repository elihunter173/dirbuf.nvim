" Matches any number of unescaped spaces at the beginning of a line, followed
" by the appropriate signifier
syntax match DirbufFile /^\([^\\ \t]\|\\[\\ t]\)\+/
highlight link DirbufFile Normal
syntax match DirbufDirectory /^\([^\\ \t]\|\\[\\ t]\)\+\//me=e-1
highlight link DirbufDirectory Directory
syntax match DirbufLink /^\([^\\ \t]\|\\[\\ t]\)\+@/me=e-1
highlight link DirbufLink String
syntax match DirbufFifo /^\([^\\ \t]\|\\[\\ t]\)\+|/me=e-1
highlight link DirbufFifo Constant
syntax match DirbufSocket /^\([^\\ \t]\|\\[\\ t]\)\+=/me=e-1
highlight link DirbufSocket Special
syntax match DirbufChar /^\([^\\ \t]\|\\[\\ t]\)\+%/me=e-1
highlight link DirbufChar Type
syntax match DirbufBlock /^\([^\\ \t]\|\\[\\ t]\)\+#/me=e-1
highlight link DirbufBlock Type

syntax match DirbufHash /\s#\x\{8}\s*$/ms=s+1
highlight link DirbufHash Special

" ```
" ^\(\(The_Regular_Expression\)\@!.\)*$
" ```
" This finds every except for the regular expression
" See: https://vim.fandom.com/wiki/Search_for_lines_not_containing_pattern_and_other_helpful_searches#Searching_with_.2F
syntax match DirbufMalformedLine /^\(\(\_^\([^\\ \t]\|\\[\\ t]\)\+\s*\(\s#\x\{8}\s*\)\?\_$\)\@!.\)*$/
highlight link DirbufMalformedLine Error
