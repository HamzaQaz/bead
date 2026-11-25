PREFIX ?= $(HOME)/.local
SHARE  := $(PREFIX)/share/bead

.PHONY: build install install-files run glint install-glint strand test friend-test

build: shaders/goo.frag.qsb shaders/stack.frag.qsb shaders/blob.frag.qsb shaders/intro.frag.qsb shaders/ink.frag.qsb shaders/sky.frag.qsb shaders/trace.frag.qsb shaders/rise.frag.qsb shaders/veil.frag.qsb shaders/sketch.frag.qsb

shaders/%.frag.qsb: shaders/%.frag
	/usr/lib/qt6/bin/qsb --glsl "100es,120,150" --hlsl 50 --msl 12 -o $@ $<

BINS   := bead bead-resume bead-discord bead-dictate bead-look bead-tint bead-pearl bead-term bead-activity bead-doctor bead-update bead-uninstall
# a user install puts the resume watcher in the user's systemd folder, a package in the system's
UNITDIR ?= $(if $(filter $(HOME)/.local,$(PREFIX)),$(HOME)/.config/systemd/user,$(PREFIX)/lib/systemd/user)

# just the files, under $(DESTDIR)$(PREFIX): what a package installs
install-files: build
	install -d $(DESTDIR)$(SHARE)
	cp -r shell.qml config components modules services pam.d data hold VERSION CHANGELOG.md $(DESTDIR)$(SHARE)/
	install -Dm644 -t $(DESTDIR)$(SHARE)/shaders shaders/goo.frag.qsb shaders/stack.frag.qsb shaders/blob.frag.qsb shaders/intro.frag.qsb shaders/ink.frag.qsb shaders/sky.frag.qsb shaders/trace.frag.qsb shaders/rise.frag.qsb shaders/veil.frag.qsb shaders/sketch.frag.qsb
	for b in $(BINS); do install -Dm755 bin/$$b $(DESTDIR)$(PREFIX)/bin/$$b || exit 1; done
	install -d $(DESTDIR)$(UNITDIR)
	sed 's|%h/.local/bin|$(PREFIX)/bin|' systemd/bead-resume.service >$(DESTDIR)$(UNITDIR)/bead-resume.service

# a user install: keeps the running version, and a bead that fails to start gets it back
install: build
	install -d $(SHARE)
	@rm -rf $(SHARE).prev && cp -a $(SHARE) $(SHARE).prev
	@$(MAKE) --no-print-directory install-files >/dev/null
	@: "where it came from, for bead update"
	@echo "$(CURDIR)" >$(SHARE)/source
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
	install -Dm755 glint/glint $(DESTDIR)$(PREFIX)/bin/glint
	install -Dm644 glint/qml/toast.qml $(DESTDIR)$(PREFIX)/share/glint/toast.qml
	install -Dm644 glint/qml/goo.frag.qsb $(DESTDIR)$(PREFIX)/share/glint/goo.frag.qsb
	install -Dm755 glint/claude-hook.sh $(DESTDIR)$(PREFIX)/share/glint/claude-hook.sh

# strand: the installer (./install.sh builds and runs it)
strand:
	cd strand && go build -trimpath -o strand .

test:
	QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests
	cd strand && go test ./...
	cd glint && go vet ./...
	tests/scripts-test.sh

# install on a fresh Arch in a throwaway container (podman) and check it
friend-test:
	tests/friend-test.sh
