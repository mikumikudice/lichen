set -xe
mkdir -p ~/.local/bin/
mkdir -p ~/.local/lib/
cd ./src/
mold -run hare build -o ~/.local/bin/lcc
cd ..
cp -r ./lib/. ~/.local/lib/liclib/
