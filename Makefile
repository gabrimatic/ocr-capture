SWIFTC ?= xcrun swiftc
BINARY ?= ocr-capture
SOURCE := ocr-capture.swift
FRAMEWORKS := -framework Cocoa -framework Vision

.PHONY: build test install uninstall

build:
	$(SWIFTC) -O -o $(BINARY) $(SOURCE) $(FRAMEWORKS)

test:
	./tests/test_cli.sh

install:
	./setup.sh

uninstall:
	./setup.sh --uninstall
