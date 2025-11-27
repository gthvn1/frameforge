# Build everything
.PHONY: build
build: build_frameforge build_ethproxy

# ---- FrameForge (OCaml) ----

.PHONY: build_frameforge
build_frameforge:
	@echo "Building frameforge"
	cd frameforge && dune build

.PHONY: run_frameforge
run_frameforge:
	@echo "Running frameforge"
	cd frameforge && dune exec frameforge

# ---- EthProxy (Go) ----

.PHONY: build_ethproxy
build_ethproxy:
	@echo "Building ethproxy"
	cd ethproxy && go build .

.PHONY: run_ethproxy
run_ethproxy:
	@echo "Running ethproxy"
	cd ethproxy && go run .

# ---- Run everything ----

.PHONY: run
run: build
	@echo "Starting frameforge server..."
	./frameforge/_build/default/bin/main.exe &
	sleep 1
	@echo "Starting ethproxy client..."
	./ethproxy/ethproxy
