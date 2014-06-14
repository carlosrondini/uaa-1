#!/bin/bash
set -eu

### del unneeded files
find -name ".git" -prune -exec rm -rf {} \;
find -name ".svn" -prune -exec rm -rf {} \;

### tar all files
tar zcf data.tar.gz ./

### mv to output
mkdir -p output
mv data.tar.gz output
