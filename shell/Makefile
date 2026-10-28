# HalCode desk (AILang, Linux ELF) and the native Haiku window.
# The window links libbe and builds on Haiku only.
# Copyright (c) 2026 Sean Collins, 2 Paws Machine and Engineering. MIT.

AILANG ?= $(shell command -v ailang.x)
AILANG_ROOT ?= $(HOME)/Ailang-Self-Hosting-

.PHONY: all desk clean

all: halcode_shell_haiku

desk: halcode_desk.x

halcode_desk.x: halcode_desk.ailang
	@test -n "$(AILANG)" || (echo "ailang.x not on PATH"; exit 1)
	cd "$(AILANG_ROOT)" && $(AILANG) "$(CURDIR)/halcode_desk.ailang" "$(CURDIR)/halcode_desk.x"

halcode_shell_haiku: halcode_shell_haiku.cxx
	g++ -O2 -o $@ $< -lbe

clean:
	rm -f halcode_shell_haiku halcode_desk.x
