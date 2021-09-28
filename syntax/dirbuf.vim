" Matches any number of unescaped spaces at the beginning of a line, followed
" by the appropriate signifier
syntax match DirbufFile /^\([^\\ ]\|\\\\\|\\\s\)*/
hi link DirbufFile Normal
syntax match DirbufDirectory /^\([^\\ ]\|\\\\\|\\\s\)*\/\@=/
hi link DirbufDirectory Directory
syntax match DirbufLink /^\([^\\ ]\|\\\\\|\\\s\)*@\@=/
hi link DirbufLink String
syntax match DirbufSocket /^\([^\\ ]\|\\\\\|\\\s\)*=\@=/
hi link DirbufSocket Special
syntax match DirbufFifo /^\([^\\ ]\|\\\\\|\\\s\)*|\@=/
hi link DirbufFifo Type

" TODO: Highlight malformed lines?

" TODO: Tolerate trailing whitespace? Also need to update dirbuf.parse_line
syntax match DirbufHash /\s#\x\{8}$/
hi link DirbufHash Special
