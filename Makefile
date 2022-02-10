all: test check

test:
	nvim --headless --noplugin -u tests/test_init.vim +Test

check:
	luacheck .
