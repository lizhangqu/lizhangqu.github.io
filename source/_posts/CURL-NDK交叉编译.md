title: CURL NDK交叉编译
date: 2017-05-24 19:17:06
categories: [NDK]
tags: [NDK, curl, 交叉编译]
---

移植curl到android，且支持https和http2.0

依赖前两篇文章
 - [libnghttp2 NDK 交叉编译](http://fucknmb.com/2017/05/24/libnghttp2-NDK%E4%BA%A4%E5%8F%89%E7%BC%96%E8%AF%91/)
 - [openssl NDK 交叉编译](http://fucknmb.com/2017/05/24/openssl-NDK%E4%BA%A4%E5%8F%89%E7%BC%96%E8%AF%91/)
<!-- more -->

创建工作目录，并进入

```
mkdir android
cd android
```

下载源码
```
wget https://curl.haxx.se/download/curl-7.53.1.tar.gz
tar xfz url-7.53.1.tar.gz
```

生成交叉编译工具链
```
$ANDROID_NDK/build/tools/make-standalone-toolchain.sh --arch=arm --install-dir=./toolchain
```

导出环境变量(armeabi)

```
export ANDROID_HOME=`pwd`
export TOOLCHAIN=$ANDROID_HOME/toolchain
export PKG_CONFIG_LIBDIR=$TOOLCHAIN/lib/pkgconfig
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
cd curl-7.53.1
./configure --prefix=$TOOLCHAIN/sysroot/usr/local \
       --with-sysroot=$TOOLCHAIN/sysroot \
       --host=arm-linux-androideabi \
       --with-ssl=$TOOLCHAIN/sysroot/usr/local \
       --with-nghttp2=$TOOLCHAIN/sysroot/usr/local \
       --enable-ipv6 \
       --enable-static \
       --enable-threaded-resolver \
       --disable-dict \
       --disable-gopher \
       --disable-ldap --disable-ldaps \
       --disable-manual \
       --disable-pop3 --disable-smtp --disable-imap \
       --disable-rtsp \
       --disable-shared \
       --disable-smb \
       --disable-telnet \
       --disable-verbose
make -j4
make install
```


armeabi-v7a

```
$ANDROID_NDK/build/tools/make-standalone-toolchain.sh --arch=arm --install-dir=./toolchain
export TOOL=arm-linux-androideabi
export ARCH_FLAGS="-march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3-d16"
export ARCH_LINK="-march=armv7-a -Wl,--fix-cortex-a8"

./configure --prefix=$TOOLCHAIN/sysroot/usr/local \
       --with-sysroot=$TOOLCHAIN/sysroot \
       --host=arm-linux-androideabi \
       --with-ssl=$TOOLCHAIN/sysroot/usr/local \
       --with-nghttp2=$TOOLCHAIN/sysroot/usr/local \
       --enable-ipv6 \
       --enable-static \
       --enable-threaded-resolver \
       --disable-dict \
       --disable-gopher \
       --disable-ldap --disable-ldaps \
       --disable-manual \
       --disable-pop3 --disable-smtp --disable-imap \
       --disable-rtsp \
       --disable-shared \
       --disable-smb \
       --disable-telnet \
       --disable-verbose
```

x86

```
$ANDROID_NDK/build/tools/make-standalone-toolchain.sh --arch=x86 --install-dir=./toolchain
export TOOL=x86-linux-android
export ARCH_FLAGS="-march=i686 -msse3 -mstackrealign -mfpmath=sse"
export ARCH_LINK=""

./configure --prefix=$TOOLCHAIN/sysroot/usr/local \
       --with-sysroot=$TOOLCHAIN/sysroot \
       --host=x86-linux-androideabi \
       --with-ssl=$TOOLCHAIN/sysroot/usr/local \
       --with-nghttp2=$TOOLCHAIN/sysroot/usr/local \
       --enable-ipv6 \
       --enable-static \
       --enable-threaded-resolver \
       --disable-dict \
       --disable-gopher \
       --disable-ldap --disable-ldaps \
       --disable-manual \
       --disable-pop3 --disable-smtp --disable-imap \
       --disable-rtsp \
       --disable-shared \
       --disable-smb \
       --disable-telnet \
       --disable-verbose
```



