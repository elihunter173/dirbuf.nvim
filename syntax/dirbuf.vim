" Matches any number of unescaped spaces at the beginning of a line, followed
" by the appropriate signifier
syntax match DirbufFile /^\([^\\ \t]\|\\[\\ t]\)*/
highlight link DirbufFile Normal
syntax match DirbufDirectory /^\([^\\ \t]\|\\[\\ t]\)*\/\@=/
highlight link DirbufDirectory Directory
syntax match DirbufLink /^\([^\\ \t]\|\\[\\ t]\)*@\@=/
highlight link DirbufLink String
syntax match DirbufFifo /^\([^\\ \t]\|\\[\\ t]\)*|\@=/
highlight link DirbufFifo Constant
syntax match DirbufSocket /^\([^\\ \t]\|\\[\\ t]\)*=\@=/
highlight link DirbufSocket Special
syntax match DirbufChar /^\([^\\ \t]\|\\[\\ t]\)*%\@=/
highlight link DirbufChar Type
syntax match DirbufBlock /^\([^\\ \t]\|\\[\\ t]\)*#\@=/
highlight link DirbufBlock Type

" TODO: Highlight malformed lines

syntax match DirbufHash /\s\@<=#\x\{8}\s*$/
highlight link DirbufHash Special
