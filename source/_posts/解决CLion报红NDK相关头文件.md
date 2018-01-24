title: 解决CLion报红NDK相关头文件
date: 2018-01-24 09:39:36
categories: [Android]
tags: [Android, NDK, Clion]
---

前几天遇到一个坑，就是Clion、Cmake、NDK在一起使用的时候，Clion会将NDK相关头文件报红，即找不到相关头文件，无法做到代码提示及自动补全，但是编译是可以通过的，google了一番，发现这个问题在2015年的时候就存在了，但是官方宣称已经修复了， 但是实际测试下来，并没有修复。相关链接见：

 - [Problem with include, parser is now broken with -DCMAKE_SYSTEM_NAME=Generic (MinGW)](https://youtrack.jetbrains.com/oauth?state=%2Fissue%2FCPP-3962)
 - [CLion fails to find some of my headers. Where does it search for them?](https://intellij-support.jetbrains.com/hc/en-us/articles/207253135-CLion-fails-to-find-some-of-my-headers-Where-does-it-search-for-them-)
 - [Cannot find the header in C](https://intellij-support.jetbrains.com/hc/en-us/community/posts/115000693804-Cannot-find-the-header-in-C)

<!-- more -->

发现遇到这个问题的人还是蛮多的，基本上都没有人能给出正确的解决方式。于是就不得不自己寻找解决方式。

既然官方宣称已经修复了，那么问题到底出在哪里呢？最终猜想和cmake相关，因为ndk需要用的cmake是google自己定制过的，其目录位于/path/to/AndroidSDK/cmake/目录下，当前的版本还是3.6.+，而CLion里使用的cmake已经到了3.9.6的版本，因此怀疑是cmake版本过低导致的。

先来看看，对于google自己定制过的cmake，如何在clion中进行集成。

 1，添加Toolchain；CLion -> Preferences -> Build, Execution, Deployment -> Toolchains -> 添加一个toolchain，将cmake路径指向AndroidSDK目录下的cmake，并命名为Android。如下图所示

![toolchain_add.png](toolchain_add.png)

 2，配置CMake；CLion -> Preferences -> Build, Execution, Deployment -> CMake -> 将Toolchain选择为刚才第一步添加的Android -> 添加CMake options选项，其内容从Android Studio产生的命令中可以看出，配置为如下内容

```
-DANDROID_ABI="armeabi-v7a"
-DANDROID_NDK="/Users/lizhangqu/AndroidNDK/android-ndk-r14b"
-DCMAKE_BUILD_TYPE="Release"
-DCMAKE_TOOLCHAIN_FILE="/Users/lizhangqu/AndroidNDK/android-ndk-r14b/build/cmake/android.toolchain.cmake"
-DANDROID_PLATFORM="android-14"
-DCMAKE_C_FLAGS=""
-DCMAKE_CXX_FLAGS=""
-DANDROID_TOOLCHAIN="clang"
```

最终的效果图如下

![toolchain_cmake.png](toolchain_cmake.png)

对于以上配置的Cmake Options，可以参考以下几篇文章

 - [cmake 交叉编译](/2017/06/27/cmake-交叉编译/)
 - [Android Gradle Plugin 源码解析之 externalNativeBuild](/2017/06/24/Android-Gradle-Plugin源码解析之externalNativeBuild/)

这样配置之后，就可以正常进行编译了，编译是完全ok的，但是代码提示和自动补全功能对于ndk相关的头文件，全部失效，如下图所示

![red.png](red.png)

所以个人猜测这个问题可能和cmake有关，于是将cmake换成CLion自带的版本，但是发现在生成cmake的相关文件时，生成就出错了，如下图所示

![error_cmake.png](error_cmake.png)

那么有没有一种方式，既可以进行代码提示，又可以不使用google定制的cmake呢，通过查找cmake相关文档发现，cmake在3.7之后，已经添加了对ndk交叉编译的支持了，也就是意味着我们完全可以在CLion中不使用google定制过的cmake。

cmake 3.6版本的交叉编译文档，地址见 [cmake-toolchains-3.6](https://cmake.org/cmake/help/v3.6/manual/cmake-toolchains.7.html)，具体目录如下

![cmake_3_6.png](cmake_3_6.png)

cmake 3.7版本及以后的交叉编译文档，地址见 [cmake-toolchains-3.7](https://cmake.org/cmake/help/v3.7/manual/cmake-toolchains.7.html)，从对应的目录中可以看出，多了Android这一选项，具体目录如下

![cmake_3_7.png](cmake_3_7.png)

从文档中可以看出，我们完全可以使用cmake 3.7之后自带的Android NDK工具链，而不使用google ndk的toolchain，为了达到最简单的配置，我们直接传递参数

```
-DCMAKE_SYSTEM_NAME=Android
-DCMAKE_ANDROID_ARCH_ABI=armeabi-v7a
-DCMAKE_ANDROID_NDK=/Users/lizhangqu/AndroidNDK/android-ndk-r14b
-DCMAKE_SYSTEM_VERSION=14
-DCMAKE_C_FLAGS=""
-DCMAKE_CXX_FLAGS=""
-DCMAKE_ANDROID_NDK_TOOLCHAIN_VERSION=clang
```

将以上cmake option配置到之前配置过的地方，将之前的配置的toolchain重新选择默认的CLion自带的cmake，如下图所示

![toolchain_default.png](toolchain_default.png)

然后重新生成cmake相关文件，再次查看是否可以自动补全以及是否还报红。

![no_red.png](no_red.png)

从上图可以看出问题已经被修复了~


总结：google挖了个深坑，凑巧我跳进了这个坑，clion和cmake都没有锅，这个锅他们不背，所以clion宣传已经修复该问题也不是没有道理的~
