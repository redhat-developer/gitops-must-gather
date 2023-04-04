#!/bin/bash

# Check if the mustgather_output tree for expected is the same as actual tree output
# sed looks for the uid of the resource and replaces it with xxxxxx-xxxxx
# sed also removes the lines for files for events because the presence of those can be impacted by external sources resulting in flaky tests
cd testdata/actual/mustgather_output/ && tree | sed -r '
s/([a-zA-Z0-9-]+(-[a-zA-Z0-9]+)?)-[a-f0-9]{4,}(-[a-z0-9]+)?(\.[a-zA-Z0-9_-]+)?/\1-xxxxxx-xxxxx\4/g
/warning-events.txt/d
/error-events.txt/d
/all-events.txt/d
'
