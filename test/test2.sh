#!/bin/bash
rm testdata/actual/test2.actual
mkdir testdata/actual/test2
cp testdata/actual/cluster_gitops testdata/actual/test2

# Check if the output file exists and has content
if ! [ -d testdata/actual/cluster-gitops ]; then
    echo "Test failed: output file is empty or does not exist"
    echo "This is a problem with the test itself (e.g. poorly written), not the must-gather tool"
    exit 1
fi

# Check if expected result is the same as actual result
if [ diff -qr testdata/expected/cluster-gitops testdata/actual/cluster-gitops ]; then
    echo "Test2: Passed"
else
    echo "Test2: Failed... test2.actual is not equal to test2.expected"
    exit 1
fi