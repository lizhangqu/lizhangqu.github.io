title: openssl NDK交叉编译
date: 2017-05-24 18:39:31
categories: [NDK]
tags: [NDK, openssl, 交叉编译]
---

移植openssl到android

<!-- more -->

创建工作目录，并进入

```
mkdir android
cd android
```

下载源码

```
wget https://www.openssl.org/source/openssl-1.1.0e.tar.gz
tar xfz openssl-1.1.0e.tar.gz
```

生成交叉编译工具链

```
$ANDROID_NDK/build/tools/make-standalone-toolchain.sh --arch=arm --install-dir=./toolchain
```



导出环境变量（armeabi）

```
export ANDROID_HOME=`pwd`
export TOOLCHAIN=$ANDROID_HOME/toolchain
export CROSS_SYSROOT=$TOOLCHAIN/sysroot
export PATH=$TOOLCHAIN/bin:$PATH
export TOOL=arm-linux-androideabi
export CC=$TOOLCHAIN/bin/${TOOL}-gcc
export CXX=$TOOLCHAIN/bin/${TOOL}-g++
export LINK=${CXX}
export LD=$TOOLCHAIN/bin/${TOOL}-ld
export AR=$TOOLCHAIN/bin/${TOOL}-ar
export RANLIB=$TOOLCHAIN/bin/${TOOL}-ranlib
export STRIP=$TOOLCHAIN/bin/${TOOL}-strip
export ARCH_FLAGS="-mthumb"
export ARCH_LINK=
export CFLAGS="${ARCH_FLAGS} -fpic -ffunction-sections -funwind-tables -fstack-protector -fno-strict-aliasing -finline-limit=64"
export CXXFLAGS="${CFLAGS} -frtti -fexceptions"
export LDFLAGS="${ARCH_LINK}"
```

编译并安装

```
cd openssl-1.1.0e/
./Configure android \
          --prefix=$TOOLCHAIN/sysroot/usr/local \
          --with-zlib-include=$TOOLCHAIN/sysroot/usr/include \
          --with-zlib-lib=$TOOLCHAIN/sysroot/usr/lib \
          zlib \
          no-asm \
          no-shared \
          no-unit-test
make -j4
make install
```

卸载

```
make uninstall
```


armeabi-v7a

```
$ANDROID_NDK/build/tools/make-standalone-toolchain.sh --arch=arm --install-dir=./toolchain
export TOOL=arm-linux-androideabi
export ARCH_FLAGS="-march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3-d16"
export ARCH_LINK="-march=armv7-a -Wl,--fix-cortex-a8"

./Configure android-armv7 \
          --prefix=$TOOLCHAIN/sysroot/usr/local \
          --with-zlib-include=$TOOLCHAIN/sysroot/usr/include \
          --with-zlib-lib=$TOOLCHAIN/sysroot/usr/lib \
          zlib \
          no-asm \
          no-shared \
          no-unit-test
```

x86

```
$ANDROID_NDK/build/tools/make-standalone-toolchain.sh --arch=x86 --install-dir=./toolchain
export TOOL=i686-linux-android
export ARCH_FLAGS="-march=i686 -msse3 -mstackrealign -mfpmath=sse"
export ARCH_LINK=""

./Configure android-x86 \
          --prefix=$TOOLCHAIN/sysroot/usr/local \
          --with-zi686lib-include=$TOOLCHAIN/sysroot/usr/include \
          --with-zlib-lib=$TOOLCHAIN/sysroot/usr/lib \
          zlib \
          no-asm \
          no-shared \
          no-unit-test
```


何大仙提供的shell脚本

```
#!/bin/sh

if [ ! -f "openssl-1.1.0e.tar.gz" ]; then
    wget https://www.openssl.org/source/openssl-1.1.0e.tar.gz
fi

if [ ! -d "openssl-1.1.0e" ]; then 
    tar zxf openssl-1.1.0e.tar.gz
fi

# env
if [ -d "out/openssl" ]; then
    rm -fr "out/openssl"
fi

mkdir "out"
mkdir "out/openssl"

_compile() {
    SURFIX=$1
    TOOL=$2
    ARCH_FLAGS=$3
    ARCH_LINK=$4
    CFGNAME=$5
    ARCH=$6

    if [ ! -d "out/openssl/${SURFIX}" ]; then
        mkdir "out/openssl/${SURFIX}" 
    fi

    if [ ! -d "toolchain_${SURFIX}" ]; then
        $ANDROID_NDK/build/tools/make-standalone-toolchain.sh --arch=${ARCH} --install-dir=./toolchain_${SURFIX}
    fi
    export ANDROID_HOME=`pwd`
    export TOOLCHAIN=$ANDROID_HOME/toolchain_${SURFIX}
    export CROSS_SYSROOT=$TOOLCHAIN/sysroot
    export PATH=$TOOLCHAIN/bin:$PATH
    export CC=$TOOLCHAIN/bin/${TOOL}-gcc
    export CXX=$TOOLCHAIN/bin/${TOOL}-g++
    export LINK=${CXX}
    export LD=$TOOLCHAIN/bin/${TOOL}-ld
    export AR=$TOOLCHAIN/bin/${TOOL}-ar
    export RANLIB=$TOOLCHAIN/bin/${TOOL}-ranlib
    export STRIP=$TOOLCHAIN/bin/${TOOL}-strip
    export ARCH_FLAGS=$ARCH_FLAGS
    export ARCH_LINK=$ARCH_LINK
    export CFLAGS="${ARCH_FLAGS} -fpic -ffunction-sections -funwind-tables -fstack-protector -fno-strict-aliasing -finline-limit=64"
    export CXXFLAGS="${CFLAGS} -frtti -fexceptions"
    export LDFLAGS="${ARCH_LINK}"


    cd openssl-1.1.0e/
    ./Configure ${CFGNAME} --prefix=$TOOLCHAIN/sysroot/usr/local --with-zlib-include=$TOOLCHAIN/sysroot/usr/include --with-zlib-lib=$TOOLCHAIN/sysroot/usr/lib zlib no-asm no-shared no-unit-test
    make clean
    make -j4
    #make install
    make install_sw
    make install_ssldirs
    cd ..
    mv openssl-1.1.0e/libssl.a out/openssl/${SURFIX}/ 
    mv openssl-1.1.0e/libcrypto.a out/openssl/${SURFIX}/
}


# arm
_compile "armeabi" "arm-linux-androideabi" "-mthumb" "" "android" "arm"

# armv7
_compile "armeabi-v7a" "arm-linux-androideabi" "-march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3-d16" "-march=armv7-a -Wl,--fix-cortex-a8" "android-armeabi" "arm"

# arm64v8
_compile "arm64-v8a" "aarch64-linux-android" "" "" "android64-aarch64" "arm64"

# x86
_compile "x86" "i686-linux-android" "-march=i686 -m32 -msse3 -mstackrealign -mfpmath=sse -mtune=intel" "" "android-x86" "x86"

# x86_64
_compile "x86_64" "x86_64-linux-android" "-march=x86-64 -m64 -msse4.2 -mpopcnt  -mtune=intel" "" "android64" "x86_64"

# mips
_compile "mips" "mipsel-linux-android" "" "" "android-mips" "mips"

# mips64
_compile "mips64" "mips64el-linux-android" "" "" "linux64-mips64" "mips64"

echo "done"


```

