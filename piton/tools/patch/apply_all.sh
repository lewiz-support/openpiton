#!/bin/bash

cd "$(dirname "$0")"
for d in */ ; do
    ${d}apply.sh
done