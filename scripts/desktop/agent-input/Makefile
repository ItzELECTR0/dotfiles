CFLAGS ?= -O2 -Wall -Wextra
PKGS = wayland-client xkbcommon
PROTOS = virtual-keyboard-unstable-v1 wlr-virtual-pointer-unstable-v1
HEADERS = $(PROTOS:%=build/%-client-protocol.h)
SOURCES = $(PROTOS:%=build/%-protocol.c)

build/agent-input: agent-input.c $(HEADERS) $(SOURCES)
	$(CC) $(CFLAGS) -Ibuild $(shell pkg-config --cflags $(PKGS)) -o $@ agent-input.c $(SOURCES) $(shell pkg-config --libs $(PKGS))

build/%-client-protocol.h: protocol/%.xml | build
	wayland-scanner client-header $< $@

build/%-protocol.c: protocol/%.xml | build
	wayland-scanner private-code $< $@

build:
	mkdir -p build

clean:
	rm -rf build

.PHONY: clean
