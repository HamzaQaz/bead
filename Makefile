PREFIX ?= $(HOME)/.local
SHARE  := $(PREFIX)/share/bead

.PHONY: build install run glint install-glint strand test

build: shaders/goo.frag.qsb shaders/stack.frag.qsb shaders/blob.frag.qsb shaders/intro.frag.qsb shaders/ink.frag.qsb shaders/sky.frag.qsb

shaders/%.frag.qsb: shaders/%.frag
	/usr/lib/qt6/bin/qsb --glsl "100es,120,150" --hlsl 50 --msl 12 -o $@ $<

install: build
	install -d $(SHARE)
	@# keep the running version: a bead that fails to start gets it back (below)
	@rm -rf $(SHARE).prev && cp -a $(SHARE) $(SHARE).prev
	cp -r shell.qml config components modules services pam.d data hold $(SHARE)/
	install -Dm644 -t $(SHARE)/shaders shaders/goo.frag.qsb shaders/stack.frag.qsb shaders/blob.frag.qsb shaders/intro.frag.qsb shaders/ink.frag.qsb shaders/sky.frag.qsb
	install -Dm755 bin/bead $(PREFIX)/bin/bead
	install -Dm755 bin/bead-resume $(PREFIX)/bin/bead-resume
	install -Dm755 bin/bead-discord $(PREFIX)/bin/bead-discord
	install -Dm755 bin/bead-dictate $(PREFIX)/bin/bead-dictate
	install -Dm755 bin/bead-look $(PREFIX)/bin/bead-look
	install -Dm755 bin/bead-tint $(PREFIX)/bin/bead-tint
	install -Dm755 bin/bead-pearl $(PREFIX)/bin/bead-pearl
	install -Dm755 bin/bead-term $(PREFIX)/bin/bead-term
	install -Dm755 bin/bead-activity $(PREFIX)/bin/bead-activity
	install -Dm644 systemd/bead-resume.service $(HOME)/.config/systemd/user/bead-resume.service
	@if pgrep -f "^qs -p $(SHARE) -n" >/dev/null; then \
		: "anchored: an unanchored pattern also matches this very shell"; \
		if $(PREFIX)/bin/bead restart >/dev/null; then echo "bead restarted"; \
		else echo "bead failed to start: rolled back to the previous version" >&2; \
			rm -rf $(SHARE).broken && mv $(SHARE) $(SHARE).broken && mv $(SHARE).prev $(SHARE) && \
			BEAD_NO_HOLD=1 $(PREFIX)/bin/bead start >/dev/null 2>&1; exit 1; fi; fi

# run from the source tree (for development)
run: build
	QT_SCALE_FACTOR=$${BEAD_SCALE:-1} qs -p .

# Glint: the toast CLI (Go) and its Claude Code hook. Optional; needs go.
glint/glint: glint/*.go glint/go.mod
	cd glint && go build -trimpath -o glint .

glint/qml/goo.frag.qsb: glint/qml/goo.frag
	/usr/lib/qt6/bin/qsb --glsl "100es,120,150" --hlsl 50 --msl 12 -o $@ $<

glint: glint/glint glint/qml/goo.frag.qsb

install-glint: glint
	install -Dm755 glint/glint $(PREFIX)/bin/glint
	install -Dm644 glint/qml/toast.qml $(PREFIX)/share/glint/toast.qml
	install -Dm644 glint/qml/goo.frag.qsb $(PREFIX)/share/glint/goo.frag.qsb
	install -Dm755 glint/claude-hook.sh $(PREFIX)/share/glint/claude-hook.sh

# strand: the installer (./install.sh builds and runs it)
strand:
	cd strand && go build -trimpath -o strand .

test:
	QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests
	cd strand && go test ./...
	cd glint && go vet ./...
