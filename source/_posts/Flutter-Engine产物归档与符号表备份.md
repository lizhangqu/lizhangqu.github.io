title: Flutter Engine产物归档与符号表备份
date: 2019-12-12 12:29:52
categories: [Flutter]
tags: [Flutter, Engine, artifacts, symbols, backup, build, compile]
---

自定义引擎编译完成后，我们需要将产物进行归档以备使用，同时为了定位到crash时发生的堆栈信息，我们需要将符号表进行备份，本文基于macOS环境下的v1.9.1产物，最新版的v1.12.13版本产物有所变化，有兴趣自行查看。Flutter官方提供的方式是基于Docker的方式，可以参考 [flutter/engine/ci](https://github.com/flutter/engine/tree/master/ci)但是并没有提供Docker之外的工具用于产物归档和符号表备份。
<!-- more -->


### Android产物

v1.9.1版本所有分发到终端用户电脑中的产物，Android共有8个，分别是debug构建的arm, arm64, x86, x64产物，profile构建的arm, arm64产物，release构建的arm, arm64产物。这些产物基本上以flutter.jar和gen_snapshot文件为主。

进入到engine/src目录，执行如下命令调用gn生成Ninja配置文件

```
cd /path/to/engine/src

./flutter/tools/gn --runtime-mode=debug --android-cpu=arm --android
./flutter/tools/gn --runtime-mode=profile --android-cpu=arm --android
./flutter/tools/gn --runtime-mode=release --android-cpu=arm --android
./flutter/tools/gn --runtime-mode=debug --android-cpu=arm64 --android
./flutter/tools/gn --runtime-mode=profile --android-cpu=arm64 --android
./flutter/tools/gn --runtime-mode=release --android-cpu=arm64 --android
./flutter/tools/gn --runtime-mode=debug --android-cpu=x86 --android
./flutter/tools/gn --runtime-mode=debug --android-cpu=x64 --android
```

构建前执行clean

```
ninja -C out/android_debug -t clean
ninja -C out/android_profile -t clean
ninja -C out/android_release -t clean
ninja -C out/android_debug_arm64 -t clean
ninja -C out/android_profile_arm64 -t clean
ninja -C out/android_release_arm64 -t clean
ninja -C out/android_debug_x86 -t clean
ninja -C out/android_debug_x64 -t clean
```

调用ninja执行构建

```
ninja -C out/android_debug -j 8
ninja -C out/android_profile -j 8
ninja -C out/android_release -j 8
ninja -C out/android_debug_arm64 -j 8
ninja -C out/android_profile_arm64 -j 8
ninja -C out/android_release_arm64 -j 8
ninja -C out/android_debug_x86 -j 8
ninja -C out/android_debug_x64 -j 8
```

构建完成我们需要将**flutter.jar**文件和**gen_snapshot**文件进行归档(v1.9.1版本debug构建不需要gen_snapshot产物)，同时需要将**libflutter.so**符号表文件进行备份

可用类似如下命令完成备份（如果宿主操作系统不是macOS，那么对应的**darwin-x64**需要换成**linux-x64**或者**windows-x64**）

```
mkdir -p flutter-engine/artifacts/android-arm
mkdir -p flutter-engine/symbols/android-arm
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/android_debug/flutter.jar flutter-engine/artifacts/android-arm/flutter.jar
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/android_debug/libflutter.so flutter-engine/symbols/android-arm/libflutter.so
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/android_debug/libflutter.so.TOC flutter-engine/symbols/android-arm/libflutter.so.TOC

mkdir -p flutter-engine/artifacts/android-arm-profile
mkdir -p flutter-engine/artifacts/android-arm-profile/darwin-x64
mkdir -p flutter-engine/symbols/android-arm-profile
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/android_profile/flutter.jar flutter-engine/artifacts/android-arm-profile/flutter.jar
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/android_profile/clang_x64/gen_snapshot flutter-engine/artifacts/android-arm-profile/darwin-x64/gen_snapshot
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/android_profile/libflutter.so flutter-engine/symbols/android-arm-profile/libflutter.so
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/android_profile/libflutter.so.TOC flutter-engine/symbols/android-arm-profile/libflutter.so.TOC


mkdir -p flutter-engine/artifacts/android-arm-release
mkdir -p flutter-engine/artifacts/android-arm-release/darwin-x64
mkdir -p flutter-engine/symbols/android-arm-release
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/android_release/flutter.jar flutter-engine/artifacts/android-arm-release/flutter.jar
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/android_release/clang_x64/gen_snapshot flutter-engine/artifacts/android-arm-release/darwin-x64/gen_snapshot
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/android_release/libflutter.so flutter-engine/symbols/android-arm-release/libflutter.so
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/android_release/libflutter.so.TOC flutter-engine/symbols/android-arm-release/libflutter.so.TOC

mkdir -p flutter-engine/artifacts/android-arm64
mkdir -p flutter-engine/symbols/android-arm64
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/android_debug_arm64/flutter.jar flutter-engine/artifacts/android-arm64/flutter.jar
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/android_debug_arm64/libflutter.so flutter-engine/symbols/android-arm64/libflutter.so
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/android_debug_arm64/libflutter.so.TOC flutter-engine/symbols/android-arm64/libflutter.so.TOC

mkdir -p flutter-engine/artifacts/android-arm64-profile
mkdir -p flutter-engine/artifacts/android-arm64-profile/darwin-x64
mkdir -p flutter-engine/symbols/android-arm64-profile
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/android_profile_arm64/flutter.jar flutter-engine/artifacts/android-arm64-profile/flutter.jar
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/android_profile_arm64/clang_x64/gen_snapshot flutter-engine/artifacts/android-arm64-profile/darwin-x64/gen_snapshot
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/android_profile_arm64/libflutter.so flutter-engine/symbols/android-arm64-profile/libflutter.so
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/android_profile_arm64/libflutter.so.TOC flutter-engine/symbols/android-arm64-profile/libflutter.so.TOC

mkdir -p flutter-engine/artifacts/android-arm64-release
mkdir -p flutter-engine/artifacts/android-arm64-release/darwin-x64
mkdir -p flutter-engine/symbols/android-arm64-release
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/android_release_arm64/flutter.jar flutter-engine/artifacts/android-arm64-release/flutter.jar
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/android_release_arm64/clang_x64/gen_snapshot flutter-engine/artifacts/android-arm64-release/darwin-x64/gen_snapshot
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/android_release_arm64/libflutter.so flutter-engine/symbols/android-arm64-release/libflutter.so
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/android_release_arm64/libflutter.so.TOC flutter-engine/symbols/android-arm64-release/libflutter.so.TOC

mkdir -p flutter-engine/artifacts/android-x86
mkdir -p flutter-engine/symbols/android-x86
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/android_debug_x86/flutter.jar flutter-engine/artifacts/android-x86/flutter.jar
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/android_debug_x86/lib.stripped/libflutter.so flutter-engine/artifacts/android-x86/libflutter.so
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/android_debug_x86/libflutter.so flutter-engine/symbols/android-x86/libflutter.so
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/android_debug_x86/libflutter.so.TOC flutter-engine/symbols/android-x86/libflutter.so.TOC

mkdir -p flutter-engine/artifacts/android-x64
mkdir -p flutter-engine/symbols/android-x64
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/android_debug_x64/flutter.jar flutter-engine/artifacts/android-x64/flutter.jar
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/android_debug_x64/lib.stripped/libflutter.so flutter-engine/artifacts/android-x64/libflutter.so
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/android_debug_x64/libflutter.so flutter-engine/symbols/android-x64/libflutter.so
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/android_debug_x64/libflutter.so.TOC flutter-engine/symbols/android-x64/libflutter.so.TOC
```

很遗憾，Flutter团队没有提供一个一键归档的工具，我们后文提供。

最终如图所示

![android-artifacts.png](android-artifacts.png)

![android-symbols.png](android-symbols.png)


### iOS产物

v1.9.1版本所有分发到终端用户电脑中的产物，iOS共有3个，分别是debug产物, profile产物，release产物，但是debug产物由ios_debug_arm, ios_debug_arm64, ios_debug_sim三个产物经过lipo合成一个ios产物，profile产物由ios_profile_arm, ios_profile_arm64, ios_debug_sim三个产物经过lipo合成一个ios-profile产物，release产物由ios_release_arm, ios_release_arm64, ios_debug_sim三个产物经过lipo合成一个ios-release产物，最终就是终端用户看到的三个产物。


进入到engine/src目录，执行如下命令调用gn生成Ninja配置文件

```
cd /path/to/engine/src

./flutter/tools/gn --runtime-mode=debug --ios-cpu=arm --ios
./flutter/tools/gn --runtime-mode=profile --ios-cpu=arm --ios
./flutter/tools/gn --runtime-mode=release --ios-cpu=arm --ios
./flutter/tools/gn --runtime-mode=debug --ios-cpu=arm64 --ios
./flutter/tools/gn --runtime-mode=profile --ios-cpu=arm64 --ios
./flutter/tools/gn --runtime-mode=release --ios-cpu=arm64 --ios
./flutter/tools/gn --runtime-mode=debug --ios-cpu=x86 --ios
./flutter/tools/gn --runtime-mode=debug --ios-cpu=x64 --ios
```


构建前执行clean

```
ninja -C out/ios_debug_arm -t clean
ninja -C out/ios_profile_arm -t clean
ninja -C out/ios_release_arm -t clean
ninja -C out/ios_debug -t clean
ninja -C out/ios_profile -t clean
ninja -C out/ios_release -t clean
ninja -C out/ios_debug_sim -t clean
```

调用ninja执行构建

```

ninja -C out/ios_debug_arm -j 8
ninja -C out/ios_profile_arm -j 8
ninja -C out/ios_release_arm -j 8
ninja -C out/ios_debug -j 8
ninja -C out/ios_profile -j 8
ninja -C out/ios_release -j 8
ninja -C out/ios_debug_sim -j 8
```



构建完成我们需要将**Flutter.framework**文件和**gen_snapshot**文件进行归档，同时需要制作**dSYM**符号表文件。

和Android不同的是，iOS提供了两个工具，一个是用于Flutter.framework的规定及符号表导出，另一个是用于gen_snapshot文件的归档，他们位于engine/src/flutter/sky/tools/create_ios_framework.py和engine/src/flutter/sky/tools/create_macos_gen_snapshots.py。

执行如下命令完成产物归档及符号表备份，注意只有release构建需要执行strip操作。

```
cd /path/to/engine/src

./flutter/sky/tools/create_ios_framework.py \
--arm64-out-dir /Users/lizhangqu/software/flutter_dev/engine/src/out/ios_release \
--armv7-out-dir /Users/lizhangqu/software/flutter_dev/engine/src/out/ios_release_arm  \
--simulator-out-dir /Users/lizhangqu/software/flutter_dev/engine/src/out/ios_debug_sim  \
--dst /Users/lizhangqu/software/flutter_dev/engine/src/out/flutter-engine/artifacts/ios-release \
--strip --dsym

./flutter/sky/tools/create_ios_framework.py \
--arm64-out-dir /Users/lizhangqu/software/flutter_dev/engine/src/out/ios_profile \
--armv7-out-dir /Users/lizhangqu/software/flutter_dev/engine/src/out/ios_profile_arm  \
--simulator-out-dir /Users/lizhangqu/software/flutter_dev/engine/src/out/ios_debug_sim  \
--dst /Users/lizhangqu/software/flutter_dev/engine/src/out/flutter-engine/artifacts/ios-profile \
--dsym

./flutter/sky/tools/create_ios_framework.py \
--arm64-out-dir /Users/lizhangqu/software/flutter_dev/engine/src/out/ios_debug \
--armv7-out-dir /Users/lizhangqu/software/flutter_dev/engine/src/out/ios_debug_arm  \
--simulator-out-dir /Users/lizhangqu/software/flutter_dev/engine/src/out/ios_debug_sim  \
--dst /Users/lizhangqu/software/flutter_dev/engine/src/out/flutter-engine/artifacts/ios \
--dsym

./flutter/sky/tools/create_macos_gen_snapshots.py \
--arm64-out-dir /Users/lizhangqu/software/flutter_dev/engine/src/out/ios_release \
--armv7-out-dir /Users/lizhangqu/software/flutter_dev/engine/src/out/ios_release_arm \
--dst /Users/lizhangqu/software/flutter_dev/engine/src/out/flutter-engine/artifacts/ios-release

./flutter/sky/tools/create_macos_gen_snapshots.py \
--arm64-out-dir /Users/lizhangqu/software/flutter_dev/engine/src/out/ios_profile \
--armv7-out-dir /Users/lizhangqu/software/flutter_dev/engine/src/out/ios_profile_arm \
--dst /Users/lizhangqu/software/flutter_dev/engine/src/out/flutter-engine/artifacts/ios-profile

./flutter/sky/tools/create_macos_gen_snapshots.py \
--arm64-out-dir /Users/lizhangqu/software/flutter_dev/engine/src/out/ios_debug \
--armv7-out-dir /Users/lizhangqu/software/flutter_dev/engine/src/out/ios_debug_arm \
--dst /Users/lizhangqu/software/flutter_dev/engine/src/out/flutter-engine/artifacts/ios

mkdir -p /Users/lizhangqu/software/flutter_dev/engine/src/out/flutter-engine/symbols/ios
mv /Users/lizhangqu/software/flutter_dev/engine/src/out/flutter-engine/artifacts/ios/Flutter.dSYM /Users/lizhangqu/software/flutter_dev/engine/src/out/flutter-engine/symbols/ios/Flutter.dSYM

mkdir -p /Users/lizhangqu/software/flutter_dev/engine/src/out/flutter-engine/symbols/ios-profile
mv /Users/lizhangqu/software/flutter_dev/engine/src/out/flutter-engine/artifacts/ios-profile/Flutter.dSYM /Users/lizhangqu/software/flutter_dev/engine/src/out/flutter-engine/symbols/ios-profile/Flutter.dSYM

mkdir -p /Users/lizhangqu/software/flutter_dev/engine/src/out/flutter-engine/symbols/ios-release
mv /Users/lizhangqu/software/flutter_dev/engine/src/out/flutter-engine/artifacts/ios-release/Flutter.dSYM /Users/lizhangqu/software/flutter_dev/engine/src/out/flutter-engine/symbols/ios-release/Flutter.dSYM
mv /Users/lizhangqu/software/flutter_dev/engine/src/out/flutter-engine/artifacts/ios-release/Flutter.unstripped /Users/lizhangqu/software/flutter_dev/engine/src/out/flutter-engine/symbols/ios-release/Flutter.unstripped


cp /Users/lizhangqu/software/flutter_dev/engine/src/out/ios_debug/Flutter.podspec /Users/lizhangqu/software/flutter_dev/engine/src/out/flutter-engine/artifacts/ios/Flutter.podspec
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/ios_profile/Flutter.podspec /Users/lizhangqu/software/flutter_dev/engine/src/out/flutter-engine/artifacts/ios-profile/Flutter.podspec
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/ios_release/Flutter.podspec /Users/lizhangqu/software/flutter_dev/engine/src/out/flutter-engine/artifacts/ios-release/Flutter.podspec


cp /Users/lizhangqu/software/flutter_dev/engine/src/out/ios_debug/LICENSE /Users/lizhangqu/software/flutter_dev/engine/src/out/flutter-engine/artifacts/ios/LICENSE
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/ios_profile/LICENSE /Users/lizhangqu/software/flutter_dev/engine/src/out/flutter-engine/artifacts/ios-profile/LICENSE
cp /Users/lizhangqu/software/flutter_dev/engine/src/out/ios_release/LICENSE /Users/lizhangqu/software/flutter_dev/engine/src/out/flutter-engine/artifacts/ios-release/LICENSE

```

最终如图所示

![ios-artifacts.png](ios-artifacts.png)

![ios-symbols.png](ios-symbols.png)


### 自动化归档

鉴于Flutter官方没有提供一个工具支持构建到产物归档和符号表备份，在持续集成环境下，需要自己处理好相关逻辑。

我这里简单编写了一个python脚本，可用于持续集成环境，见:
 - [Flutter Engine构建产物归档工具](https://github.com/lizhangqu/flutter_engine_build)

使用方法:

```
./flutter_engine_build \
  --local-engine-src-path /path/to/engine/src \
  --no-ios \
  --no-android \
  --no-arm \
  --no-arm64 \
  --no-x86 \
  --no-x64 \ 
  --no-debug \
  --no-profile \
  --no-release \
  --gn \
  --clean \
  --build \
  --artifacts \
  --symbols
```


提示:
 - 如果你不需要执行iOS相关脚本，那么添加--no-ios参数，默认都会执行
 - 如果你不需要执行android相关脚本，那么添加--no-android参数，默认都会执行
 - 如果你不需要执行arm相关脚本，那么添加--no-arm参数，默认都会执行
 - 如果你不需要执行arm64相关脚本，那么添加--no-arm64参数，默认都会执行
 - 如果你不需要执行x86相关脚本，那么添加--no-x86参数，默认都会执行
 - 如果你不需要执行x64相关脚本，那么添加--no-x64参数，默认都会执行
 - 如果需要构建iOS模拟器产物，那么添加--x64参数，默认情况下就会执行，除非添加了--no-x64参数
 - 如果你不需要执行debug相关脚本，那么添加--no-debug参数，默认都会执行
 - 如果你不需要执行profile相关脚本，那么添加--no-profile参数，默认都会执行
 - 如果你不需要执行release相关脚本，那么添加--no-release参数，默认都会执行
 - 如果你需要调用gn生成Ninja配置文件，那么添加--gn参数，默认不会执行
 - 如果你需要调用Ninja执行clean，那么添加--clean参数，默认不会执行
 - 如果你需要调用Ninja执行build，那么添加--build参数，默认不会执行
 - **如果你需要按cache目录结构归档产物，那么添加--artifacts参数，默认不会执行**
 - **如果你需要归档符号表文件，那么添加--symbols参数，默认不会执行**
 - 以上参数为同时作用生效，即**与**的关系
 - 产物和符号表归档目录为/path/to/engine/src/out/engine/artifacts和/path/to/engine/src/out/engine/symbols下
 - iOS的产物归档需要同时构建完对应构建类型(debug，profile，release)下的arm，arm64，debug_sim产物，否则归档会失败
 
如果你需要构建iOS debug产物，并进行归档，同时备份符号表，则执行

```
./flutter_engine_build \
  --local-engine-src-path /path/to/engine/src \
  --no-android \
  --no-profile \
  --no-release \
  --gn \
  --clean \
  --build \
  --artifacts \
  --symbols
```

如果你需要构建Android profile arm64产物，并进行归档，同时备份符号表，则执行

```
./flutter_engine_build \
  --local-engine-src-path /path/to/engine/src \
  --no-ios \
  --no-debug \
  --no-release \
  --no-arm \
  --no-x86 \
  --no-x64 \
  --gn \
  --clean \
  --build \
  --artifacts \
  --symbols
```

如果你不需要执行Ninja构建，仅仅是归档iOS产物和符号表，则执行

```
./flutter_engine_build \
  --local-engine-src-path /path/to/engine/src \
  --no-android \
  --artifacts \
  --symbols
```

假如你执行如下命令

```
./flutter_engine_build \
  --local-engine-src-path /path/to/engine/src \
  --gn \
  --clean \
  --build \
  --artifacts \
  --symbols
```

那么android会执行的构建有：

debug-arm，debug-arm64，debug-x86，debug-x64，profile-arm，profile-arm64，release-arm，release-arm64

iOS会执行的构建有：

debug-arm，debug-arm64，debug-sim，profile-arm，profile-arm64，release-arm，release-arm64

并且会将产物和符号表进行归档




