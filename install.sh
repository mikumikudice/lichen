set -xe
mkdir -p ~/.local/bin/
mkdir -p ~/.local/lib/
cd ./src/
mold -run hare build -o ~/.local/bin/mmc
cd ..
cp -r ./lib/. ~/.local/lib/mmclib/
