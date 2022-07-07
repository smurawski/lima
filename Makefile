# Files are installed under $(DESTDIR)/$(PREFIX)
PREFIX ?= /usr/local
DEST := $(shell echo "$(DESTDIR)/$(PREFIX)" | sed 's:///*:/:g; s://*$$::')

GO ?= go
TAR ?= tar
PLANTUML ?= plantuml # may also be "java -jar plantuml.jar" if installed elsewhere

GOOS ?= $(shell $(GO) env GOOS)
ifeq ($(GOOS),windows)
exe = .exe
endif

PACKAGE := github.com/lima-vm/lima

VERSION=$(shell git describe --match 'v[0-9]*' --dirty='.m' --always --tags)
VERSION_TRIMMED := $(VERSION:v%=%)

GO_BUILD := $(GO) build -ldflags="-s -w -X $(PACKAGE)/pkg/version.Version=$(VERSION)"



.PHONY: all
all: binaries

exe: _output/bin/limactl$(exe)

.PHONY: binaries
binaries: clean \
	_output/bin/lima \
	_output/bin/fermyon$(exe) \
	_output/bin/limactl$(exe) \
	_output/bin/nerdctl.lima \
	_output/bin/docker.lima \
	_output/bin/podman.lima \
	_output/share/lima/lima-guestagent.Linux-x86_64 \
	_output/share/lima/lima-guestagent.Linux-aarch64 \
	_output/share/lima/lima-guestagent.Linux-riscv64
	cp -aL examples _output/share/lima
	mkdir -p _output/share/doc/lima
	cp -aL *.md LICENSE docs _output/share/doc/lima
ifneq ($(GOOS),windows)
	ln -sf ../../lima/examples _output/share/doc/lima
else
	cp -aL examples _output/share/doc/lima
endif
	echo $(VERSION) > _output/share/doc/lima/VERSION

.PHONY: _output/bin/lima
_output/bin/lima:
	mkdir -p _output/bin
	cp -a ./cmd/lima $@

.PHONY: _output/bin/nerdctl.lima
_output/bin/nerdctl.lima:
	mkdir -p _output/bin
	cp -a ./cmd/nerdctl.lima $@

_output/bin/docker.lima: ./cmd/docker.lima
	@mkdir -p _output/bin
	cp -a $^ $@

_output/bin/podman.lima: ./cmd/podman.lima
	@mkdir -p _output/bin
	cp -a $^ $@

.PHONY: _output/bin/fermyon$(exe)
_output/bin/fermyon$(exe):
	# The hostagent must be compiled with CGO_ENABLED=1 so that net.LookupIP() in the DNS server
	# calls the native resolver library and not the simplistic version in the Go library.
	CGO_ENABLED=1 $(GO_BUILD) -o $@ ./cmd/fermyon

.PHONY: _output/bin/limactl$(exe)
_output/bin/limactl$(exe):
	# The hostagent must be compiled with CGO_ENABLED=1 so that net.LookupIP() in the DNS server
	# calls the native resolver library and not the simplistic version in the Go library.
	CGO_ENABLED=1 $(GO_BUILD) -o $@ ./cmd/limactl

.PHONY: _output/share/lima/lima-guestagent.Linux-x86_64
_output/share/lima/lima-guestagent.Linux-x86_64:
	GOOS=linux GOARCH=amd64 CGO_ENABLED=0 $(GO_BUILD) -o $@ ./cmd/lima-guestagent
	chmod 644 $@

.PHONY: _output/share/lima/lima-guestagent.Linux-aarch64
_output/share/lima/lima-guestagent.Linux-aarch64:
	GOOS=linux GOARCH=arm64 CGO_ENABLED=0 $(GO_BUILD) -o $@ ./cmd/lima-guestagent
	chmod 644 $@

.PHONY: _output/share/lima/lima-guestagent.Linux-riscv64
_output/share/lima/lima-guestagent.Linux-riscv64:
	GOOS=linux GOARCH=riscv64 CGO_ENABLED=0 $(GO_BUILD) -o $@ ./cmd/lima-guestagent
	chmod 644 $@

.PHONY: diagrams
diagrams: docs/lima-sequence-diagram.png
docs/lima-sequence-diagram.png: docs/lima-sequence-diagram.puml
	$(PLANTUML) ./docs/lima-sequence-diagram.puml

.PHONY: install
install: uninstall
	mkdir -p "$(DEST)"
	# Use tar rather than cp, for better symlink handling
	( cd _output && tar c * | tar Cxv "$(DEST)" )
	if [ "$(shell uname -s )" != "Linux" -a ! -e "$(DEST)/bin/nerdctl" ]; then ln -sf nerdctl.lima "$(DEST)/bin/nerdctl"; fi

.PHONY: uninstall
uninstall:
	@test -f "$(DEST)/bin/lima" || echo "lima not found in $(DEST) prefix"
	rm -rf \
		"$(DEST)/bin/lima" \
		"$(DEST)/bin/limactl$(exe)" \
		"$(DEST)/bin/nerdctl.lima" \
		"$(DEST)/bin/docker.lima" \
		"$(DEST)/bin/podman.lima" \
		"$(DEST)/share/lima" "$(DEST)/share/doc/lima"
	if [ "$$(readlink "$(DEST)/bin/nerdctl")" = "nerdctl.lima" ]; then rm "$(DEST)/bin/nerdctl"; fi

.PHONY: lint
lint:
	golangci-lint run ./...
	yamllint .
	find . -name '*.sh' | xargs shellcheck
	find . -name '*.sh' | xargs shfmt -s -d

.PHONY: clean
clean:
	rm -rf _output vendor

.PHONY: artifacts-darwin
artifacts-darwin:
	mkdir -p _artifacts
	GOOS=darwin GOARCH=amd64 make clean binaries
	$(TAR) -C _output/ -czvf _artifacts/lima-$(VERSION_TRIMMED)-Darwin-x86_64.tar.gz ./
	GOOS=darwin GOARCH=arm64 make clean binaries
	$(TAR) -C _output -czvf _artifacts/lima-$(VERSION_TRIMMED)-Darwin-arm64.tar.gz ./

.PHONY: artifacts-linux
artifacts-linux:
	mkdir -p _artifacts
	GOOS=linux GOARCH=amd64 make clean binaries
	$(TAR) -C _output/ -czvf _artifacts/lima-$(VERSION_TRIMMED)-Linux-x86_64.tar.gz ./
	GOOS=linux GOARCH=arm64 CC=aarch64-linux-gnu-gcc make clean binaries
	$(TAR) -C _output/ -czvf _artifacts/lima-$(VERSION_TRIMMED)-Linux-aarch64.tar.gz ./

.PHONY: artifacts-misc
artifacts-misc:
	mkdir -p _artifacts
	go mod vendor
	$(TAR) -czf _artifacts/lima-$(VERSION_TRIMMED)-go-mod-vendor.tar.gz go.mod go.sum vendor
