" if exists("g:loaded_dirbuf")
"   finish
" endif
let g:loaded_dirbuf = 1

lua dirbuf = require("dirbuf")

command! -nargs=? -complete=dir Dirbuf lua dirbuf.open(<q-args>)
command! DirbufDebug lua dirbuf.debug()
command! DirbufPrintln lua dirbuf.println(vim.fn.line('.'))
