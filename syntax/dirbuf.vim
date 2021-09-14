" Matches any number of unescaped spaces at the beginning of a line, followed
" by the appropriate signifier
syn match DirbufFile /^\([^\\ ]\|\\\\\|\\\s\)*/
hi link DirbufFile Normal
syn match DirbufDir /^\([^\\ ]\|\\\\\|\\\s\)*\//
hi link DirbufDir Directory
syn match DirbufLink /^\([^\\ ]\|\\\\\|\\\s\)*@/
hi link DirbufLink String

" TODO: Highlight malformed lines?

" TODO: Tolerate trailing whitespace? Also need to update dirbuf.parse_line
syn match DirbufHash /\s#\x\{8}$/
hi link DirbufHash Special
