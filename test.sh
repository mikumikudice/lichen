set -xe
cd src/
mold -run hare test -D stacktrace=true
