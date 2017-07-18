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

卸载

```
make uninstall
```

何大仙提供的shell脚本

```
#!/bin/sh

if [ ! -d "nghttp2" ]; then
    git clone git@github.com:nghttp2/nghttp2.git
else
    cd nghttp2
    git pull
    cd ..
fi

# env
if [ -d "out/nghttp2" ]; then
    rm -fr "out/nghttp2"
fi

mkdir "out"
mkdir "out/nghttp2"

_compile() {
    SURFIX=$1
    TOOL=$2
    ARCH_FLAGS=$3
    ARCH_LINK=$4
    ARCH=$5

    if [ ! -d "out/nghttp2/${SURFIX}" ]; then
        mkdir "out/nghttp2/${SURFIX}"
    fi

    if [ ! -d "toolchain_${SURFIX}" ]; then
        $ANDROID_NDK/build/tools/make-standalone-toolchain.sh --arch=${ARCH} --install-dir=./toolchain_${SURFIX}
    fi

    export CURRENT_HOME=`pwd`
    export TOOLCHAIN=$CURRENT_HOME/toolchain_${SURFIX}
    export PATH=$TOOLCHAIN/bin:$PATH
    export PKG_CONFIG_LIBDIR=$TOOLCHAIN/lib/pkgconfig
    export ARCH_FLAGS=$ARCH_FLAGS
    export ARCH_LINK=$ARCH_LINK
    export CPPFLAGS="-fPIE -I$TOOLCHAIN/sysroot/usr/include"
    export LDFLAGS="-fPIE -pie -I$TOOLCHAIN/sysroot/usr/lib"

    cd nghttp2/
    autoreconf -i
    ./configure --enable-lib-only --host=${TOOL} --build=`dpkg-architecture -qDEB_BUILD_GNU_TYPE` --disable-shared --prefix="$TOOLCHAIN/sysroot/usr/local"
    make clean
    make -j4
    make install
    cd ..

    mv nghttp2/lib/.libs/libnghttp2.a out/nghttp2/${SURFIX}/
}

# arm
_compile "armeabi" "arm-linux-androideabi" "-mthumb" "" "arm"

# armv7
_compile "armeabi-v7a" "arm-linux-androideabi" "-march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3-d16" "-march=armv7-a -Wl,--fix-cortex-a8" "arm"

# arm64v8
_compile "arm64-v8a" "aarch64-linux-android" "" "" "arm64"

# x86
_compile "x86" "i686-linux-android" "-march=i686 -m32 -msse3 -mstackrealign -mfpmath=sse -mtune=intel" "" "x86"

# x86_64
_compile "x86_64" "x86_64-linux-android" "-march=x86-64 -m64 -msse4.2 -mpopcnt  -mtune=intel" "" "x86_64"

# mips
_compile "mips" "mipsel-linux-android" "" "" "mips"

# mips64
_compile "mips64" "mips64el-linux-android" "" "" "mips64"


echo "done"


```