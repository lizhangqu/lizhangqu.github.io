title: Flutter Engine C++源码调试初探
date: 2019-12-06 11:33:40
categories: [Flutter]
tags: [Flutter, Engine, LLDB, Debug, GDB, Andorid Studio, VSCode, Clion, Android]
---

>禁止转载，原文出处 https://fucknmb.com

在Flutter Engine的自定义过程中，难免会对其进行调试，所谓工欲善其事必先利其器。调试的手段有多种，一般以日志输出和断点调试为主。本篇文章主要介绍一下Android环境下使用LLDB对Flutter Engine C++部分源码进行调试，至于为什么不使用GDB，因为我没有用GDB成功过，环境搭建的过程中遇到的坑很多，需要耐心看完全文。[此处为人肉防盗文, 原文出处 https://fucknmb.com](https://fucknmb.com)
<!-- more -->


### 前言

纵观全网，截止发稿，你大致可以在google搜索到这么几篇关于Flutter Engine调试的文章。

  - [调试Flutter Native Engine初探](https://zhuanlan.zhihu.com/p/38626359)
  - [Visual Studio Code调试和查看Flutter Engine源代码](https://zhuanlan.zhihu.com/p/38787295)
  - [Flutter Engine源码调试](https://xinbaos.github.io/Flutter%20Engine%E6%BA%90%E7%A0%81%E8%B0%83%E8%AF%95/)

当然也不乏官方的调试文档

 - [Debugging the engine](https://github.com/flutter/flutter/wiki/Debugging-the-engine)

Flutter官方的文档很简陋，简陋到只用了一句话描述Android部分的GDB调试

>Debugging Android builds with gdb
See https://github.com/flutter/engine/blob/master/sky/tools/flutter_gdb#L13

当然我并没有使用该工具和GDB成功调试过Flutter Engine，因为调试过程中一直附加不上符号表，没有符号表自然断点也打不上，也不知道哪里出问题了。鉴于GDB比较古老，目前苹果和Google都已经使用LLDB替换了GDB，所以就不纠结GDB了，让我们开启LLDB的征程。

此处小结一下，目前全网找到的文章，调试方法的灵感基本都是源自此文

 - [如何调试Android Native Framework](http://weishu.me/2017/01/14/how-to-debug-android-native-framework-source/)

我们要站在巨人的肩膀上，充分利用现有资源，当然有时候巨人也不一定是对的，也包括此文中的一些观点不一定是对的。[此处为人肉防盗文, 原文出处 https://fucknmb.com](https://fucknmb.com)

### 源码编译

源码的编译并不是本篇文章的重点，可以参考之前写的一篇文章和官方文档进行编译：
   - [Flutter Engine 编译指北](/2019/02/26/Flutter-Engine-编译指北/)
   - [Setting up the Framework development environment](https://github.com/flutter/flutter/wiki/Setting-up-the-Framework-development-environment)
   - [Compiling the engine](https://github.com/flutter/flutter/wiki/Compiling-the-engine)

假设你已经通过如下方式编译好引擎
```
cd /path/to/engine/src
./flutter/tools/gn --android --runtime-mode=debug --unoptimized
./flutter/tools/gn --runtime-mode=debug --unoptimized
ninja -C out/android_debug_unopt
ninja -C out/host_debug_unopt
```

然后通过如下方式使用本地编译好的引擎编译apk

```
/path/to/flutter build apk \
--debug \
--target-platform=android-arm \
--local-engine-src-path=/Users/lizhangqu/software/flutter_dev/engine/src \
--local-engine=android_debug_unopt
```

当然你也可以在`gradle.properties`中加入如下配置直接使用`gradlew clean :app:installDebug`命令进行编译

```
target-platform=android-arm
localEngineOut=/Users/lizhangqu/software/flutter_dev/engine/src/out/android_debug_unopt
```

然后你成功的run起了你的apk

以上几步是下文的前提，请务必先编译好引擎。

在开始之前，我们做如下假设
 - 假设你的引擎源码目录为/Users/lizhangqu/software/flutter_dev/engine/src
 - 假设你的Android SDK目录安装在`/Users/lizhangqu/AndroidSDK/`
 - 假设你启动的apk的包名为`com.example.flutter_app`
 - 假设你的apk是可调试的，也就是debuggable为true
 - 假设apk中只有armeabi-v7a或armeabi的动态库
 - 假设你用的flutter的引擎版本为v1.9.1+hotfix.4
 - 其他未想到的假设...

### 追本溯源LLDB

从上面的几篇文章中汲取精华，你会发现LLDB 远程调试遵循如下步骤
 - 将lldb-server通过adb push到手机上，然后启动lldb-server
 - 连接lldb-server，attach到进程中，设置符号表，断点调试

这一节我们介绍一下将lldb-server推送到设备上，然后启动lldb-server，启动客户端进行调试。

首先你需要知道lldb-server存放的位置，lldb-server存放于AndroidSDK目录下，如
 - /Users/lizhangqu/AndroidSDK/lldb/3.1/android/armeabi/lldb-server
 - /Users/lizhangqu/AndroidSDK/lldb/3.1/android/arm64-v8a/lldb-server

如果你没有安装过LLDB，可通过Android Studio进行安装：

**Android Studio -> Preferences -> Appearance & Behavior -> System Settings -> Android SDK -> SDK Tools -> 勾选LLDB -> Apply**

如图所示：

![install_lldb.png](install_lldb.png)

安装完LLDB后，你需要将它通过adb push到设备上。

```
adb push \
/Users/lizhangqu/AndroidSDK/lldb/3.1/android/armeabi/lldb-server \
/data/local/tmp/lldb-server
```

>开始划重点
**注意这里我们将lldb-server通过adb push到了一个临时目录，这里有一个坑，如果你在这个目录启动lldb-server，那后面必然会遇到权限不足的问题，因此我们必须将其放在app的私有目录下去执行，通过run-as提升权限，将该文件拷贝到app私有目录。**

```
adb shell run-as com.example.flutter_app \
cp -F /data/local/tmp/lldb-server /data/data/com.example.flutter_app/lldb-server
```

然后对该文件增加可执行权限

```
adb shell run-as com.example.flutter_app \
chmod a+x /data/data/com.example.flutter_app/lldb-server
```

在正式启动lldb-server服务前，你需要将之前启动的进程杀掉

```
adb shell run-as com.example.flutter_app killall lldb-server
```

如果这一步报权限不足，假设你的设备是root的，那么请以root方式执行去杀进程

```
adb shell "su -c 'killall lldb-server'"
```

如果你后续连接不上lldb-server或者启动不了lldb-server，并且也杀不掉已有进程，那么请重启手机，当然这不是必要的，一切在你连不上lldb-server的前提下才去重启手机，一般这个发生在你之前启动过lldb-server，然后将app卸载后重新安装，再次启动lldb-server会发生。

一切准备就绪，这时候你可以启动lldb-server服务了

```
adb shell "run-as com.example.flutter_app sh -c '/data/data/com.example.flutter_app/lldb-server platform --server --listen unix-abstract:///data/data/com.example.flutter_app/debug.socket'"
```

这时候进程就会进入等待状态，等待lldb的客户端连接上去。

你可以使用如下命令列出platform子命令的用法

```
adb shell "run-as com.example.flutter_app sh -c '/data/data/com.example.flutter_app/lldb-server platform'"
```

这时候会输出

```
Usage:
  /data/data/com.example.flutter_app/lldb-server platform \
  [--log-file log-file-name] \
  [--log-channels log-channel-list] 
  [--port-file port-file-path] \
  --server \
  --listen port
```

注意这里我们使用了unix-abstrac协议，你也可以直接使用指定端口号，lldb相关文档可以参考
 - [Remote Debugging](https://lldb.llvm.org/use/remote.html)

接下来我们需要将我们安装好的apk启动起来，并获取该进程的pid，我们可以使用monkey的简易命令直接启动apk

```
adb shell monkey -p com.example.flutter_app -v 1
```

通过pidof命令获取该app的进程pid

```
adb shell pidof com.example.flutter_app
```

当然如果你的手机系统版本比较低，可能pidof命令不存在，这时候可以使用ps加上grep命令进行查找进程号

```
adb shell ps | grep com.example.flutter_app | awk '{ print $2 }'
```

假设我们这里获取到的进程pid值为29898

接下来我们再起一个终端，执行lldb命令进入lldb交互界面，使用platform select命令选择remote-android插件，使用platform connect命令连接远程lldb-server，这里使用unix-abstract-connect连接协议

```
lldb
(lldb) platform select remote-android
(lldb) platform connect unix-abstract-connect:///data/data/com.example.flutter_app/debug.socket
(lldb) process attach -p 29898
```

如下图所示：
![atatch_to_remote_android.png](atatch_to_remote_android.png)


到这一步，其实你就已经attach到debug进程了，可以从之前启动lldb-server的终端看到输出`Connection established`，此时程序会被暂停，直到你执行`continue`或其简写`c`，如果你想再次暂停，可以执行`process interrupt`

这时候如果你通过`adb forward --list`命令查看端口转发关系，你会发现一个端口映射，这是lldb帮我们完成的
![adb_forward.png](adb_forward.png)

目前还差一份符号表，从前人的经验中可以得出可以使用`add-dsym`命令添加符号表，该命令是`target symbols add`的缩写，后面跟上本地引擎编译的out目录下的libflutter.so的绝对路径

```
(lldb) add-dsym /Users/lizhangqu/software/flutter_dev/engine/src/out/android_debug_unopt/libflutter.so
```

>开始划重点
**注意`add-dsym`命令有一个坑，就是必须要在你的so加载后执行，也就是必须在System.loadLibrary("flutter")后进行执行**

否则就会报如下错误

```
error: symbol file '/Users/lizhangqu/software/flutter_dev/engine/src/out/android_debug_unopt/libflutter.so' does not match any existing module
```

![no_existing_module.png](no_existing_module.png)

这里假设我们已经加载过libflutter.so了，那么执行add-dsym命令后，你就会看到输出

```
symbol file '/Users/lizhangqu/software/flutter_dev/engine/src/out/android_debug_unopt/libflutter.so' has been added to '/Users/lizhangqu/.lldb/module_cache/remote-android/.cache/F11F2051-0507-2910-730A-D41DBED297F2-160C5726/libflutter.so'
```

![existing_module.png](existing_module.png)

这表示添加符号表成功了。

其实到这一步，我们就已经可以开始下断点调试了，见证奇迹的时候到了。

engine.cc中有一段代码，函数名为BeginFrame，我们在这里下一个断点，从而每次界面渲染都会进入断点

```
210 	void Engine::BeginFrame(fml::TimePoint frame_time) {
211 	  TRACE_EVENT0("flutter", "Engine::BeginFrame");
212 	  runtime_controller_->BeginFrame(frame_time);
213 	}
```

使用br命令下一个断点

```
br s -f engine.cc -l 211
```

以上命令等效于

```
breakpoint set --file engine.cc --line 211
```

然后在app中触发界面渲染进入该断点，如下图所示，你就可以在终端中开始愉快的调试了。

![debug_terminal.png](debug_terminal.png)

细心的你肯定发现了我已经使用了流程控制中的`continue`，`step over`，`step into`，`step out`，这些功能你都可以在android studio中的调试状态栏中找到，只是这里使用的是命令行的方式。

![debug_toolbar.png](debug_toolbar.png)

你还可以使用`p`打印一个变量, `po`打印一个对象，`bt`打印当前的堆栈，`expression`改变一个变量的值

如下是使用bt打印的堆栈

![backtrace.png](backtrace.png)

关于终端调试，更详细的内容可以参考 
 - [与调试器共舞 - LLDB 的华尔兹](https://objccn.io/issue-19-2/)

如果你要查看gdb命令到lldb命令的映射关系，可以参考
 - [GDB to LLDB command map](https://lldb.llvm.org/use/map.html)

毕竟终端调试不是本文的重点，我们的重点是要在集成环境中进行图形化调试。

>开始划重点
**如果你编译debug用的flutter引擎的机器和你当前debug的机器不是位于同一台机器，那么你还需要设置源码映射**

可在lldb交互界面下使用如下命令设置，这里默认源码目录和构建目录位于同一个目录，所以参数中两个目录设成同一个
```
(lldb) settings set target.source-map /Users/lizhangqu/software/flutter_dev/engine/src /Users/lizhangqu/software/flutter_dev/engine/src
```

大多数情况下我们编译的机器和调试的机器都是同一台，那么这一步可直接忽略。

当然你从文章最开始贴的几篇Flutter Engine源码调试中你会发现他们都是设置错误的，可以看看他们如何设置：

```
settings set target.source-map /Users/lizhangqu/software/flutter_dev/engine/src/out/android_debug_unopt /Users/lizhangqu/software/flutter_dev/engine/src
```

将out/android_debug_unopt目录映射到src目录，其实是无效的，因为我们的源码目录本来就是src，已经不需要映射了。


如果你基于其他人编译的产物，然后本地调试，那么这一步是必须的。target.source-map后面第一个目录为build目录，第二个目录为源码目录

到这里，恭喜你，你已经学会了LLDB在终端中的调试。什么？嫌麻烦！不要急，好东西来了。[此处为人肉防盗文, 原文出处 https://fucknmb.com](https://fucknmb.com)

### Flutter_LLDB封装

鉴于以上操作太麻烦，并且官方提供了一个[flutter_gdb](https://github.com/flutter/engine/blob/master/sky/tools/flutter_gdb#L13)的脚本，因此我将以上操作封装成了一个python脚本，姑且命名为flutter_lldb，用于启动lldb-server服务，并输出在client端中需要的命令，从而可以复制粘贴。该脚本代码位于 [flutter_lldb](https://github.com/lizhangqu/flutter_lldb)

首先你需要clone这个工程

```
git clone https://github.com/lizhangqu/flutter_lldb.git
```

启动apk后，然后执行flutter_lldb完成lldb-server服务的启动

```
cd flutter_lldb
./flutter_lldb \
--local-engine-src-path=/Users/lizhangqu/software/flutter_dev/engine/src \
--local-engine=android_debug_unopt \
com.example.flutter_app
```

这时候你会看到输出

![flutter_lldb.png](flutter_lldb.png)

如果你的符号表路径和你源码路径不一样，比如你在a机器上的/path/to/engine/src目录构建了代码，但是你在b机器上调试，那么你需要追加参数\-\-build-dir进行源码目录映射，追加--symbol-dir表示你本地机器上的符号表路径

```
cd flutter_lldb
./flutter_lldb \
--local-engine-src-path=/Users/lizhangqu/software/flutter_dev/engine/src \
--local-engine=android_debug_unopt \
--build-dir=/path/to/engine/src \
--symbol-dir=/path/to/symbol \
com.example.flutter_app
```

![flutter_lldb_build.png](flutter_lldb_build.png)

没错，你需要用到的命令都在里面了，复制过去就可以使用。并且该配置是一个完整的vscode的启动配置，可直接被VSCode运行，关于VSCode，我们后文再讲，因为我们还有重点内容没有讲。[此处为人肉防盗文, 原文出处 https://fucknmb.com](https://fucknmb.com)

### 等待调试器

前文说到`add-dsym`命令必须在libflutter.so被加载后进行调用，那么问题来了：

 - 如果我们要打的断点执行的时机比较早，那么我们要怎么打断点？

其实在集成环境中是有解决方法的，比如Android Studio中的`Attach debugger to Android Process`，那么我们要怎么做呢，这里有两种解决方法，一种是需要修改源码支持，另一种是不需要修改源码支持，我们来一一进行介绍。

既然add-dsym需要在libflutter.so加载后执行，那我们就遵循这个条件，我们只需要在加载libflutter.so后，在C++代码中暂停程序，暂停程序后，我们在lldb交互界面中执行continue进行恢复。

我们在`library_loader.cc`中的`JNI_OnLoad`方法中加入如下代码，因为JNI_OnLoad的时机是最早的

```
#include <signal.h>
#include <csignal>
#include <unistd.h>

JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* reserved) {

#if FLUTTER_RUNTIME_MODE == FLUTTER_RUNTIME_MODE_DEBUG
  if ((access("/sdcard/lldb.debug", F_OK)) != -1) {
    raise(SIGSTOP);
  }
#endif

//其他原始代码
}
```

重新编译引擎，重新编译apk运行，这时候打开flutter界面，如果你的sdcard目录下存在lldb.debug文件，并且是debug模式运行的flutter，那么程序就会进行暂停，这时候我们使用lldb进行连接，然后使用add-dsym命令添加符号表，就会顺利的添加，之后设置断点后执行`continue`让程序继续运行。我们满足了add-dsym命令在libflutter.so被加载后调用，所以add-dsym也就被顺利的调用了。

显然这不是理想的方式，因为需要重新编译代码，对于其他人编译的flutter引擎就无能为力，所以必然有一种更优的方式。

那么Android Studio是怎么做到Native代码等待调试器的呢？好奇心让我去找`Android NDK Support`插件的源码，找了一圈发现根本找不到。对于此，Google官方的回复如下：

>The NDK plugin source code is not on AOSP, because it uses some closed source codes that Google licensed.

>开始划重点
**无奈只能通过反编译查看Andorid Studio中的插件`Android NDK Support`代码，可以发现Android Studio是通过在attach命令执行前，设置`target.exec-search-paths`为符号表路径达到目的的**

具体命令如下，注意命令的先后顺序，必须在attach前执行，也就是`preRunCommands`亦或是`LLDB Startup Commands`
```
lldb
(lldb) platform select remote-android
(lldb) platform connect unix-abstract-connect:///data/data/com.example.flutter_app/debug.socket
(lldb) settings append target.exec-search-paths "/Users/lizhangqu/software/flutter_dev/engine/src/out/android_debug_unopt"
(lldb) process attach -p 29898
```

然后下断点就可以正常调试了。

等等？你在欺骗我吗，明明不可以调试！没错，确实是不可以调试，为什么不能调试呢？因为这里Flutter的编译脚本中有个BUG，不要问我怎么知道的，这是在经过几天定位后得出的结论，那么是什么BUG呢，请看下一节内容。[此处为人肉防盗文, 原文出处 https://fucknmb.com](https://fucknmb.com)


### -fuse-ld=lld与\-\-build-id引发的BUG

先说结论：

>开始划重点
**该BUG的原因是因为LLDB无法识别形如BuildID[xxHash]=086ed6b255edf06d的build id，而这种build id只会在同时传递了-fuse-ld=lld和\-\-build-id才会出现，很不幸，Flutter的构建脚本中同时存在这两个参数，并且Flutter 1.9.1使用的ndk版本为ndk-19**

该BUG的描述可以参考我在github的issue
 - [Why lldb remote debug can't locate the libflutter.so's symbol file](https://github.com/flutter/flutter/issues/45971)

以及在提完该issue后在ndk的代码库中找到的另一个issus
 - [[BUG] Breakpoints never hit in native code when using LLD](https://github.com/android/ndk/issues/885)

在ndk-21发布文档中的描述，该问题在ndk-21中已经修复，很不幸的是flutter 1.9.1是基于ndk-19编译的
 - [Build System Maintainers Guide](https://android.googlesource.com/platform/ndk/+/refs/heads/ndk-release-r21/docs/BuildSystemMaintainers.md)

该文档中有这么一段话

>Android Studio's LLDB debugger uses a binary’s build ID to locate debug information. To ensure that LLDB works with a binary, pass an option like -Wl,--build-id=sha1 to Clang when linking. Other --build-id= modes are OK, but avoid a plain --build-id argument when using LLD, because Android Studio‘s version of LLDB doesn’t recognize LLD's default 8-byte build ID. See Issue 885.

简单点说就是ndk现在使用了新的链接器lld，为了定位到符号表，需要传递参数-Wl,\-\-build-id=sha1给Clang

那么什么是lld呢，简单暴力点就是一种新的链接器，用于取代旧的链接器，因为它更快以及其他诸多优点。关于lld的介绍，可以参考
 - [LLD - The LLVM Linker](https://lld.llvm.org/)
 - [lld: A Fast, Simple and Portable Linker](http://llvm.org/devmtg/2017-10/slides/Ueyama-lld.pdf)

甚至在llvm的项目中也对这种格式的build id进行了兼容，但是不知道是因为Android Studio中的lldb或者mac用的lldb过旧，还是因为没有完全改全代码，依旧没有正确定位到符号表
 - [accept any build-id length between 4 and 20 bytes inclusive](https://reviews.llvm.org/D18096)

去flutter engine源码的构建脚本仓库[buildroot](https://github.com/flutter/buildroot)中全局搜索-fuse-ld=lld和\-\-build-id，你会发现flutter恰恰同时传递了这两个参数

 - [/build/config/compiler/BUILD.gn](https://github.com/flutter/buildroot/blob/a518e359c41e00f964f7cc079cbc5ef525f82516/build/config/compiler/BUILD.gn)
 - [/build/toolchain/custom/BUILD.gn](https://github.com/flutter/buildroot/blob/5a33d6ab06fa2cc94cdd864ff238d2c58d6b7e4e/build/toolchain/custom/BUILD.gn)
 - [/build/toolchain/fuchsia/BUILD.gn](https://github.com/flutter/buildroot/blob/8d73ea7887fc0474f168041a910037688adaf0f0/build/toolchain/fuchsia/BUILD.gn)
 - [/build/toolchain/gcc_toolchain.gni](https://github.com/flutter/buildroot/blob/5a33d6ab06fa2cc94cdd864ff2)

flutter engine的构建脚本使用gn编写的，gn是Generate Ninja的缩写，如其名它是用来生成Ninja构建所需的配置文件，然后交由Ninja进行构建，关于gn，可以参考如下几篇文章：
 - [Using GN Build](https://docs.google.com/presentation/d/15Zwb53JcncHfEwHpnG_PoIbbzQ3GQi_cpujYwbpcbZo/mobilepresent?slide=id.g119c85d284_0_57)
 - [Chromium GN构建工具的使用](https://github.com/hanpfei/chromium-net/wiki/Chromium-GN%E6%9E%84%E5%BB%BA%E5%B7%A5%E5%85%B7%E7%9A%84%E4%BD%BF%E7%94%A8)
 - [GN (Generate Ninja) 使用入門](https://blog.simplypatrick.com/posts/2016/01-23-gn/)
 - [GN语法和操作](https://blog.csdn.net/rankun1/article/details/80506829)

我们从[flutter_infra/android-arm/symbols.zip](https://storage.cloud.google.com/flutter_infra/flutter/b863200c37df4ed378042de11c4e9ff34e4e58c9/android-arm/symbols.zip)下载v1.9.1版本的libflutter.so的符号表，然后通过file命令查看该文件的build id

![buildid_md5.png](buildid_md5.png)

你会发现其build id是形如 BuildID[xxHash]=f37a5bf372c3eba5的形式。

然后再用file命令查看我们构建好的本地引擎的build id

![build_id_localengine.png](build_id_localengine.png)

其形式和我们从flutter_infra下载的符号表文件是一样的。

我们尝试新建一个带有JNI代码并且同时具备flutter界面的工程，编写一个测试的libfluttertest.so，然后用ndk进行编译，编译完成后运行加载libfluttertest.so进行调试，然后用settings append target.exec-search-paths设置libfluttertest.so和libflutter.so的符号表，看看有什么区别

```
lldb
(lldb) platform select remote-android
(lldb) platform connect unix-abstract-connect:///data/data/com.example.flutter_app/debug.socket
(lldb) settings append target.exec-search-paths /Users/lizhangqu/software/flutter_dev/engine/src/out/android_debug_unopt
(lldb) settings append target.exec-search-paths /Users/lizhangqu/Desktop/flutter_app/build/app/intermediates/ndkBuild/debug/obj/local/armeabi-v7a/
(lldb) process attach -p 20786
(lldb) image list
```

![libfluttertest.png](libfluttertest.png)

`image list`命令可以用来查看内存中已经加载的so的信息

可以看到如下输出

![uuid_not_work.png](uuid_not_work.png)

注意图中libfluttertest.so的符号表被正确的查找到了
```
[238] 303568CE-B37B-3E2E-3948-74901647876A-711EF2B6 0xc1bcc000 
/Users/lizhangqu/Desktop/flutter_app/build/app/intermediates/ndkBuild/debug/obj/local/armeabi-v7a/libfluttertest.so
```

但是libflutter.so并没有被正确识别

```
[237] 41A11D10-3034-6D25 0xc3a97000 
/Users/lizhangqu/.lldb/module_cache/remote-android/.cache/92EB5ECF-0000-0000-0000-000000000000/libflutter.so
```

我们再用file命令查看下libfluttertest.so的build id

```
file /Users/lizhangqu/Desktop/flutter_app/build/app/intermediates/ndkBuild/debug/obj/local/armeabi-v7a/libfluttertest.so
```
![libfluttertest_buildid.png](libfluttertest_buildid.png)

没错，libfluttertest.so的build id和libflutter.so的build id形式不同，libfluttertest.so的build id 是形如`BuildID[sha1]=303568ceb37b3e2e394874901647876a711ef2b6`的形式，而libflutter.so的build id是形如`BuildID[xxHash]=f37a5bf372c3eba5`的形式的。

为了验证是-fuse-ld=lld和\-\-build-id同时作用的锅，我们在编译libfluttertest.so的时候添加链接参数

如果你用Android.mk进行编译，使用如下配置

```
#NDK < 21 时，如果同时设置-fuse-ld=lld和--build-id就会触发生成形如BuildID[xxHash]=086ed6b255edf06d，lldb无法识别此类型的BuildID
LOCAL_LDFLAGS := -fuse-ld=lld -Wl,--build-id
```

如果你用CMake进行编译，使用如下配置

```
#NDK < 21 时，如果同时设置-fuse-ld=lld和--build-id就会触发生成形如`BuildID[xxHash]=086ed6b255edf06d`，lldb无法识别此类型的BuildID
set(CMAKE_SHARED_LINKER_FLAGS "-fuse-ld=lld -Wl,--build-id")
```

然后使用ndk-19进行编译，注意ndk版本过低是无法识别-fuse-ld=lld参数的，这里必须使用高版本的ndk，但不能使用ndk-21，因为该版本已经修复了，这里我们使用和flutter engine一样的版本，即ndk-19，具体详情可以见NDK的发布日志
 - [NDK Revision History](https://developer.android.google.cn/ndk/downloads/revision_history)


再次编译运行，执行lldb调试后进入交互界面，执行image list，你会看到libfluttertest.so的符号表也无法识别了！！！断点也无法正常进入！！

![libfluttertest_md5.png](libfluttertest_md5.png)

执行file命令查看libfluttertest.so的build id，你会发现它变成了形如`BuildID[xxHash]=086ed6b255edf06d`的形式

知道原因后，问题也就好解决了，我们只需要将\-\-build-id修改成\-\-build-id=sha1，让build id强制使用sha1，为了再次验证是这两个参数同时作用导致的，我们将flutter engine的构建脚本中\-\-build-id修改成\-\-build-id=sha1，重新编译libflutter.so。

主要修改点在path/to/engine/src/build/toolchain/gcc_toolchain.gni文件中，文件搜索\-\-build-id，将其修改成\-\-build-id=sha1，然后重新编译引擎。

```
./flutter/tools/gn --runtime-mode=debug --unoptimized
ninja -C out/android_debug_unopt -t clean
ninja -C out/android_debug_unopt
```

编译完成后通过file命令查看其build id

![build_id_sha1.png](build_id_sha1.png)

可以看到libflutter.so的build id变成了和libfluttertest.so的build id一样的形式，都是形如`BuildID[sha1]=303568ceb37b3e2e394874901647876a711ef2b6`的形式

再次进行调试并使用image list输出so的信息

```
lldb
(lldb) platform select remote-android
(lldb) platform connect unix-abstract-connect:///data/data/com.example.flutter_app/debug.socket
(lldb) settings append target.exec-search-paths /Users/lizhangqu/software/flutter_dev/engine/src/out/android_debug_unopt
(lldb) process attach -p 20786
(lldb) image list
```

你会发现这时候可以成功定位到libflutter.so的符号表了，如下图所示

![libflutter_symbol.png](libflutter_symbol.png)

下个断点进行调试，发现也可以正常进入断点了

![br.png](br.png)

完美解决了libflutter.so无法定位到符号表的问题。

关于这个BUG，我也提了一个PR
 - [Fix LLDB can't work with --build-id](https://github.com/flutter/buildroot/pull/336)

至于Flutter团队后续如何修复这个问题，可能是将\-\-build-id修改成\-\-build-id=sha1，也可能是升级ndk解决，这个看官方如何修复了。

解决了在终端中的调试问题，我们接下来看重头，如何在集成开发环境中进行调试，毕竟实际情况下不太可能在终端中进行调试。[此处为人肉防盗文, 原文出处 https://fucknmb.com](https://fucknmb.com)

### VSCode中使用LLDB调试

VSCode中调试相对比较简单，你除了要安装VSCode外，你还需要安装两个VSCode的插件。
 - [C/C++ for Visual Studio Code](https://marketplace.visualstudio.com/items?itemName=ms-vscode.cpptools)
 - [CodeLLDB](https://marketplace.visualstudio.com/items?itemName=vadimcn.vscode-lldb)

还记得我们最开始执行gn的命令生成Ninja的配置文件吗，大致如下

```
cd /path/to/engine/src
./flutter/tools/gn --android --runtime-mode=debug --unoptimized
```

该命令执行完成后，会在out目录下生成**compile_commands.json**文件，其全称是**JSON Compilation Database Format Specification**，关于该文件的介绍，可以参考
 - [JSON Compilation Database Format Specification](https://clang.llvm.org/docs/JSONCompilationDatabase.html)

生成该文件的地方就是在**./flutter/tools/gn**脚本中，大致代码如下

![gn_generate.png](gn_generate.png)

![jsonfile.png](jsonfile.png)

很幸运的是VSCode能够识别该文件并进行源码跳转，我们只需要将out目录下的compile_commands.json文件拷贝到src/futter目录下，在src/futter目录下，该文件是不跟随git
版本控制的，然后用VSCode打开src/flutter目录即可。

之后运行最开始介绍的flutter_lldb脚本运行lldb-server并获取VSCode的配置

```
./flutter_lldb \
--local-engine-src-path=/Users/lizhangqu/software/flutter_dev/engine/src \
--local-engine=android_debug_unopt \
com.example.flutter_app
```

![vscode_1.png](vscode_1.png)

大致可以获取到两段VSCode的配置

```
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "remote_lldb",
            "type": "lldb",
            "request": "attach",
            "pid": "26709",
            "initCommands": [
                "platform select remote-android",
                "platform connect unix-abstract-connect:///data/data/com.example.flutter_app/debug.socket"
            ],
            "postRunCommands": [
                "add-dsym /Users/lizhangqu/software/flutter_dev/engine/src/out/android_debug_unopt/libflutter.so",
                "settings set target.source-map /Users/lizhangqu/software/flutter_dev/engine/src /Users/lizhangqu/software/flutter_dev/engine/src"
            ],
        }
    ]
}
```


```
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "remote_lldb",
            "type": "lldb",
            "request": "attach",
            "pid": "26709",
            "initCommands": [
                "platform select remote-android",
                "platform connect unix-abstract-connect:///data/data/com.example.flutter_app/debug.socket"
            ],
            "preRunCommands": [
                "settings append target.exec-search-paths /Users/lizhangqu/software/flutter_dev/engine/src/out/android_debug_unopt"
            ],
            "postRunCommands": [
                "settings set target.source-map /Users/lizhangqu/software/flutter_dev/engine/src /Users/lizhangqu/software/flutter_dev/engine/src"
            ],
        }
    ]
}
```

你可以使用其中任何一段配置，如果你想达到等待调试器的目的，那你就使用第二个配置，如果你已经加载了libflutter.so想attach上去，那么两个配置都可以做到，任你选择。

将配置拷贝到.vscode/launch.json中，然后运行remote_lldb的configuration，下个断点，你就会发现可以正常调试并且可以进行源码跳转了。

![vscode_2.png](vscode_2.png)

![vscode_3.png](vscode_3.png)

[此处为人肉防盗文, 原文出处 https://fucknmb.com](https://fucknmb.com)

### CLion中使用LLDB调试

>开始划重点
**Clion自带的LLDB很不幸没有lldb remote configuration的功能，我们需要第三方插件的支持，但是截至发稿，该插件不支持最新版的Clion 2019，因此我们必须使用Clion 2018.3.4的版本，这是该插件目前为止支持的最新Clion的版本，注意一定要用该版本，否则插件无法装上，也就无法进行调试了。**

安装完Clion 2018.3.4后，我们需要安装一个插件叫**Android Native Debug**，反编译该插件可以发现该插件中的很多类都是**Android NDK Support**插件中抠出来

![Clion_plugin.png](Clion_plugin.png)

还记得前面的**compile_commands.json**文件吗，很幸运，Clion也能识别到该文件。打开Clion后直接选择该文件进行打开，Clion会进行索引，首次打开索引时间会比较久，耐心等待即可，如果索引过程中出现如下error，可以无视，不影响我们调试，只是会影响部分源码跳转。

![clion_error.png](clion_error.png)

还是和VSCode一样，启动app，运行flutter_lldb启动lldb_server

```
./flutter_lldb \
--local-engine-src-path=/Users/lizhangqu/software/flutter_dev/engine/src \
--local-engine=android_debug_unopt \
com.example.flutter_app
```

然后在Clion中新建一个Run Configuration

**Add Configuration -> Android Native DEBUG -> LLDB -> 随意输入name，如debug**

然后选择Android SDK目录，Android NDK目录和LLDB路径会被自动填充，Remote填写flutter_lldb生成的json配置中的**platform connect**命令后面跟着的字符串，如 **unix-abstract-connect:///data/data/com.example.flutter_app/debug.socket**

![clion_config.png](clion_config.png)

切换到Symbol选项卡添加符号表路径，值为**/Users/lizhangqu/software/flutter_dev/engine/src/out/android_debug_unopt**。（这一步也可不添加，可以在调试进程attach到app进程后在lldb交互界面下通过add-dsym命令添加，取决于你喜欢哪种方式。）

![clion_symbol.png](clion_symbol.png)

其他配置留空，然后点击确认后运行新建的Configuration

![clion_run.png](clion_run.png)

选择连接的设备

![clion_run1.png](clion_run1.png)

搜索调试的应用包名

![clion_run2.png](clion_run2.png)

下断点，进入调试状态

![clion_br.png](clion_br.png)

如果之前你没有在Symbol选项卡设置符号表路径为**/Users/lizhangqu/software/flutter_dev/engine/src/out/android_debug_unopt**，那么你也可以在应用启动后加载libflutter.so后，暂停程序，进入Clion中的lldb交互界面，通过add-dsym添加符号表。

切换到Debugger选项卡，点击暂停程序，点击LLDB选项卡

![clion_pause.png](clion_pause.png)

点击LLDB选项卡后，你就可以输入lldb命令(源码映射的命令可忽略，因为是同一个目录)

```
add-dsym /Users/lizhangqu/software/flutter_dev/engine/src/out/android_debug_unopt/libflutter.so
settings set target.source-map /Users/lizhangqu/software/flutter_dev/engine/src /Users/lizhangqu/software/flutter_dev/engine/src
```
![clion_add.png](clion_add.png)

然后点击左侧绿色的按钮恢复程序运行，下断点即可触发进入断点调试。

至此Clion的调试方法就介绍完了。[此处为人肉防盗文, 原文出处 https://fucknmb.com](https://fucknmb.com)

### Android Studio中使用LLDB调试

最后来介绍一下旗舰集成环境Android Studio怎么调试，其实Android Studio进行Native调试是有条件的，要求你运行的flutter app的工程必须是带有jni代码的工程，这里我提供了一个简单的工程，就在最基本的flutter demo的基础上添加测试用的jni代码。
 - [flutter_app_for_lldb](https://github.com/lizhangqu/flutter_app_for_lldb)

克隆工程后，在android/gradle.properties中加入本地引擎的配置

```
target-platform=android-arm
localEngineOut=/Users/lizhangqu/software/flutter_dev/engine/src/out/android_debug_unopt
```

然后以flutter的工程视图打开工程执行flutter packages get后成功运行一次app，然后关闭工程，以Android工程的视角打开android目录下的工程。

要进行调试，必须在工程中可以看到源码，因此我们通过软链接的方式将flutter engine的源码链接到android/flutter_source目录

```
ln -s /Users/lizhangqu/software/flutter_dev/engine/src ./android/flutter_source
```

链接完成后等待Android Studio进行索引，首次索引耗时比较久，耐心等待。

>开始划重点
注意，我们软链接后，源码目录就发生了变化，这里假设flutter_source的目录为**/Users/lizhangqu/Desktop/flutter_app/android/flutter_source**，那么源码目录就从**/Users/lizhangqu/software/flutter_dev/engine/src**变成了**/Users/lizhangqu/Desktop/flutter_app/android/flutter_source**，因此我们需要使用**settings set target.source-map**命令设置源码映射

Android Studio中进行调试的好处在于lldb-server不用再手动启动了，Android Studio会帮你完成这一切，包括push lldb-server和启动lldb-server。

我们需要做的就是附加符号表信息和设置源码目录映射

**Run/Debug Configuration -> app -> Debugger -> Debug Type选择Native**

LLDB Startup Commands:
```
settings append target.exec-search-paths /Users/lizhangqu/software/flutter_dev/engine/src/out/android_debug_unopt 
```
LLDB Post Commands:
```
settings set target.source-map /Users/lizhangqu/software/flutter_dev/engine/src /Users/lizhangqu/Desktop/flutter_app/android/flutter_source
```
![as_symbol.png](as_symbol.png)

![as_post.png](as_post.png)


注意如果源码映射不设置，Android Studio的断点是打在/Users/lizhangqu/Desktop/flutter_app/android/flutter_source目录下的文件的，但是符号表中的路径其实是/Users/lizhangqu/software/flutter_dev/engine/src，所以断点是不会生效的。

然后Apply，以Debug 'app'形式运行apk，注意不是Attach Debugger to Android Process，如果无法进入debug，可以尝试重启下手机。
![as_debug_run.png](as_debug_run.png)

下断点，调试
![as_br.png](as_br.png)

上面是以Debug 'app'形式运行进行调试的，实际情况，我们可能需要Attach Debugger to Android，当你使用Attach Debugger to Android方式进行调试，你会发现LLDB Startup Commands和LLDB Post Commands命令并没有生效，这是Bug吗，根据Google团队的反馈，这并不是Bug。

>开始划重点
Debug 'app'和Attach Debugger to Android设计的时候是两个完全不同的概念，即使你把所有的Run/Debug Configuration删除，Attach Debugger to Android依旧也是可以工作的，所以Attach Debugger to Android的正常运行不依赖Debug 'app'，因此配置上也没有直接关联了，那么Attach Debugger to Android的时候有没有办法设置LLDB Startup Commands和LLDB Post Commands命令呢？答案是没有办法在图形化界面中设置，我们只能在调试器附加到App进程后，通过暂停程序的方式，通过lldb交互界面添加，而且此时只能添加LLDB Post Commands，不能添加LLDB Startup Commands

具体的解释可以参考google issuetracker
 - [LLDB Startup Commands Can't work with Attach Debugger to Android Process when debug](https://issuetracker.google.com/issues/145707569)

由于LLDB交互界面不能设置LLDB Startup Commands，因此我们只能使用add-dsym方式进行调试。

点击Attach Debugger to Android，选择Native方式，进入调试

![as_attach.png](as_attach.png)

和Clion一样的方式，进入lldb终端交互界面。
输入如下命令设置符号表和源码映射

```
add-dsym /Users/lizhangqu/software/flutter_dev/engine/src/out/android_debug_unopt/libflutter.so
settings set target.source-map /Users/lizhangqu/software/flutter_dev/engine/src /Users/lizhangqu/Desktop/flutter_app/android/flutter_source
```
![as_lldb.png](as_lldb.png)

那么有没有办法在attach后用settings append target.exec-search-paths呢，答案也是有的，前提是你的libflutter.so还没有加载，这个其实很好构造，我们只需要构造一个中间页面，启动的时候跳转到中间页面，在跳转flutter界面前不加载libflutter.so即可，在中间页面完成lldb命令的调用，之后断点也会正常进入。

```
settings set target.source-map /Users/lizhangqu/software/flutter_dev/engine/src /Users/lizhangqu/Desktop/flutter_app/android/flutter_source
settings append target.exec-search-paths /Users/lizhangqu/software/flutter_dev/engine/src/out/android_debug_unopt
```
![as_lldb1.png](as_lldb1.png)

然后下断点调试，你会发现也会正常进入断点并进行调试

![as_br2.png](as_br2.png)

至此Android Studio的调试也就结束了。

和VSCode，Clion相比，Android Studio需要进行源码链接，并且多设置一步源码映射。

除此之外，Android Studio也无法进行源码的点击跳转和代码提示，这是最头痛的地方。 [此处为人肉防盗文, 原文出处 https://fucknmb.com](https://fucknmb.com)


### Google构建的引擎能调试吗

很不幸，只有gn加了\-\-unoptimized参数，才会保留足够的调试信息，而Google编译的引擎必然不会添加该参数，因此也就不能调试了。

![gn_debug.png](gn_debug.png)

构建脚本中如果is_debug=false，那么symbol_level便会被赋值成0，从而被配置成no_symbols

```
# Optimizations and debug checking.
if (is_debug) {
  _native_compiler_configs += [ "//build/config:debug" ]
  _default_optimization_config = "//build/config/compiler:no_optimize"
} else {
  _native_compiler_configs += [ "//build/config:release" ]
  _default_optimization_config = "//build/config/compiler:optimize"
}
_native_compiler_configs += [ _default_optimization_config ]

# If it wasn't manually set, set to an appropriate default.
if (symbol_level == -1) {
  # Linux is slowed by having symbols as part of the target binary, whereas
  # Mac and Windows have them separate, so in Release Linux, default them off.
  if (is_debug || !is_linux) {
    symbol_level = 2
  } else if (is_asan || is_lsan || is_tsan || is_msan) {
    # Sanitizers require symbols for filename suppressions to work.
    symbol_level = 1
  } else {
    symbol_level = 0
  }
}

# Symbol setup.
if (symbol_level == 2) {
  _default_symbols_config = "//build/config/compiler:symbols"
} else if (symbol_level == 1) {
  _default_symbols_config = "//build/config/compiler:minimal_symbols"
} else if (symbol_level == 0) {
  _default_symbols_config = "//build/config/compiler:no_symbols"
} else {
  assert(false, "Bad value for symbol_level.")
}
```

而no_symbols则会添加-g0编译参数

```
config("no_symbols") {
  if (!is_win) {
    cflags = [ "-g0" ]
  }
}

```

缺失足够的调试信息，因此如果你想进行源码调试，你必须自己编译引擎，并且添加\-\-unoptimized参数 [此处为人肉防盗文, 原文出处 https://fucknmb.com](https://fucknmb.com)

### 总结

虽然看似LLDB调试简单，但是实际操作起来遇到的坑还是很多的，尤其是build id的问题，定位了好几天，如果不是机缘巧合之下发现了问题，那么可能定位的时间还要更长。

一般我们不会直接在终端中调试，除非你对终端十分熟悉并且严重依赖终端。VSCode和Clion是比较推荐的，因为可以进行源码跳转和代码提示，Android Studio虽然也可以，但是在没有特殊工程结构面前，Android Studio显得有点无力，因此这里不太推荐使用Android Studio。

本文提到的LLDB调试方法，理论上适用于Android场景下的所有so调试，包括系统源码（你需要自己编译系统），还有比如chromium，你也需要自己编译，再比如chromium的子项目cronet，自己编译后，带上足够的调试信息，你就能游刃有余的进行调试了。

[此处为人肉防盗文, 原文出处 https://fucknmb.com](https://fucknmb.com)
