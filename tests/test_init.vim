if !isdirectory('/tmp/plenary.nvim')
  !git clone https://github.com/nvim-lua/plenary.nvim.git /tmp/plenary.nvim
  !git -C /tmp/plenary.nvim reset --hard 1338bbe8ec6503ca1517059c52364ebf95951458
endif
set runtimepath+=/tmp/plenary.nvim,.
runtime plugin/plenary.vim
command Test PlenaryBustedDirectory tests/ {minimal_init = 'tests/test_init.vim'}
