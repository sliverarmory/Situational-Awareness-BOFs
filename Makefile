.PHONY: all matrix verify clean

all: matrix

matrix:
	./scripts/build-matrix.sh

verify:
	./scripts/verify-matrix.sh

clean:
	rm -rf dist
