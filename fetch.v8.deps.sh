mkdir -p v8/third_party/googletest/src

# src url revision
fetch_specific() {
  rm -rf $1
  git clone $2 $1
  cd $1
  git reset --hard $3
  cd -
}


fetch_specific v8/base/trace_event/common https://chromium.googlesource.com/chromium/src/base/trace_event/common.git 147f65333c38ddd1ebf554e89965c243c8ce50b3

fetch_specific v8/build https://chromium.googlesource.com/chromium/src/build.git 7f93a1e7ae8de96f113834f37d01b869a74b7dd3

fetch_specific v8/third_party/abseil-cpp https://chromium.googlesource.com/chromium/src/third_party/abseil-cpp.git 583dc6d1b3a0dd44579718699e37cad2f0c41a26

fetch_specific v8/tools/clang https://chromium.googlesource.com/chromium/src/tools/clang.git 4ee099ac1c0d6e86e53cedfdcfd7cd2d45e126ca

fetch_specific v8/third_party/googletest/src https://chromium.googlesource.com/external/github.com/google/googletest.git af29db7ec28d6df1c7f0f745186884091e602e07

fetch_specific v8/third_party/zlib https://chromium.googlesource.com/chromium/src/third_party/zlib.git 14dd4c4455602c9b71a1a89b5cafd1f4030d2e3f

touch v8/build/config/gclient_args.gni
