#!/bin/bash

# Run the command and save the output to a file
tree testdata/actual/cluster-gitops | tail -n -1 > testdata/actual/test1.actual

# Check if the output file exists and has content
if ! [ -s testdata/actual/test1.actual ]; then
    echo "Test failed: output file is empty or does not exist"
    echo "This is a problem with the test itself (e.g. poorly written), not the must-gather tool"
    exit 1
fi
