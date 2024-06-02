set -xe
cd ./src/
mold -run hare build -D stacktrace=false -D silent=true -o ~/.local/bin/mossy
cd ..
cp -r ./lib/. ~/.local/lib/lime/
