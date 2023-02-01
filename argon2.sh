#!/bin/sh

pw="$1"

salt="$(tr -dc 'A-Za-z0-9!"#$%&'\''()*+,-./:;<=>?@[\]^_`{|}~' </dev/urandom | head -c 64  ; echo)"

saltedpw="${salt}${pw}"#

