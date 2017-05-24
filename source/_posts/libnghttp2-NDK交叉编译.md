title: libnghttp2 NDK交叉编译
date: 2017-05-24 17:25:39
categories: [NDK]
tags: [NDK, nghttp2, 交叉编译]
---

移植nghttp2到android

<!-- more -->

创建工作目录，并进入

```
mkdir android
cd android
```

clone源码

```
git clone git@github.com:nghttp2/nghttp2.git
```

生成交叉编译工具链

```
$ANDROID_NDK/build/tools/make-standalone-toolchain.sh --arch=arm --install-dir=./toolchain
```

导出环境变量

```
export CURRENT_HOME=`pwd`
export TOOLCHAIN=$CURRENT_HOME/toolchain
export PATH=$TOOLCHAIN/bin:$PATH
export PKG_CONFIG_LIBDIR=$TOOLCHAIN/lib/pkgconfig
export CPPFLAGS="-fPIE -I$TOOLCHAIN/sysroot/usr/include"
export LDFLAGS="-fPIE -pie -I$TOOLCHAIN/sysroot/usr/lib"
```

编译并安装

```
cd nghttp2
autoreconf -i
./configure --enable-lib-only \
    --host=arm-linux-androideabi \
    --build=`dpkg-architecture -qDEB_BUILD_GNU_TYPE` \
    --disable-shared \
    --prefix="$TOOLCHAIN/sysroot/usr/local"
make
make install
```