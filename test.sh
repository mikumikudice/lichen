set -xe
cd src/
mold -run hare test -D stacktrace=false -D silent=false
