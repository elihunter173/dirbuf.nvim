" Matches any number of unescaped spaces at the beginning of a line, followed
" by the appropriate signifier
syn match DirbufFile /^\([^\\ ]\|\\\\\|\\\s\)*/
hi link DirbufFile Normal
syn match DirbufDirectory /^\([^\\ ]\|\\\\\|\\\s\)*\//
hi link DirbufDirectory Directory
syn match DirbufLink /^\([^\\ ]\|\\\\\|\\\s\)*@/
hi link DirbufLink String
syn match DirbufSocket /^\([^\\ ]\|\\\\\|\\\s\)*=/
hi link DirbufSocket Special
syn match DirbufFifo /^\([^\\ ]\|\\\\\|\\\s\)*|/
hi link DirbufFifo Type

" TODO: Highlight malformed lines?

" TODO: Tolerate trailing whitespace? Also need to update dirbuf.parse_line
syn match DirbufHash /\s#\x\{8}$/
hi link DirbufHash Special
