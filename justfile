default: build

build: build_ethproxy build_frameforge
run: run_ethproxy run_frameforge

[working-directory: 'ethproxy']
@build_ethproxy:
    echo 'Building ethproxy'
    go build .

[working-directory: 'ethproxy']
@run_ethproxy:
    echo 'Running ethproxy'
    go run .

[working-directory: 'frameforge']
@build_frameforge:
    echo 'Building frameforge'
    dune build

[working-directory: 'frameforge']
@run_frameforge:
    echo 'Running frameforge'
    dune exec frameforge
