PREFIX ?= $(HOME)/.local
SHARE  := $(PREFIX)/share/bead

.PHONY: build install run

build: shaders/goo.frag.qsb shaders/stack.frag.qsb

shaders/%.frag.qsb: shaders/%.frag
	/usr/lib/qt6/bin/qsb --glsl "100es,120,150" --hlsl 50 --msl 12 -o $@ $<

install: build
	install -d $(SHARE)
	cp -r shell.qml config components modules $(SHARE)/
	install -Dm644 -t $(SHARE)/shaders shaders/goo.frag.qsb shaders/stack.frag.qsb
	install -Dm755 bin/bead $(PREFIX)/bin/bead

# run from the source tree (for development)
run: build
	QT_SCALE_FACTOR=$${BEAD_SCALE:-1.35} qs -p .
