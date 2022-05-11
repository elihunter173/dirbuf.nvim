if !isdirectory('plenary.nvim')
  !git clone https://github.com/nvim-lua/plenary.nvim.git plenary.nvim
  !git -C plenary.nvim reset --hard 1338bbe8ec6503ca1517059c52364ebf95951458
endif
set runtimepath+=plenary.nvim,.
runtime plugin/plenary.vim
try | runtime plugin/dirbuf.vim | catch | cquit! 173 | endtry
command Test PlenaryBustedDirectory tests/ {minimal_init = 'tests/test_init.vim'}
