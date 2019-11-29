title: Flutter Engine 编译指北
date: 2019-02-26 17:29:51
categories: [Flutter]
tags: [flutter, engine, compile]
---

### 前言

Flutter 作为一个跨平台，高性能的移动开发框架，通过Skia绘制引擎对UI进行渲染，可以用于快速地构建iOS和Android应用，对于普通开发者来讲，它基本已经做到开箱即用的程度。到2019.02.26为止，Flutter也已经对外发布了Release 1.2.2版本，并且处于不断迭代的过程中。但是如果你想更深入的学习或者进行定制操作，那么难免会需要对Flutter Engine进行编译，也会遇到一些问题。

<!-- more -->

首先我们来明确一下编译Flutter Engine的最终目的。
 
 - 学习。对于一部分保持好奇心的开发者来说可能会通过编译Flutter Engine来进行对Flutter的整体学习和实践掌握，这和编译AOSP源码来进行Android的学习是一样。
 - 定制。对于现有Flutter版本不能满足的场景，可能会面临定制化操作。

实际情况下，我们基本不会对Flutter Engine进行定制操作，大部分场景都是秉着学习的目的对其进行编译的。

### 编译

#### 配置代理

基于当前我们所处网络环境，拉取Flutter Engine源码，将会面对种种问题，如git源码拉取不下来，某zip文件下载不下来。

所以我们必须提前进行代理配置，包括：
  
  - git代理配置，含git的http/https协议代理配置和git的ssh协议代理配置
  - 终端的http/https代理配置

只要将以上代理配置完成，那么源码同步过程会变得异常顺利，下载过程会变得十分快速。此处基于Shadowsocks进行代理的配置演示。

##### 配置git代理

git代理一般会分为两种，一种是走http协议的代理，另一种是走ssh协议的代理。

对于走http协议的代理，我们只需要执行如下命令(端口号根据本地Shadowsocks配置自行修改)：

```
git config --global http.proxy http://127.0.0.1:1088
git config --global https.proxy http://127.0.0.1:1088
```

如果要取消代理，则执行如下命令

```
git config --global --unset http.proxy
git config --global --unset https.proxy
```

加上如上配置后，对于公司内网的git是无法进行访问的，所以还得把内网的git地址加入到no_proxy环境变量中

```
export no_proxy="localhost,127.0.0.1,内网git域名"
```

除了http协议代理，git可能还会走ssh协议，对于ssh协议的配置其实也是类似

编辑ssh config文件
```
vim ~/.ssh/config
```

加入如下内容（端口号根据本地Shadowsocks配置自行修改）
```
Host github.com
   HostName github.com
   User git
   # 走 HTTP 代理
   # ProxyCommand socat - PROXY:127.0.0.1:%h:%p,proxyport=1088
   # 走 socks5 代理（如 Shadowsocks）
   ProxyCommand nc -v -x 127.0.0.1:1086 %h %p
```

注意此处使用的是socks5代理，而http/https协议配置的是http代理，至此就完成了git的代理配置

##### 配置终端http/https代理

除了git需要配置代理之外，其实还需要配置终端http/https代理，因为源码下载过程中除了用git去下载源码外，还会借用python去下载一些zip文件，以及使用cipd下载一些文件，使用这些工具的时候，在终端中可能无法正常完成对应文件的下载。

因为这部分代理使用场景不多，全局共两处
 - src/tools/dart/update.py
 - src/tools/buildtools/update.py

为了尽可能的不污染全局环境，我们进行临时的环境变量导出(端口号根据本地Shadowsocks配置自行修改)。

```
export http_proxy=http://127.0.0.1:1088
export https_proxy=http://127.0.0.1:1088
```

完成以上配置后，源码同步过程会变得十分顺畅，而不用进行漫长的等待。

#### 配置depot_tools工具

depot_tools是个工具包，里面包含gclient、gn和ninja等工具。是Google为解决Chromium源码管理问题为Chromium提供的源代码管理的一个工具。Flutter源码同步也需要依赖depot_tools工具。

clone depot_tools源码

```
git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
```

然后将depot_tools加入环境变量

```
export PATH="$PATH:/path/to/depot_tools"
```

然后就可以愉快的使用depot_tools了，关于depot_tools的使用可以参考 
 - [Using depot_tools](https://dev.chromium.org/developers/how-tos/depottools)
 - [depot_tools_tutorial](https://commondatastorage.googleapis.com/chrome-infra-docs/flat/depot_tools/docs/html/depot_tools_tutorial.html)

#### 获取源码

目前在Linux上只能编译Flutter的Android产物，在Windows上不支持编译，在Mac上支持同时编译Flutter的Android和iOS产物，因此Mac是编译Flutter的最佳选择，此文也是基于Mac环境进行编译的。

创建一个目录用于同步Flutter源码，按照约定，建议使用engine。

```
mkdir engine
cd engine
```

在engine目录下创建.gclient文件用于同步源码，官方建议我们fork一个项目，但是个人觉得如果你不进行开发，纯粹为了编译学习的话，那就没有fork的必要了，如果你要进行开发，定制一些需求，那fork还是有必要的。

在.gclient文件中加入如下内容，如果你进行了fork，那么url修改为你fork后的url，此处没有进行fork，所以是直接使用官方的url。

```
solutions = [
  {
    "managed": False,
    "name": "src/flutter",
    "url": "git@github.com:flutter/engine.git",
    "custom_deps": {},
    "deps_file": "DEPS",
    "safesync_url": "",
  },
]
```

如果想指定flutter engine revision，则可以配置url加入@revision，如检出v1.9.1的engine版本

```
solutions = [
  {
    "managed": False,
    "name": "src/flutter",
    "url": "git@github.com:flutter/engine.git@b863200c37df4ed378042de11c4e9ff34e4e58c9",
    "custom_deps": {},
    "deps_file": "DEPS",
    "safesync_url": "",
  },
]
```

如果想覆盖特定的依赖，可在custom_deps中重写，比如我想覆盖buildroot，从*git@github.com:flutter/engine.git*工程中的DEPS文件中可以找到buildroot对应的释放路径为src

```
'src': 'https://github.com/flutter/buildroot.git' + '@' + '5a33d6ab06fa2cc94cdd864ff238d2c58d6b7e4e',
```

因此我们只需要覆盖src的dep即可完成buildroot的覆盖，如

```
solutions = [
  {
    "managed": False,
    "name": "src/flutter",
    "url": "git@github.com:flutter/engine.git@b863200c37df4ed378042de11c4e9ff34e4e58c9",
    "custom_deps": {
        "src":"https://github.com/flutter/buildroot.git@fa860b64553b54bbd715ebd2145523a4999a3b3a"
    },
    "deps_file": "DEPS",
    "safesync_url": "",
  },
]
```

然后在engine目录下执行源码同步操作

```
cd /path/to/engine
gclient sync --verbose
```

如果源码同步过程中速度很慢或者出现了一些异常，基本就是代理配置存在问题，请认真检查代理是否配置正确。

如果出现如下Operation timed out异常

```
----------------------------------------
________ running '/usr/local/Cellar/python@2/2.7.15_1/Frameworks/Python.framework/Versions/2.7/Resources/Python.app/Contents/MacOS/Python src/build/landmines.py' in '/Users/lizhangqu/Desktop/engine'
________ running '/usr/local/Cellar/python@2/2.7.15_1/Frameworks/Python.framework/Versions/2.7/Resources/Python.app/Contents/MacOS/Python src/build/vs_toolchain.py update' in '/Users/lizhangqu/Desktop/engine'
________ running '/usr/local/Cellar/python@2/2.7.15_1/Frameworks/Python.framework/Versions/2.7/Resources/Python.app/Contents/MacOS/Python src/tools/dart/update.py' in '/Users/lizhangqu/Desktop/engine'
Traceback (most recent call last):
  File "src/tools/dart/update.py", line 92, in <module>
    sys.exit(main())
  File "src/tools/dart/update.py", line 82, in main
    urllib.urlretrieve(sdk_url, output_file)
  File "/usr/local/Cellar/python@2/2.7.15_1/Frameworks/Python.framework/Versions/2.7/lib/python2.7/urllib.py", line 98, in urlretrieve
    return opener.retrieve(url, filename, reporthook, data)
  File "/usr/local/Cellar/python@2/2.7.15_1/Frameworks/Python.framework/Versions/2.7/lib/python2.7/urllib.py", line 245, in retrieve
    fp = self.open(url, data)
  File "/usr/local/Cellar/python@2/2.7.15_1/Frameworks/Python.framework/Versions/2.7/lib/python2.7/urllib.py", line 213, in open
    return getattr(self, name)(url)
  File "/usr/local/Cellar/python@2/2.7.15_1/Frameworks/Python.framework/Versions/2.7/lib/python2.7/urllib.py", line 350, in open_http
    h.endheaders(data)
  File "/usr/local/Cellar/python@2/2.7.15_1/Frameworks/Python.framework/Versions/2.7/lib/python2.7/httplib.py", line 1038, in endheaders
    self._send_output(message_body)
  File "/usr/local/Cellar/python@2/2.7.15_1/Frameworks/Python.framework/Versions/2.7/lib/python2.7/httplib.py", line 882, in _send_output
    self.send(msg)
  File "/usr/local/Cellar/python@2/2.7.15_1/Frameworks/Python.framework/Versions/2.7/lib/python2.7/httplib.py", line 844, in send
    self.connect()
  File "/usr/local/Cellar/python@2/2.7.15_1/Frameworks/Python.framework/Versions/2.7/lib/python2.7/httplib.py", line 821, in connect
    self.timeout, self.source_address)
  File "/usr/local/Cellar/python@2/2.7.15_1/Frameworks/Python.framework/Versions/2.7/lib/python2.7/socket.py", line 575, in create_connection
    raise err
IOError: [Errno socket error] [Errno 60] Operation timed out
Error: Command '/usr/local/Cellar/python@2/2.7.15_1/Frameworks/Python.framework/Versions/2.7/Resources/Python.app/Contents/MacOS/Python src/tools/dart/update.py' returned non-zero exit status 1 in /Users/lizhangqu/Desktop/engine
Hook '/usr/local/Cellar/python@2/2.7.15_1/Frameworks/Python.framework/Versions/2.7/Resources/Python.app/Contents/MacOS/Python src/tools/dart/update.py' took 75.57 secs
```

也请检查http/https代理是否配置正确，在命令行中导出如下环境变量即可(端口号根据本地Shadowsocks配置自行修改)

```
export http_proxy=http://127.0.0.1:1088
export https_proxy=http://127.0.0.1:1088
```

耐心等待源码完全检出即可，大约半小时检出完成。

#### 构建

##### 检出对应版本

在构建前，我们需要保证当前的源码和我们使用的Flutter版本是兼容的，为了避免不必要的错误，我们对源码检出到我们当前使用的Flutter版本的提交上。

首先获取我们当前使用的Flutter版本的提交记录。

```
cat /path/to/currentFlutter/bin/internal/engine.version
```

得到v1.0.0版本的提交记录为

```
7375a0f414bde4bc941e623482221db2fc8c4ab5
```

然后将源码同步到上述提交记录上，执行如下命令然后约等待10分钟。

```
cd /path/to/engine/src/flutter
git reset --hard 7375a0f414bde4bc941e623482221db2fc8c4ab5
gclient sync --with_branch_heads --with_tags --verbose
```

之后即可进行编译。


也可以一开始直接通过修改.gclient的配置达到目的，如检出v1.9.1的engine版本

```
solutions = [
  {
    "managed": False,
    "name": "src/flutter",
    "url": "git@github.com:flutter/engine.git@b863200c37df4ed378042de11c4e9ff34e4e58c9",
    "custom_deps": {},
    "deps_file": "DEPS",
    "safesync_url": "",
  },
]
```


##### Xcode 32位支持

如果你在编译过程中遇到如下问题

```
ld: symbol(s) not found for architecture i386
```

原因是Xcode 10对32位编译进行了废弃，如果使用的是Xcode 10这个版本及以上，那么就需要另外进行一个处理，让其支持32位编译。

首先从 [macos-sdk](https://github.com/alexey-lysiuk/macos-sdk/releases) 获取 MacOS 10.13 SDK的压缩包，将其内容释放到

```
/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX10.13.sdk
```

如果执行如下命令返回10.13那就说明配置正确了。

```
python /path/to/engine/src/build/mac/find_sdk.py 10.12
```

具体流程可以参考官方文档
 - [Supporting-legacy-platforms](https://github.com/flutter/flutter/wiki/Supporting-legacy-platforms)

##### 构建Android引擎产物

Flutter Engine是基于Ninja进行构建的，Ninja是Google为了改进编译速度而开发出来的， Chromium目前也是通过Ninja进行构建的，由此看来，Flutter在工程上借鉴了很多Chromium的东西。

Flutter Engine的构建产物总体上有以下几种组合

| 是否优化（默认为optimized） | 运行模式 |
| ------ | ------ |
| unoptimized | debug |
| optimized | debug |
| unoptimized | profile |
| optimized | profile |
| unoptimized | release |
| optimized | release |


对于Andorid来说，有arm，arm64，x86和x86_64的产物区分，默认为arm，对于iOS来说，有arm，arm64的产物区分，默认为arm64。iOS还有模拟器的产物(使用\-\-simulator参数)。

除了设备端的产物，Host端（即PC）也需要编译出产物与之对应。Host端的产物是Android和iOS共用的，因此无需重复编译。

具体的所有组合可以参考 [Flutter's Mode](https://github.com/flutter/flutter/wiki/Flutter%27s-modes)

具体的可用编译选项如下:

```
usage: gn [-h] [--unoptimized] [--runtime-mode {debug,profile,release}]
          [--dynamic] [--interpreter] [--dart-debug]
          [--target-os {android,ios,linux}] [--android]
          [--android-cpu {arm,x64,x86,arm64}] [--ios] [--ios-cpu {arm,arm64}]
          [--simulator] [--linux-cpu {x64,x86,arm64,arm}]
          [--arm-float-abi {hard,soft,softfp}] [--goma] [--no-goma] [--lto]
          [--no-lto] [--clang] [--no-clang] [--target-sysroot TARGET_SYSROOT]
          [--target-toolchain TARGET_TOOLCHAIN]
          [--target-triple TARGET_TRIPLE]
          [--toolchain-prefix TOOLCHAIN_PREFIX] [--enable-vulkan]
          [--embedder-for-target]
```

以下是编译Andorid arm未优化的产物

```
cd /path/to/engine/src/
./flutter/tools/gn --android --unoptimized
ninja -C out/android_debug_unopt -j 8
./flutter/tools/gn --unoptimized
ninja -C out/host_debug_unopt -j 8
```

根据机器性能，需要编译的时间会有所不同，在Mac上，设备端和Host端两个产物一起编译完大约需要30-60分钟左右。

\-\-android-cpu参数如果不指定，那么arm是Andorid的默认使用的cpu。

下面简单提供几种组合方式


Android arm的debug优化版

```
cd /path/to/engine/src/
./flutter/tools/gn --android 
ninja -C out/android_debug -j 8
./flutter/tools/gn 
ninja -C out/host_debug -j 8
```

Android arm的release优化版

```
cd /path/to/engine/src/
./flutter/tools/gn --android --runtime-mode=release
ninja -C out/android_release -j 8
./flutter/tools/gn --runtime-mode=release
ninja -C out/host_release -j 8
```

Android arm的release非优化版

```
cd /path/to/engine/src/
./flutter/tools/gn --android --unoptimized --runtime-mode=release
ninja -C out/android_release_unopt -j 8
./flutter/tools/gn --unoptimized --runtime-mode=release
ninja -C out/host_release_unopt -j 8
```

Android arm64的release优化版

```
cd /path/to/engine/src/
./flutter/tools/gn --android --android-cpu arm64 --runtime-mode=release
ninja -C out/android_release_arm64 -j 8
./flutter/tools/gn --android-cpu arm64 --runtime-mode=release
ninja -C out/host_release_arm64 -j 8
```


Android x86的profile非优化版

```
cd /path/to/engine/src/
./flutter/tools/gn --android --android-cpu x86 --unoptimized --runtime-mode=profile
ninja -C out/android_profile_unopt_x86 -j 8
./flutter/tools/gn --android-cpu x86 --unoptimized --runtime-mode=profile
ninja -C out/host_profile_unopt_x86 -j 8
```

Android x64的profile非优化版

```
cd /path/to/engine/src/
./flutter/tools/gn --android --android-cpu x64 --unoptimized --runtime-mode=profile
ninja -C out/android_profile_unopt_x64 -j 8
./flutter/tools/gn --android-cpu x64 --unoptimized --runtime-mode=profile
ninja -C out/host_profile_unopt_x64 -j 8
```

对于Andorid来说，使用本地Engine的方式其实很简单，只要用gradle传递传递localEngineOut参数即可。传递方式可以通过命令行参数传入，也可通过gradle.properties属性文件传入

终端命令行参数传入

```
gradlew clean assembleDebug -PlocalEngineOut=/path/to/engine/src/out/android_debug_unopt
```

如果用属性文件传入，则在gradle.properties文件中加入如下内容

```
localEngineOut=/path/to/engine/src/out/android_debug_unopt
```

值得注意的是，对于assembleRelease编译，不支持x86和x64的产物，x86和x64的产物只能用于assembleDebug编译，在执行release构建时则会报错。比如使用x86产物在执行assembleRelease就会报如下错误：

```
../../third_party/dart/runtime/vm/compiler/jit/compiler.cc: 100: error: Precompilation not supported on IA32
```

如果直接使用flutter build方式进行构建，那需要传递两个参数，即\-\-local-engine和\-\-local-engine-src-path

```
flutter build apk --local-engine=android_debug_unopt --local-engine-src-path=/path/to/engine/src
```

其中--local-engine指向engine/src/out下的目录文件名

##### 构建iOS引擎产物

对于iOS来说，其实和Andorid也是类似的组合，简单提供几种组合编译方式。

\-\-ios-cpu参数如果不指定，那么arm64是iOS的默认使用的cpu。

iOS arm64未优化release版本

```
cd /path/to/engine/src/
./flutter/tools/gn --ios --unoptimized --runtime-mode=release
ninja -C out/ios_release_unopt -j 8
./flutter/tools/gn --unoptimized --runtime-mode=release
ninja -C out/host_release_unopt -j 8
```

iOS arm优化profile版本

```
cd /path/to/engine/src/
./flutter/tools/gn --ios --ios-cpu=arm --runtime-mode=profile
ninja -C out/ios_profile_arm -j 8
./flutter/tools/gn --ios-cpu=arm --runtime-mode=release
ninja -C out/host_profile_arm -j 8
```

iOS 模拟器未优化版本

```
cd /path/to/engine/src/
./flutter/tools/gn --ios --simulator --unoptimized
ninja -C out/ios_debug_sim_unopt -j 8
./flutter/tools/gn --simulator --unoptimized
ninja -C out/host_debug_sim_unopt -j 8
```

iOS使用本地Engine的话建议直接使用flutter build方式进行使用

```
flutter build ios --debug --local-engine=ios_debug_unopt --local-engine-src-path=/path/to/engine/src
```

release则使用
```
flutter build ios --local-engine=ios_release_unopt --local-engine-src-path=/path/to/engine/src
```

其中--local-engine指向engine/src/out下的目录文件名

如果在构建过程报了如下错误

```
    === BUILD TARGET Runner OF PROJECT Runner WITH CONFIGURATION Debug ===
    Unable to detect local Flutter engine build directory.
    Either specify a dependency_override for the sky_engine package in your pubspec.yaml and ensure --package-root is set if necessary, or set the $FLUTTER_ENGINE
    environment variable, or use --local-engine-src-path to specify the path to the root of your flutter/engine repository.
    Failed to package /path/to/your_project.
    Command /bin/sh failed with exit code 255
```

这其实是Flutter的问题，v1.0.0的 Flutter 对 iOS 的本地引擎支持存在一点小问题，必须导出engine/src目录到环境变量中。最新版本已经修复了该问题。如果你报了该错误，不妨换个版本进行编译，如果不想换，那么可以通过导出环境变量来修复这个问题。

```
export FLUTTER_ENGINE=/path/to/engine/src
```

如果在构建过程中报了如下错误

```
    === BUILD TARGET Runner OF PROJECT Runner WITH CONFIGURATION Release ===
    ========================================================================
    ERROR: Requested build with Flutter local engine at '/Users/lizhangqu/Desktop/engine/src/out/ios_debug_unopt'
    This engine is not compatible with FLUTTER_BUILD_MODE: 'release'.
    You can fix this by updating the LOCAL_ENGINE environment variable, or
    by running:
      flutter build ios --local-engine=ios_release
    or
      flutter build ios --local-engine=ios_release_unopt
    ========================================================================
```

根据提示可以看出，这是因为debug的产物不能用于release构建，请切换成release的产物后再构建。

##### IDE 支持

执行./flutter/tools/gn生成src/out目录后，会在src/out目录生成compile_commands.json文件，执行ninja完成构建后，可将compile_commands.json拷贝到src/compile_commands.json（或者src/flutter/compile_commands.json），然后使用Clion直接打开src目录(或者src/flutter目录)即可，Clion可以识别到compile_commands.json文件，并完成源码跳转。

除了Clion之外，你也可以直接用Xcode打开./flutter/tools/gn执行后生成的目录，如src/out/ios_debug_sim_unopt，里面会有Xcode需要的工程文件，从而完成源码跳转。

##### Android armeabi支持

默认情况下，如果指定\-\-android-cpu=arm的话，编译出来的引擎是只支持armeabi-v7a的，并不会产出armeabi的产物，这是因为Flutter依赖的一些library只支持armeabi，所以Flutter只能支持armeabi-v7a，这其实也是合理的。而在ndk16中，Google也废弃对armeabi、mips、mips64的支持。种种迹象都说明Google不建议我们再使用armeabi，而是使用armeabi-v7a。并且根据统计，市面上也基本没有armeabi的设备了，所以我们使用armeabi-v7a是完全没有问题的。

但是由于种种原因，可能一些第三方库只提供了armeabi的动态库，从而使我们在app中不得不使用armeabi。

由于Flutter依赖的一些第三方库只支持armeabi-v7a，所以我们修改引擎编译出armeabi的产物其实会有难度，可能需要修改很多地方。所以换一种思路，在构建App时，我们将armeabi-v7a的产物拷贝到armeabi中完成兼容。

这里提供两种方式进行处理：
 - 修改flutter.jar
 - 修改gradle脚本注入armeabi产物依赖

对于第一种方式，美团其实在其文章中进行了介绍，详情见 [Flutter原理与实践#SO库兼容性部分](https://tech.meituan.com/2018/08/09/waimai-flutter-practice.html)

这种方式依赖于修改产物flutter.jar文件，如果产物重新生成或者版本修改，其实有时候容易忘记修改，出现一些问题。

这里介绍另一种方式，通过gradle脚本注入armeabi产物。这种方式依赖于修改 packages/flutter_tools/gradle/flutter.gradle 文件，所以修改flutter.jar存在的问题，它也会存在，唯一的区别是前者通过直接修改产物，后者通过编译期注入产物。个人更倾向于使用gradle的方式。

在flutter.gradle中加入几个函数，用于建立对armeabi动态库的依赖

```
/**
 * create armeabi task
 */
private Task createArmeabiTask(Project project, String taskName, File flutterJar, File flutterArmV7Jar) {
    def flutterArmeabiJarTask = project.tasks.create(taskName, Jar) {
        destinationDir flutterArmV7Jar.parentFile
        archiveName flutterArmV7Jar.name
        from(project.zipTree(flutterJar).matching {
            //仅包含armeabi-v7a的so
            include "lib/armeabi-v7a/libflutter.so"
        }) {
            eachFile { def fcp ->
                if (fcp.relativePath.pathString.contains("lib/armeabi-v7a/libflutter.so")) {
                    //重命名路径，否则会拷贝到v7a目录
                    fcp.path = "lib/armeabi/libflutter.so"
                } else {
                    //非so排除
                    fcp.exclude()
                }
            }
        }
    }
    return flutterArmeabiJarTask
}

/**
 * add armeabi so for local engine
 */
private void addFlutterArmeabiJarApiDependencyForLocalEngine(Project project, File localFlutterJar) {
    if (this.flutterJar == null) {
        return
    }
    File flutterJar = localFlutterJar
    File flutterArmV7Jar = project.file("${project.buildDir}/${AndroidProject.FD_INTERMEDIATES}/flutter/armeabi/flutter-armeabi.jar")

    def flutterArmeabiJarTask = createArmeabiTask(project, "${flutterBuildPrefix}ArmeabiJar", flutterJar, flutterArmV7Jar)

    if (flutterArmeabiJarTask == null) {
        return
    }

    Task preBuildTask = project.tasks.findByName("preBuild")
    if (preBuildTask) {
        preBuildTask.dependsOn flutterArmeabiJarTask
    }

    project.dependencies {
        String configuration;
        if (project.getConfigurations().findByName("api")) {
            configuration = "api";
        } else {
            configuration = "compile";
        }
        add(configuration, project.files {
            flutterArmeabiJarTask
        })
    }
}

/**
 * add armeabi so for prebuilt engine
 */
private void addFlutterArmeabiJarApiDependency(Project project, def buildType, String targetArch) {
    def flutterArmeabiJarTask = null
    if (targetArch == 'arm') {
        File flutterJar = flutterJarFor(buildModeFor(buildType))
        File flutterArmV7Jar = project.file("${project.buildDir}/${AndroidProject.FD_INTERMEDIATES}/flutter/armeabi/${buildType.name}/flutter-armeabi.jar")
        flutterArmeabiJarTask = createArmeabiTask(project, "${flutterBuildPrefix}${buildType.name.capitalize()}ArmeabiJar", flutterJar, flutterArmV7Jar)
    }
    if (flutterArmeabiJarTask == null) {
        return
    }

    Task javacTask = project.tasks.findByName("compile${buildType.name.capitalize()}JavaWithJavac")
    if (javacTask) {
        javacTask.dependsOn flutterArmeabiJarTask
    }
    Task kotlinTask = project.tasks.findByName("compile${buildType.name.capitalize()}Kotlin")
    if (kotlinTask) {
        kotlinTask.dependsOn flutterArmeabiJarTask
    }

    project.dependencies {
        String configuration;
        if (project.getConfigurations().findByName("api")) {
            configuration = buildType.name + "Api";
        } else {
            configuration = buildType.name + "Compile";
        }
        add(configuration, project.files {
            flutterArmeabiJarTask
        })
    }
}
```


找到if (project.hasProperty('localEngineOut')) 逻辑部分

将如下逻辑

```
project.dependencies {
    if (project.getConfigurations().findByName("api")) {
        api project.files(flutterJar)
    } else {
        compile project.files(flutterJar)
    }
}
```

修改为注入我们的逻辑

```
project.dependencies {
    if (project.getConfigurations().findByName("api")) {
        api project.files(flutterJar)
    } else {
        compile project.files(flutterJar)
    }
    //加入如下函数调用
    addFlutterArmeabiJarApiDependencyForLocalEngine(project, flutterJar)
}
```

在if (project.hasProperty('localEngineOut'))的 else 部分逻辑中找到如下逻辑部分

将如下逻辑

```
project.android.buildTypes.each {
    addFlutterJarApiDependency(project, it, flutterX86JarTask)
}
project.android.buildTypes.whenObjectAdded {
    addFlutterJarApiDependency(project, it, flutterX86JarTask)
}
```

修改为注入我们的逻辑

```
project.android.buildTypes.each {
    addFlutterJarApiDependency(project, it, flutterX86JarTask)
    //加入如下函数调用
    addFlutterArmeabiJarApiDependency(project, it, targetArch)
}
project.android.buildTypes.whenObjectAdded {
    addFlutterJarApiDependency(project, it, flutterX86JarTask)
    //加入如下函数调用
    addFlutterArmeabiJarApiDependency(project, it, targetArch)
}
```

这样在执行gradlew assembleDebug或者gradlew assembleRelease的时候，就会自动建立对我们中间临时生成的flutter-armeabi.jar的依赖，该jar文件中只有一个文件，即armeabi目录下的libflutter.so文件，从而完成对armeabi的兼容。


这里我将其封装成了gradle插件，有兴趣可以参考 [plugin-flutter-armeabi](https://github.com/lizhangqu/plugin-flutter-armeabi)

```
buildscript {
    repositories {
        jcenter()
    }
    dependencies {
        classpath "io.github.lizhangqu:plugin-flutter-armeabi:1.0.0"
    }
}

apply plugin: 'flutter.armeabi'
```

### Flutter Framework开发环境

有时候除了需要编译Flutter Engine，你可能还需要修改dart部分，即Flutter Framework，比起Flutter Engine，Flutter Framework的编译比较简单，首先需要clone一份源码

```
git clone https://github.com/flutter/flutter.git flutter_framework
```

然后执行包更新获取Flutter所依赖的Dart依赖

```
cd /path/to/flutter_framework
./bin/flutter update-packages
cd /path/to/flutter_framework/packages/flutter
../../bin/flutter doctor
../../bin/flutter packages get
```

之后使用IDE直接打开工程即可，这里官方推荐使用Android Studio，也可以使用Intellij IDEA(装有Flutter插件)，注意这里打开的目录为/path/to/flutter_framework/packages/flutter，这个目录下的文件是我们runtime所需要的dart文件，如果你要进行定制或者bugfix，可修改该文件夹下的文件，从而完成定制。

定制完成后，如果你需要使用自己的Flutter Framework，注意完成修改后，请务必在你修改的分支上打上TAG，避免一些不必要的坑，TAG这里是有要求的，一般是v开头，跟着三位数的版本号，如v1.9.1，但是如果是hotfix版本，则会跟着hotfix的版本号，如v1.9.1+hotfix.4，不是这两种格式的TAG，Flutter会无法识别到，因此自己打的TAG可以在原始TAG后追加五位数，如v1.9.100001，如果是hotfix版本，就是v1.9.1+hotfix.400001，末尾五位数表示我们修改过的版本，每次修改数字进行递增即可。


### 总结

整个Flutter Engine编译过程中，其实官方文档已经很详细了，我们只要将相关联的文档组合在一起，最终就能编译出Flutter Engine并进行使用。当然也有一些地方是官方文档中没有的，需要我们自己想办法解决的，比如文中最开始的代理的配置，文章最后提到的Android armeabi的支持等等，这种就完全只能根据经验进行判断到底是什么地方出现了问题，并通过实践进行解决。另一方面，其实很多东西都是相通的，就像Flutter用了很多和Chromium一样的构建工具一样。

### 参考链接

 - [Setting-up-the-Engine-development-environment](https://github.com/flutter/flutter/wiki/Setting-up-the-Engine-development-environment)
 - [Compiling-the-engine](https://github.com/flutter/flutter/wiki/Compiling-the-engine)
 - [Flutter's-modes](https://github.com/flutter/flutter/wiki/Flutter%27s-modes)
 - [Supporting-legacy-platforms](https://github.com/flutter/flutter/wiki/Supporting-legacy-platforms)
 - [Using depot_tools](https://dev.chromium.org/developers/how-tos/depottools)
 - [depot_tools_tutorial](https://commondatastorage.googleapis.com/chrome-infra-docs/flat/depot_tools/docs/html/depot_tools_tutorial.html)
 - [The Ninja build system](https://ninja-build.org/manual.html)
 - [macos-sdk](https://github.com/alexey-lysiuk/macos-sdk)
 - [Flutter原理与实践](https://tech.meituan.com/2018/08/09/waimai-flutter-practice.html)