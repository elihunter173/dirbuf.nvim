all: lint test

test:
	nvim --headless --clean -u tests/test_init.vim +Test

lint:
	luacheck .
