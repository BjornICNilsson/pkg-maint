PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin
CONF_DIR ?= $(HOME)/.config/pkg-maint
MAN_DIR ?= $(PREFIX)/share/man/man1

.PHONY: install install-bin install-config install-man uninstall path-hint setup-path test

install: install-config install-man install-bin path-hint

install-bin:
	install -d $(BINDIR)
	install -m 0755 bin/pkg-maint $(BINDIR)/pkg-maint

install-config:
	install -d $(CONF_DIR)
	@if [ ! -f $(CONF_DIR)/config.env ]; then \
		install -m 0644 config/config.env.example $(CONF_DIR)/config.env; \
	else \
		echo "Keeping existing $(CONF_DIR)/config.env"; \
	fi

install-man:
	install -d $(MAN_DIR)
	install -m 0644 man/pkg-maint.1 $(MAN_DIR)/pkg-maint.1

path-hint:
	@if case ":$$PATH:" in *":$(BINDIR):"*) true ;; *) false ;; esac; then \
		echo "$(BINDIR) is already in PATH"; \
	else \
		echo "Installed to $(BINDIR), but it is not in PATH."; \
		echo "Run 'make setup-path' to add it to your shell startup file."; \
		echo "Or install to /usr/local/bin (in PATH): sudo make install BINDIR=/usr/local/bin"; \
	fi

setup-path:
	@bindir="$(BINDIR)"; \
	case "$$SHELL" in \
		*/zsh) rc="$(HOME)/.zprofile" ;; \
		*/bash) rc="$(HOME)/.profile" ;; \
		*) rc="$(HOME)/.profile" ;; \
	esac; \
	line="export PATH=\"$$bindir:\$$PATH\""; \
	touch "$$rc"; \
	if grep -Fq "$$line" "$$rc"; then \
		echo "$$bindir is already configured in $$rc"; \
	else \
		printf '\n# Added by pkg-maint install\n%s\n' "$$line" >> "$$rc"; \
		echo "Added $$bindir to PATH in $$rc"; \
		echo "Restart your shell or run: . $$rc"; \
	fi

uninstall:
	rm -f $(BINDIR)/pkg-maint
	rm -f $(MAN_DIR)/pkg-maint.1

test:
	./tests/regression.sh
