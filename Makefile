.PHONY: package clean

package: clean
	mkdir -p build/package
	python3 -m pip install . -t build/package --no-deps --quiet
	python3 -m pip install pyyaml -t build/package --quiet
	cd build/package && zip -qr ../devgen-lambda.zip .
	@echo "built build/devgen-lambda.zip"

clean:
	rm -rf build