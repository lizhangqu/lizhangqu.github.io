title: NDK交叉编译常用变量
date: 2017-06-22 21:01:51
categories: [NDK]
tags: [NDK, 交叉编译]
---


总结一发NDK交叉编译的套路

<!-- more -->

### 工具说明

 - addr2line  把程序地址转换为文件名和行号。在命令行中给它一个地址和一个可执行文件名，它就会使用这个可执行文件的调试信息指出在给出的地址上是哪个文件以及行号。
 - ar  建立、修改、提取归档文件。归档文件是包含多个文件内容的一个大文件，其结构保证了可以恢复原始文件内容。
 - as  主要用来编译GNU C编译器gcc输出的汇编文件，产生的目标文件由连接器ld连接。
 - c++filt  连接器使用它来过滤 C++ 和 Java 符号，防止重载函数冲突。
 - gprof  显示程序调用段的各种数据。
 - ld  是连接器，它把一些目标和归档文件结合在一起，重定位数据，并连接符号引用。通常，建立一个新编译程序的最后一步就是调用ld。
 - nm  列出目标文件中的符号。
 - objcopy  把一种目标文件中的内容复制到另一种类型的目标文件中。
 - objdump  显示一个或者更多目标文件的信息。使用选项来控制其显示的信息，它所显示的信息通常只有编写编译工具的人才感兴趣。
 - ranlib  产生归档文件索引，并将其保存到这个归档文件中。在索引中列出了归档文件各成员所定义的可重分配目标文件。
 - readelf  显示elf格式可执行文件的信息。
 - size  列出目标文件每一段的大小以及总体的大小。默认情况下，对于每个目标文件或者一个归档文件中的每个模块只产生一行输出。
 - strings  打印某个文件的可打印字符串，这些字符串最少4个字符长，也可以使用选项-n设置字符串的最小长度。默认情况下，它只打印目标文件初始化和可加载段中的可打印字符；对于其它类型的文件它打印整个文件的可打印字符。这个程序对于了解非文本文件的内容很有帮助。
 - strip  丢弃目标文件中的全部或者特定符号。

### make 环境变量 

 见 [https://www.gnu.org/software/make/manual/html_node/Implicit-Variables.html](https://www.gnu.org/software/make/manual/html_node/Implicit-Variables.html)

### 通用脚本

```
#ANDROID_HOME目录下存在交叉编译工具链toolchain目录，由make-standalone-toolchain.sh生成

# 各cpu架构的参数见下方
$ANDROID_NDK/build/tools/make-standalone-toolchain.sh --arch=arm --install-dir=./toolchain
TOOL=arm-linux-androideabi

ANDROID_HOME=`pwd`
TOOLCHAIN=$ANDROID_HOME/toolchain

PKG_CONFIG_LIBDIR=$TOOLCHAIN/lib/pkgconfig
CC=$TOOLCHAIN/bin/$TOOL-gcc
CXX=$TOOLCHAIN/bin/$TOOL-g++
LINK=$CXX
LD=$TOOLCHAIN/bin/$TOOL-ld
AR=$TOOLCHAIN/bin/$TOOL-ar
AS=$TOOLCHAIN/bin/$TOOL-as
NM=$TOOLCHAIN/bin/$TOOL-nm
RANLIB=$TOOLCHAIN/bin/$TOOL-ranlib
STRIP=$TOOLCHAIN/bin/$TOOL-strip
OBJDUMP=$TOOLCHAIN/bin/$TOOL-objdump
OBJCOPE=$TOOLCHAIN/bin/$TOOL-objcopy
ADDR2LINE=$TOOLCHAIN/bin/$TOOL-addr2line
ELFEDIT=$TOOLCHAIN/bin/$TOOL-elfedit
READELF=$TOOLCHAIN/bin/$TOOL-readelf
SIZE=$TOOLCHAIN/bin/$TOOL-size
STRINGS=$TOOLCHAIN/bin/$TOOL-strings



export PKG_CONFIG_LIBDIR CC CXX LINK LD AR AS NM RANLIB STRIP OBJDUMP OBJCOPE ADDR2LINE ELFEDIT READELF SIZE STRINGS

# 各cpu架构的参数见下方
ARCH_FLAGS="-mthumb"
ARCH_LINK=

CFLAGS="${ARCH_FLAGS} -fpic -ffunction-sections -funwind-tables -fstack-protector -fno-strict-aliasing -finline-limit=64"
CXXFLAGS="${CFLAGS} -frtti -fexceptions"
LDFLAGS="${ARCH_LINK}"
ARFLAGS=
LIBS=

export CFLAGS CXXFLAGS LDFLAGS LIBS

#CFLAGS：表示用于 C 编译器的选项。
#如指定头文件（.h文件）的路径，如：CFLAGS=-I/usr/include -I/path/include。同样地，安装一个包时会在安装路径下建立一个include目录，当安装过程中出现问题时，试着把以前安装的包的include目录加入到该变量中来。
#CXXFLAGS：表示用于 C++ 编译器的选项。
#如执行三级优化 CXXFLAGS="-O3"
#LDFLAGS：gcc 等编译器会用到的一些链接参数，也可以在里面指定库文件的位置。用法：LDFLAGS=-L/usr/lib -L/path/to/your/lib。每安装一个包都几乎一定的会在安装目录里建立一个lib目录。如果明明安装了某个包，而安装另一个包时，它却是说找不到，可以将那个包的lib路径加入的LDFALGS中试一下。
#LIBS：告诉链接器要链接哪些库文件，如LIBS = -lpthread -liconv -llibz -llog
#LDFLAGS是告诉链接器从哪里寻找库文件，而LIBS是告诉链接器要链接哪些库文件


autoreconf -i
./configure --prefix=$TOOLCHAIN/sysroot/usr/local \
			--with-sysroot=$TOOLCHAIN/sysroot
			--host=$TOOL
			--enable_shared
			--enable_static

make -j4
make install
make uninstall
```

armeabi

```
$ANDROID_NDK/build/tools/make-standalone-toolchain.sh --arch=arm --install-dir=./toolchain
TOOL=arm-linux-androideabi
ARCH_FLAGS="-mthumb"
ARCH_LINK=
```

armeabi-v7a

```
$ANDROID_NDK/build/tools/make-standalone-toolchain.sh --arch=arm --install-dir=./toolchain
TOOL=arm-linux-androideabi
ARCH_FLAGS="-march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3-d16"
ARCH_LINK="-march=armv7-a -Wl,--fix-cortex-a8"
```

arm64-v8a

```
$ANDROID_NDK/build/tools/make-standalone-toolchain.sh --arch=arm64 --install-dir=./toolchain
TOOL=aarch64-linux-android
ARCH_FLAGS=
ARCH_LINK=
```

x86

```
$ANDROID_NDK/build/tools/make-standalone-toolchain.sh --arch=x86 --install-dir=./toolchain
TOOL=x86-linux-android
ARCH_FLAGS="-march=i686 -msse3 -mstackrealign -mfpmath=sse"
ARCH_LINK=
```

x86_64

```
$ANDROID_NDK/build/tools/make-standalone-toolchain.sh --arch=x86_64 --install-dir=./toolchain
TOOL="x86_64-linux-android"
ARCH_FLAGS="-march=x86-64 -msse4.2 -mpopcnt -m64 -mtune=intel"
ARCH_LINK=""
```

mips

```
$ANDROID_NDK/build/tools/make-standalone-toolchain.sh --arch=mips --install-dir=./toolchain
TOOL=mipsel-linux-android
ARCH_FLAGS=
ARCH_LINK=
```

mips64

```
$ANDROID_NDK/build/tools/make-standalone-toolchain.sh --arch=mips64 --install-dir=./toolchain
TOOL=mips64-linux-android
ARCH_FLAGS=
ARCH_LINK=
```

