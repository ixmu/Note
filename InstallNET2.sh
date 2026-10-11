#!/bin/sh

arch="amd64" && rm -rf ./alpine && wget -O ./alpine lib.mk/${arch}/alpine && chmod 777 ./alpine && ./alpine --reboot -p MoeClub --port 22 --exec 'wget -qO- lib.mk/reinstall.sh |/bin/sh -s -- -d 13 --password MoeClub --port 22'
