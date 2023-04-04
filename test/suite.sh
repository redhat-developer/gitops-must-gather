#!/bin/bash

# Set testdata directories
TESTDATA_ACTUAL="testdata/actual"
TESTDATA_EXPECTED="testdata/expected"

# Create actual folder if it doesn't exist
if [ ! -d "$TESTDATA_ACTUAL" ]; then
    mkdir -p "$TESTDATA_ACTUAL"
fi

# Set color codes
COLOR_GREEN="\033[32m"
COLOR_RED="\033[31m"
COLOR_CYAN="\033[36m"
COLOR_RESET="\033[0m"

# Print welcome message
echo -e "${COLOR_CYAN}Starting must-gather test suite...${COLOR_RESET}"

# --------------------------------------------------------- #

# Check if there are any test files (excluding this script)
if ! ls test*.sh >/dev/null; then
    echo -e "  ${COLOR_RED}No test files found.${COLOR_RESET}"
    exit 1
fi

echo -e "  ${COLOR_GREEN}Test files found.${COLOR_RESET}"

# Check if kubectl is installed
if ! command -v kubectl >/dev/null; then
    echo -e "  ${COLOR_RED}kubectl not found. Please install kubectl and try again.${COLOR_RESET}"
    exit 1
fi

echo -e "  ${COLOR_GREEN}kubectl binary is installed.${COLOR_RESET}"

# Check if kubectl can access the cluster
if ! kubectl get nodes >/dev/null; then
    echo -e "  ${COLOR_RED}kubectl failed to access the cluster. Please check your kubectl configuration and try again.${COLOR_RESET}"
    exit 1
fi

echo -e "  ${COLOR_GREEN}kubectl is working correctly against the cluster.${COLOR_RESET}"

# --------------------------------------------------------- #
echo

# Run the gather_gitops.sh command and check the exit status
echo -e "${COLOR_CYAN}Running MustGather against the cluster...${COLOR_RESET}"
if ! ../gather_gitops.sh --base-collection-path "$TESTDATA_ACTUAL/mustgather_output"; then
    echo -e "  ${COLOR_RED}Test failed: command exited with an error${COLOR_RESET}"
    echo -e "  ${COLOR_RED}This is a big issue, the must gather fails by default${COLOR_RESET}"
    exit 1
fi
echo -e "  ${COLOR_GREEN}Test passed: command ran successfully${COLOR_RESET}"

# --------------------------------------------------------- #

# Print message
echo
echo -e "${COLOR_CYAN}Running individual test files...${COLOR_RESET}"

# Initialize variables
TEST_COUNTER=0
FAILED_TESTS=0

# Loop over all the test files
for TEST_FILE in ./test*.sh; do
    # Increment the test counter
    ((TEST_COUNTER++))

    # Execute the test and save the output
    TEST_NAME=$(basename "$TEST_FILE" .sh)
    sh "$TEST_FILE" > "$TESTDATA_ACTUAL/$TEST_NAME.actual"

    # Check if the output file exists and has content
    if ! [ -f "$TESTDATA_ACTUAL/$TEST_NAME.actual" ]; then
        echo "Test failed: output file is empty or does not exist"
        echo "This is a problem with the test itself (e.g. poorly written), not the must-gather tool"
        exit 1
    fi

    # Compare the actual and expected outputs
    if diff "$TESTDATA_ACTUAL/$TEST_NAME.actual" "$TESTDATA_EXPECTED/$TEST_NAME.expected" >/dev/null; then
        echo -e "  TEST $TEST_COUNTER: ${COLOR_GREEN}$TEST_NAME PASSED${COLOR_RESET}"
    else
        echo -e "  TEST $TEST_COUNTER: ${COLOR_RED}$TEST_NAME FAILED${COLOR_RESET}"
        ((FAILED_TESTS++))
        # Print the diff if there is a mismatch
        echo -e "=== ACTUAL ==="
        cat "$TESTDATA_ACTUAL/$TEST_NAME.actual"
        echo -e "=== EXPECTED ==="
        cat "$TESTDATA_EXPECTED/$TEST_NAME.expected"
    fi
done

# Print the final message
echo
echo
echo
if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${COLOR_GREEN}Test suite successfully completed without errors!${COLOR_RESET}"
else
    echo -e "${COLOR_RED}Testing failed. $FAILED_TESTS test(s) failed.${COLOR_RESET}"
fi

