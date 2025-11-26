default: build

build: build_frameforge build_ethproxy

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

@run: build
    echo 'Starting frameforge server...'
    ./frameforge/_build/default/bin/main.exe &
    sleep 1 # Give server time to start
    echo 'Starting ethproxy client...'
    ./ethproxy/ethproxy
