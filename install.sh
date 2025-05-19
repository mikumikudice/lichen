set -xe
mkdir -p ~/.local/bin/
mkdir -p ~/.local/lib/
cd ./src/
hare build -o ~/.local/bin/lcc
cd ..
cp -r ./lib/. ~/.local/lib/lcclib/
