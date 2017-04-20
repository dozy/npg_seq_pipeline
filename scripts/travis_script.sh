#!/bin/bash

set -e -x

perl Build.PL
./Build clean
./Build test --verbose

if [ $? -ne 0 ]; then
    echo ===============================================================================
    cat tests.log
    echo ===============================================================================
fi
