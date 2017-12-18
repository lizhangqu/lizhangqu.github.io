title: Ubuntu使用ming-w64交叉编译Windows可执行文件
date: 2017-12-18 10:27:16
categories: [Android]
tags: [Ubuntu, ming-w64, 交叉编译, windows]
---

最近需要对AOSP上的aapt和aapt2进行自定义，但是AOSP的整个源码树过大，完整释放后约200G，不大适合整个拉下来编译，因此对构建环境进行精简，只拉取aapt和aapt2的关键依赖项目，使用cmake进行编译，整个移植过程很顺利，并且成功的编译出了mac和linux的可执行文件和对应的动态库，包括x86和x86_64的文件，但是在编译windows的版本的时候，遇到了一点小问题，就是AOSP上的依赖项目，存在软链接，但是windows系统是不支持软链接的，因此不能在windows上进行编译。

<!-- more -->

对于windows不支持软链接，其实有两种处理方式：
  1. 手动拷贝对应软链接文件到对应的目录，显然这是很不明智的选择，因为文件太大了
  2. 不在windows上进行编译，选择linux下交叉编译windows可执行文件。我这里选择的就是这一种。


### 安装依赖

由于要进行交叉编译，因此需要安装交叉编译工具链mingw-w64

```
sudo apt-get install mingw-w64
```

安装完成后，mingw-gcc和mingw-g++默认使用的线程模型是win32的，但是我们需要使用posix的线程模型，因此分别执行以下命令，然后将工具链指向带-posix后缀的工具链

```
sudo update-alternatives --config x86_64-w64-mingw32-gcc
sudo update-alternatives --config x86_64-w64-mingw32-g++
sudo update-alternatives --config x86_64-w64-mingw32-gfortran
sudo update-alternatives --config x86_64-w64-mingw32-gnat

sudo update-alternatives --config i686-w64-mingw32-gcc
sudo update-alternatives --config i686-w64-mingw32-g++
sudo update-alternatives --config i686-w64-mingw32-gfortran
sudo update-alternatives --config i686-w64-mingw32-gnat
```

### 编写cmake交叉编译脚本

参考之前写的一篇文章[Mac生成Linux交叉编译工具链](/2017/08/18/Mac生成Linux交叉编译工具链/)，编写cmake交叉编译脚本，创建windows.toolchain.cmake文件，里面的内容为：

```
# 安装 mingw-w64
# sudo apt-get install mingw-w64
# windows 64位操作系统
# -DCMAKE_TOOLCHAIN_FILE=windows.toolchain.cmake
# windows 32位操作系统
# -DCMAKE_TOOLCHAIN_FILE=windows.toolchain.cmake -DUSE_32BITS=1

set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_VERSION 1)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

set(CMAKE_C_COMPILER   x86_64-w64-mingw32-gcc)
set(CMAKE_CXX_COMPILER x86_64-w64-mingw32-g++)
SET(CMAKE_RC_COMPILER  x86_64-w64-mingw32-windres)
set(CMAKE_AR           x86_64-w64-mingw32-ar CACHE FILEPATH "Archiver")
set(CMAKE_RANLIB       x86_64-w64-mingw32-ranlib CACHE FILEPATH "Ranlib")
set(CMAKE_ASM_COMPILER x86_64-w64-mingw32-as)
set(CMAKE_LINKER       x86_64-w64-mingw32-ld)
set(CMAKE_NM           x86_64-w64-mingw32-nm)
set(CMAKE_OBJCOPY      x86_64-w64-mingw32-objcopy)
set(CMAKE_OBJDUMP      x86_64-w64-mingw32-objdump)
set(CMAKE_STRIP        x86_64-w64-mingw32-strip)

message(STATUS "CMAKE_C_COMPILER = ${CMAKE_C_COMPILER}")
message(STATUS "CMAKE_CXX_COMPILER = ${CMAKE_CXX_COMPILER}")
message(STATUS "CMAKE_AR = ${CMAKE_AR}")
message(STATUS "CMAKE_RANLIB = ${CMAKE_RANLIB}")
message(STATUS "CMAKE_ASM_COMPILER = ${CMAKE_ASM_COMPILER}")
message(STATUS "CMAKE_LINKER = ${CMAKE_LINKER}")
message(STATUS "CMAKE_NM = ${CMAKE_NM}")
message(STATUS "CMAKE_OBJCOPY = ${CMAKE_OBJCOPY}")
message(STATUS "CMAKE_OBJDUMP = ${CMAKE_OBJDUMP}")
message(STATUS "CMAKE_STRIP = ${CMAKE_STRIP}")

# Set or retrieve the cached flags.
# This is necessary in case the user sets/changes flags in subsequent
# configures. If we included the flags in here, they would get
# overwritten.
set(CMAKE_C_FLAGS ""
        CACHE STRING "Flags used by the compiler during all build types.")
set(CMAKE_CXX_FLAGS ""
        CACHE STRING "Flags used by the compiler during all build types.")
set(CMAKE_ASM_FLAGS ""
        CACHE STRING "Flags used by the compiler during all build types.")
set(CMAKE_C_FLAGS_DEBUG ""
        CACHE STRING "Flags used by the compiler during debug builds.")
set(CMAKE_CXX_FLAGS_DEBUG ""
        CACHE STRING "Flags used by the compiler during debug builds.")
set(CMAKE_ASM_FLAGS_DEBUG ""
        CACHE STRING "Flags used by the compiler during debug builds.")
set(CMAKE_C_FLAGS_RELEASE ""
        CACHE STRING "Flags used by the compiler during release builds.")
set(CMAKE_CXX_FLAGS_RELEASE ""
        CACHE STRING "Flags used by the compiler during release builds.")
set(CMAKE_ASM_FLAGS_RELEASE ""
        CACHE STRING "Flags used by the compiler during release builds.")
set(CMAKE_MODULE_LINKER_FLAGS ""
        CACHE STRING "Flags used by the linker during the creation of modules.")
set(CMAKE_SHARED_LINKER_FLAGS ""
        CACHE STRING "Flags used by the linker during the creation of dll's.")
set(CMAKE_EXE_LINKER_FLAGS ""
        CACHE STRING "Flags used by the linker.")

set(CMAKE_C_FLAGS             "${CMAKE_C_FLAGS}")
set(CMAKE_CXX_FLAGS           "${CMAKE_CXX_FLAGS}")
set(CMAKE_ASM_FLAGS           "${CMAKE_ASM_FLAGS}")
set(CMAKE_C_FLAGS_DEBUG       "${CMAKE_C_FLAGS_DEBUG}")
set(CMAKE_CXX_FLAGS_DEBUG     "${CMAKE_CXX_FLAGS_DEBUG}")
set(CMAKE_ASM_FLAGS_DEBUG     "${CMAKE_ASM_FLAGS_DEBUG}")
set(CMAKE_C_FLAGS_RELEASE     "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_RELEASE   "${CMAKE_CXX_FLAGS_RELEASE}")
set(CMAKE_ASM_FLAGS_RELEASE   "${CMAKE_ASM_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS}")
set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS}")
set(CMAKE_EXE_LINKER_FLAGS    "${CMAKE_EXE_LINKER_FLAGS}")

set(CMAKE_FIND_ROOT_PATH /usr/x86_64-w64-mingw32)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLYONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)
#make VERVOSE=1 to output the log
```

### 优化cmake交叉编译脚本支持32位可执行文件

上面的只能编译出64位的文件，要想编译出32位的文件，需要使用i686开头的工具链，因此，可以简单的通过参数进行控制是使用64位还是32位的，优化后的cmake脚本如下

```
# 安装 mingw-w64
# sudo apt-get install mingw-w64
# windows 64位操作系统
# -DCMAKE_TOOLCHAIN_FILE=windows.toolchain.cmake
# windows 32位操作系统
# -DCMAKE_TOOLCHAIN_FILE=windows.toolchain.cmake -DUSE_32BITS=1

set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_VERSION 1)
if(USE_32BITS)
    message(STATUS "using 32bits")
    set(CMAKE_SYSTEM_PROCESSOR x86)
else()
    set(CMAKE_SYSTEM_PROCESSOR x86_64)
endif(USE_32BITS)

if(USE_32BITS)
    set(CMAKE_C_COMPILER   i686-w64-mingw32-gcc)
    set(CMAKE_CXX_COMPILER i686-w64-mingw32-g++)
    SET(CMAKE_RC_COMPILER  i686-w64-mingw32-windres)
    set(CMAKE_AR           i686-w64-mingw32-ar CACHE FILEPATH "Archiver")
    set(CMAKE_RANLIB       i686-w64-mingw32-ranlib CACHE FILEPATH "Ranlib")
    set(CMAKE_ASM_COMPILER i686-w64-mingw32-as)
    set(CMAKE_LINKER       i686-w64-mingw32-ld)
    set(CMAKE_NM           i686-w64-mingw32-nm)
    set(CMAKE_OBJCOPY      i686-w64-mingw32-objcopy)
    set(CMAKE_OBJDUMP      i686-w64-mingw32-objdump)
    set(CMAKE_STRIP        i686-w64-mingw32-strip)
else()
    set(CMAKE_C_COMPILER   x86_64-w64-mingw32-gcc)
    set(CMAKE_CXX_COMPILER x86_64-w64-mingw32-g++)
    SET(CMAKE_RC_COMPILER  x86_64-w64-mingw32-windres)
    set(CMAKE_AR           x86_64-w64-mingw32-ar CACHE FILEPATH "Archiver")
    set(CMAKE_RANLIB       x86_64-w64-mingw32-ranlib CACHE FILEPATH "Ranlib")
    set(CMAKE_ASM_COMPILER x86_64-w64-mingw32-as)
    set(CMAKE_LINKER       x86_64-w64-mingw32-ld)
    set(CMAKE_NM           x86_64-w64-mingw32-nm)
    set(CMAKE_OBJCOPY      x86_64-w64-mingw32-objcopy)
    set(CMAKE_OBJDUMP      x86_64-w64-mingw32-objdump)
    set(CMAKE_STRIP        x86_64-w64-mingw32-strip)
endif(USE_32BITS)

message(STATUS "CMAKE_C_COMPILER = ${CMAKE_C_COMPILER}")
message(STATUS "CMAKE_CXX_COMPILER = ${CMAKE_CXX_COMPILER}")
message(STATUS "CMAKE_AR = ${CMAKE_AR}")
message(STATUS "CMAKE_RANLIB = ${CMAKE_RANLIB}")
message(STATUS "CMAKE_ASM_COMPILER = ${CMAKE_ASM_COMPILER}")
message(STATUS "CMAKE_LINKER = ${CMAKE_LINKER}")
message(STATUS "CMAKE_NM = ${CMAKE_NM}")
message(STATUS "CMAKE_OBJCOPY = ${CMAKE_OBJCOPY}")
message(STATUS "CMAKE_OBJDUMP = ${CMAKE_OBJDUMP}")
message(STATUS "CMAKE_STRIP = ${CMAKE_STRIP}")

# Set or retrieve the cached flags.
# This is necessary in case the user sets/changes flags in subsequent
# configures. If we included the flags in here, they would get
# overwritten.
set(CMAKE_C_FLAGS ""
        CACHE STRING "Flags used by the compiler during all build types.")
set(CMAKE_CXX_FLAGS ""
        CACHE STRING "Flags used by the compiler during all build types.")
set(CMAKE_ASM_FLAGS ""
        CACHE STRING "Flags used by the compiler during all build types.")
set(CMAKE_C_FLAGS_DEBUG ""
        CACHE STRING "Flags used by the compiler during debug builds.")
set(CMAKE_CXX_FLAGS_DEBUG ""
        CACHE STRING "Flags used by the compiler during debug builds.")
set(CMAKE_ASM_FLAGS_DEBUG ""
        CACHE STRING "Flags used by the compiler during debug builds.")
set(CMAKE_C_FLAGS_RELEASE ""
        CACHE STRING "Flags used by the compiler during release builds.")
set(CMAKE_CXX_FLAGS_RELEASE ""
        CACHE STRING "Flags used by the compiler during release builds.")
set(CMAKE_ASM_FLAGS_RELEASE ""
        CACHE STRING "Flags used by the compiler during release builds.")
set(CMAKE_MODULE_LINKER_FLAGS ""
        CACHE STRING "Flags used by the linker during the creation of modules.")
set(CMAKE_SHARED_LINKER_FLAGS ""
        CACHE STRING "Flags used by the linker during the creation of dll's.")
set(CMAKE_EXE_LINKER_FLAGS ""
        CACHE STRING "Flags used by the linker.")

set(CMAKE_C_FLAGS             "${CMAKE_C_FLAGS}")
set(CMAKE_CXX_FLAGS           "${CMAKE_CXX_FLAGS}")
set(CMAKE_ASM_FLAGS           "${CMAKE_ASM_FLAGS}")
set(CMAKE_C_FLAGS_DEBUG       "${CMAKE_C_FLAGS_DEBUG}")
set(CMAKE_CXX_FLAGS_DEBUG     "${CMAKE_CXX_FLAGS_DEBUG}")
set(CMAKE_ASM_FLAGS_DEBUG     "${CMAKE_ASM_FLAGS_DEBUG}")
set(CMAKE_C_FLAGS_RELEASE     "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_RELEASE   "${CMAKE_CXX_FLAGS_RELEASE}")
set(CMAKE_ASM_FLAGS_RELEASE   "${CMAKE_ASM_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS}")
set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS}")
set(CMAKE_EXE_LINKER_FLAGS    "${CMAKE_EXE_LINKER_FLAGS}")

if(USE_32BITS)
    set(CMAKE_FIND_ROOT_PATH /usr/i686-w64-mingw32)
else()
    set(CMAKE_FIND_ROOT_PATH /usr/x86_64-w64-mingw32)
endif(USE_32BITS)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLYONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)
#make VERVOSE=1 to output the log
```

### 生成cmake构建文件

如果生成64的构建文件，则使用

```
cmake -H"./" -B"./build-cmake-windows" -DCMAKE_BUILD_TYPE=MinSizeRel -DCMAKE_TOOLCHAIN_FILE=windows.toolchain.cmake

```

但是如果需要生产32位的构建文件，则需要传递USE_32BITS=1参数，如下

```
cmake -H"./" -B"./build-cmake-windows-x86" -DCMAKE_BUILD_TYPE=MinSizeRel -DCMAKE_TOOLCHAIN_FILE=windows.toolchain.cmake -DUSE_32BITS=1
```

### mac下编译

mac下可使用brew install mingw-w64安装mingw-w64，但是安装出来的mingw-w64线程模型是win32的，而我们需要使用posix线程模型，因此如果要想在mac下进行编译，则需要自己编译mingw-w64，启用posix线程模型，有兴趣可以自行研究。
