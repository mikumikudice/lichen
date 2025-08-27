set -e
cd ../
./install.sh
cd ./scripts/
./run_tests.lua $@
