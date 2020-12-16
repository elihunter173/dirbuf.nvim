test:
	nvim --headless --noplugin -u tests/test_init.vim -c 'PlenaryBustedDirectory tests/ tests/test_init.vim'
