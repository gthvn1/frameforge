default: build

build: build_frameforge build_ethproxy
run: run_frameforge run_ethproxy

[working-directory: 'frameforge']
@build_frameforge:
    echo 'Building frameforge'
    dune build

[working-directory: 'frameforge']
@run_frameforge:
    echo 'Running frameforge'
    dune exec frameforge

[working-directory: 'ethproxy']
@build_ethproxy:
    echo 'Building ethproxy'
    go build .

[working-directory: 'ethproxy']
@run_ethproxy:
    echo 'Running ethproxy'
    go run .
