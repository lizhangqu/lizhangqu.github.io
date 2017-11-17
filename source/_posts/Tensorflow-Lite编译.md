title: Tensorflow Lite编译
date: 2017-11-17 09:58:17
categories: [TensorFlow]
tags: [TensorFlow, TensorFlow Lite，Android]
---

Google最近发布了Tensorflow Lite，并且提供了demo，虽然该demo可以使用**bazel build --cxxopt='--std=c++11' //tensorflow/contrib/lite/java/demo/app/src/main:TfLiteCameraDemo**命令成功编译出来，但是文档中并没有提及如何纯粹的编译出动态库，参考之前的一篇文章[《当 Android 开发者遇见 TensorFlow》](/2017/06/02/当Android开发者遇见TensorFlow/)，这篇文章就简单介绍一下如何编译动态库

<!-- more -->

### clone 代码

```
git clone https://github.com/tensorflow/tensorflow.git
```

### 修改TensorFlow项目根下的WROKSPACE文件

将以下代码反注释

```
# Uncomment and update the paths in these entries to build the Android demo.
android_sdk_repository(
    name = "androidsdk",
    api_level = 23,
    # Ensure that you have the build_tools_version below installed in the
    # SDK manager as it updates periodically.
    build_tools_version = "26.0.1",
    # Replace with path to Android SDK on your system
    path = "/Users/lizhangqu/AndroidSDK",
)
#
android_ndk_repository(
    name="androidndk",
    path="/Users/lizhangqu/AndroidNDK/android-ndk-r14b",
    # This needs to be 14 or higher to compile TensorFlow.
    # Please specify API level to >= 21 to build for 64-bit
    # archtectures or the Android NDK will automatically select biggest
    # API level that it supports without notice.
    # Note that the NDK version is not the API level.
    api_level=14)
```

然后修改android_sdk_repository中的path为自己电脑中的android sdk目录，修改android_ndk_repository中的path为自己电脑的android ndk目录。

值得注意的是，ndk的版本，官方建议使用大于r14的版本，下载地址[android-ndk-r14b-darwin-x86_64.zip](https://dl.google.com/android/repository/android-ndk-r14b-darwin-x86_64.zip?hl=zh-cn
)

### 编译

确保必要的工具已经安装，如bazel

```
bazel build --cxxopt='--std=c++11' //tensorflow/contrib/lite/java:tensorflowlite \
--crosstool_top=//external:android/crosstool \
--host_crosstool_top=@bazel_tools//tools/cpp:toolchain \
--cpu=armeabi
```

编译其他ABI请修改cpu参数，分别为

```
--cpu=armeabi
--cpu=armeabi-v7a
--cpu=arm64-v8a
--cpu=mips
--cpu=mips64
--cpu=x86
--cpu=x86_64
```

产物位于

```
bazel-bin/tensorflow/contrib/lite/java/libtensorflowlite_jni.so
bazel-bin/tensorflow/contrib/lite/java/libtensorflowlitelib.jar
```

注意编译mips和mips64的时候，需要将构建脚本稍微修改一下，删除一部分代码，否则会报错

找到/tensorflow/contrib/lite/build_def.bzl文件，找到如下代码

```
def tflite_linkopts_unstripped():
  """Defines linker flags to reduce size of TFLite binary.

     These are useful when trying to investigate the relative size of the
     symbols in TFLite.

  Returns:
     a select object with proper linkopts
  """
  return select({
      "//tensorflow:android": [
          "-Wl,--no-export-dynamic", # Only inc syms referenced by dynamic obj.
          "-Wl,--exclude-libs,ALL",  # Exclude syms in all libs from auto export.
          "-Wl,--gc-sections", # Eliminate unused code and data.
          "-Wl,--as-needed", # Don't link unused libs.
      ],
      "//tensorflow/contrib/lite:mips": [],
      "//tensorflow/contrib/lite:mips64": [],
      "//conditions:default": [
          "-Wl,--icf=all",  # Identical code folding.
      ],
  })

def tflite_jni_linkopts_unstripped():
  """Defines linker flags to reduce size of TFLite binary with JNI.

     These are useful when trying to investigate the relative size of the
     symbols in TFLite.

  Returns:
     a select object with proper linkopts
  """
  return select({
      "//tensorflow:android": [
          "-Wl,--gc-sections", # Eliminate unused code and data.
          "-Wl,--as-needed", # Don't link unused libs.
      ],
      "//tensorflow/contrib/lite:mips": [],
      "//tensorflow/contrib/lite:mips64": [],
      "//conditions:default": [
          "-Wl,--icf=all",  # Identical code folding.
      ],
  })

```

将上面代码中的下面这段删除

```
"//tensorflow:android": [
          "-Wl,--no-export-dynamic", # Only inc syms referenced by dynamic obj.
          "-Wl,--exclude-libs,ALL",  # Exclude syms in all libs from auto export.
          "-Wl,--gc-sections", # Eliminate unused code and data.
          "-Wl,--as-needed", # Don't link unused libs.
      ],
```

以及这一段也删除

```
 "//tensorflow:android": [
          "-Wl,--gc-sections", # Eliminate unused code and data.
          "-Wl,--as-needed", # Don't link unused libs.
      ],
```

临时删除后，编译完mips和mips64还原即可，不然会报如下错误

```
ERROR: /Users/lizhangqu/Desktop/tensorflow/tensorflow/contrib/lite/java/BUILD:133:1: Illegal ambiguous match on configurable attribute "linkopts" in //tensorflow/contrib/lite/java:libtensorflowlite_jni.so:
//tensorflow/contrib/lite:mips
//tensorflow:android
Multiple matches are not allowed unless one is unambiguously more specialized.
ERROR: Analysis of target '//tensorflow/contrib/lite/java:tensorflowlite' failed; build aborted:

/Users/lizhangqu/Desktop/tensorflow/tensorflow/contrib/lite/java/BUILD:133:1: Illegal ambiguous match on configurable attribute "linkopts" in //tensorflow/contrib/lite/java:libtensorflowlite_jni.so:
//tensorflow/contrib/lite:mips
//tensorflow:android
Multiple matches are not allowed unless one is unambiguously more specialized.
```

```
ERROR: /Users/lizhangqu/Desktop/tensorflow/tensorflow/contrib/lite/java/BUILD:133:1: Illegal ambiguous match on configurable attribute "linkopts" in //tensorflow/contrib/lite/java:libtensorflowlite_jni.so:
//tensorflow/contrib/lite:mips64
//tensorflow:android
Multiple matches are not allowed unless one is unambiguously more specialized.
ERROR: Analysis of target '//tensorflow/contrib/lite/java:tensorflowlite' failed; build aborted:

/Users/lizhangqu/Desktop/tensorflow/tensorflow/contrib/lite/java/BUILD:133:1: Illegal ambiguous match on configurable attribute "linkopts" in //tensorflow/contrib/lite/java:libtensorflowlite_jni.so:
//tensorflow/contrib/lite:mips64
//tensorflow:android
Multiple matches are not allowed unless one is unambiguously more specialized.
```

