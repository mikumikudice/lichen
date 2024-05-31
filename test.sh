set -xe
cd src/
mold -run hare test

cd ..
mkdir -p .test/
lua run_ms_test.lua