set -xe
mkdir -p bin
cd ./src/
mold -run hare build -o ./../bin/mossy
