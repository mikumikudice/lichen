set -xe
mkdir -p bin
cd ./src/
mold -run hare build -D stacktrace=true -o ./../bin/mossy
