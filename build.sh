set -xe
mkdir -p bin
cd ./src/
mold -run hare build -D stacktrace=false -D silent=false -o ./../bin/mossy
