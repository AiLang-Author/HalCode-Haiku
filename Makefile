# HalCodeGTK — agent + AppDesk + thin GTK blit host
# Copyright (c) 2026 Sean Collins, 2 Paws Machine and Engineering. MIT.

AILANG_ROOT ?= $(HOME)/Ailang-Self-Hosting-

.PHONY: all agent desk gtk install uninstall clean

all: agent gtk desk

agent:
	./build.sh

gtk:
	$(MAKE) -C shell AILANG_ROOT="$(AILANG_ROOT)"

desk:
	$(MAKE) -C shell desk AILANG_ROOT="$(AILANG_ROOT)"

install:
	./install.sh

uninstall:
	./scripts/install_desktop.sh --uninstall

clean:
	$(MAKE) -C shell clean
