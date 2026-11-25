#!/usr/bin/env bash
# Near-miss: read-only git with a benign pager, writes only inside the project.
GIT_PAGER=cat git log --oneline -n 5 > ./build-log.txt
