" Matches any number of unescaped spaces at the beginning of a line, followed
" by the appropriate signifier
syntax match DirbufFile /^\([^\\ \t]\|\\[\\ t]\)*/
hi link DirbufFile Normal
syntax match DirbufDirectory /^\([^\\ \t]\|\\[\\ t]\)*\/\@=/
hi link DirbufDirectory Directory
syntax match DirbufLink /^\([^\\ \t]\|\\[\\ t]\)*@\@=/
hi link DirbufLink String
syntax match DirbufFifo /^\([^\\ \t]\|\\[\\ t]\)*|\@=/
hi link DirbufFifo Constant
syntax match DirbufSocket /^\([^\\ \t]\|\\[\\ t]\)*=\@=/
hi link DirbufSocket Special

" TODO: Highlight malformed lines

syntax match DirbufHash /\s\@<=#\x\{8}\s*$/
hi link DirbufHash Special
