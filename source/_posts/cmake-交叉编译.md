title: cmake 交叉编译
date: 2017-06-27 21:29:06
categories: [cmake]
tags: [cmake, Android，ndk]
---


### 前言

#### Android交叉编译工具链

 - [google官方出的android.toolchain.cmake](https://android.googlesource.com/platform/tools/cmake-utils/+/cmake-master-dev/android.toolchain.cmake)
 - [第三方android-cmake，可以被android.toolchain.cmake兼容](https://github.com/taka-no-me/android-cmake)
http://gitlab.vdian.net/WD-INPUT/toolchain/

#### iOS交叉编译工具链

 - [cristeab/ios-cmake，两三年没更新了](https://github.com/cristeab/ios-cmake)
 - [leetal/ios-cmake，建议使用这个](https://github.com/leetal/ios-cmake)

<!-- more -->

### 交叉编译前的准备

clone项目到本地某个位置，android的可以直接使用ndk目录下的cmake，位于ndk/build/cmake/android.toolchain.cmake；iOS可以使用https://github.com/leetal/ios-cmake，将其clone到本地。
 
### Android交叉编译

 **android的cmake必须使用sdk目录下的cmake可执行文件，google对其修改了源码，如果使用系统的cmake，可能导致编译出错**

生成cmake编译所需的文件
```
#-H指向CMakeLists.txt文件父级目录
#-B指向中间产物目录
#-DCMAKE_LIBRARY_OUTPUT_DIRECTORY指向so输出目录
#-DCMAKE_TOOLCHAIN_FILE指向android.toolchain.cmake文件，可以使用ndk自带的，也可以使用clone下来的项目中的文件
#-DANDROID_NDK指向ndk目录
#-DANDROID_ABI定义目标cpu结构，取值armeabi，armeabi-v7a，arm64-v8a，x86，x86_64，mips，mips64中的一个
#-DCMAKE_BUILD_TYPE定义构建类型，取值Debug或Release，Release构建做-O3三级优化
#-DANDROID_PLATFORM定义最低api版本
#-DANDROID_TOOLCHAIN表示交叉编译链类型，取值gcc或者clang，gcc已经被废弃
#-DANDROID_STL指明使用的stl
#-DCMAKE_C_FLAGS代表c编译器参数
#-DCMAKE_CXX_FLAGS代表c++编译器参数
#更多参数见google官方文档 https://developer.android.com/ndk/guides/cmake.html
#如果需要使用ninja构建，追加-GAndroid Gradle - Ninja参数，该参数标准cmake可执行文件不支持，只有sdk下的cmake支持
 
/Users/lizhangqu/AndroidSDK/cmake/3.6.3155560/bin/cmake \
-H"../jni" \
-B"../build/android/armeabi-v7a" \
-DANDROID_ABI="armeabi-v7a" \
-DANDROID_NDK="/Users/lizhangqu/AndroidNDK/android-ndk-r14b" \
-DCMAKE_LIBRARY_OUTPUT_DIRECTORY="../build/android/libs/armeabi-v7a" \
-DCMAKE_BUILD_TYPE="Release" \
-DCMAKE_TOOLCHAIN_FILE="/Users/lizhangqu/AndroidNDK/android-ndk-r14b/build/cmake/android.toolchain.cmake" \
-DANDROID_PLATFORM="android-14" \
-DANDROID_TOOLCHAIN="clang" \
-DCMAKE_C_FLAGS="-fpic -fexceptions -frtti" \
-DCMAKE_CXX_FLAGS="-fpic -fexceptions -frtti" \
-DANDROID_STL="c++_static" \
#-GAndroid Gradle - Ninja  #需要支持自行打开注释
```
 
clean及构建目标产物
```
#--build代表cmake生成的中间产物目录，即上面-B指定的目录
#--target代表构建哪个target
#-- -j4代表执行make的时候追加-j4，并行编译
 
#clean 
 
/Users/lizhangqu/AndroidSDK/cmake/3.6.3155560/bin/cmake \
--build "../build/android/armeabi-v7a" \
--target clean
 
# build your target
/Users/lizhangqu/AndroidSDK/cmake/3.6.3155560/bin/cmake \
--build "../build/android/armeabi-v7a" \
--target 构建的目标target \
-- -j4
```


### iOS交叉编译

生成cmake编译所需的文件
```
#-H指向CMakeLists.txt文件父级目录
#-B指向中间产物目录
#-DCMAKE_BUILD_TYPE定义构建类型，取值Debug或Release，Release构建做-O3三级优化
#-DIOS_PLATFORM定义构建的目标平台，OS表示构建iPhoneOS所需的lib，SIMULATOR代表构建x86模拟器所需的lib，SIMULATOR64代表构建x86_64模拟器所需的lib
#-DCMAKE_TOOLCHAIN_FILE指向ios.toolchain.cmake文件，使用clone下来的项目中的文件
cmake \
-H"../jni" \
-B"../build/ios" \
-DCMAKE_BUILD_TYPE="Release" \
-DCMAKE_TOOLCHAIN_FILE="../toolchain/ios.toolchain.cmake" \
-DIOS_PLATFORM=OS
# IOS_PLATFORM
# OS = Build for iPhoneOS.
# SIMULATOR = Build for x86 i386 iPhone Simulator.
# SIMULATOR64 = Build for x86 x86_64 iPhone Simulator.
# CMAKE_BUILD_TYPE
# Debug or Release
```
 
clean及构建目标产物
```
#--build代表cmake生成的中间产物目录，即上面-B指定的目录
#--target代表构建哪个target
#-- -j4代表执行make的时候追加-j4，并行编译
 
#clean 
 
cmake \
--build "../build/android/armeabi-v7a" \
--target clean
 
 
# build your target
cmake \
--build "../build/ios" \
--target 构建的目标target \
-- -j4
```