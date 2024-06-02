set -xe
cd ./src/
mold -run hare build -D stacktrace=false -o ~/.local/bin/mossy
cd ..
cp -r ./lib/. ~/.local/lib/lime/
