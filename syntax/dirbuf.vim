" syn region DirbufFile start=/'/ skip=/\\\\\|\\'/ end=/'/ keepend
" hi link DirbufFile String

" Matches any number of unescaped spaces at the beginning of a line, followed
" by the appropriate signifier
" TODO: Figure out how to make this match not overlap with the others
" Actually, is this even necessary? Probably nice for users who want to
" specifically color them...
" syn match DirbufFile /^\([^\\ ]\|\\\\\|\\\s\)*/
" hi link DirbufFile Normal
syn match DirbufDir /^\([^\\ ]\|\\\\\|\\\s\)*\//
hi link DirbufDir Directory
syn match DirbufLink /^\([^\\ ]\|\\\\\|\\\s\)*@/
hi link DirbufLink String

" TODO: Highlight malformed lines?

syn match DirbufHash /#\x\{7}$/
hi link DirbufHash Special
