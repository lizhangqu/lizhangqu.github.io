title: Flutter Tools 断点调试
date: 2019-03-21 14:49:23
categories: [Flutter]
tags: [flutter, debugger, breakpoint]
---

### 前言

在Flutter的开发过程中，构建App的时候会遇到一些问题需要对其进行调试，亦或者是需要了解其构建过程需要对其进行调试，主要包括Flutter Tools的调试和Flutter App的调试，Flutter App的调试比较简单，本篇文章着重介绍一下Flutter Tools相关的调试技巧。

<!-- more -->

### Flutter Tools 调试

#### 导入Flutter Tools 源码

正式开始调试前，我们需要先导入Flutter Tools的源码。

我们可以直接使用Android Studio或者Intellij IDEA打开该文件夹
```
/path/to/flutter/packages/flutter_tools
```

我们在执行flutter命令后，其代码的调用入口会走到该文件。
```
/path/to/flutter/packages/flutter_tools/bin/flutter_tools.dart
```

其内容如下
```
import 'package:flutter_tools/executable.dart' as executable;

void main(List<String> args) {
  executable.main(args);
}
```

那么我们如何进行断点调试呢？

#### 断点调试

Flutter Tools的断点调试无外乎两种方式，和普通App的断点调试以及Gradle插件的断点调试都是类似的。

1、导出环境变量，让其启动的时候等待debug进程attach
2、直接使用IDEA以debug方式运行

对于第一种方法，我们通过指定环境变量，让Observatory在指定端口监听，并让其在启动的时候进行等待debug进程，整个过程和gradle的插件断点调试类似。

导出环境变量，让Observatory在指定的65432端口监听

```
export FLUTTER_TOOL_ARGS="--pause_isolates_on_start --enable-vm-service:65432"
```

之后执行flutter run命令后，会输出相关信息，看到如下内容说明设置成功了

```
Observatory listening on http://127.0.0.1:65432/
```

这时候该进程就会一直等待，直到我们attach到该进程上去，那么如何attach呢？

使用 Android Studio 或者 Intellij Idea 新建一个Configuration。
Edit Configurations -》New -》 Dart Remote Debug -》 输入Host为127.0.0.1，端口号为65432

如图所示

![configuration.png](configuration.png)

然后以debug方式运行该新建的configuration，这时候之前等待的进程就会继续执行下去，也可以正常的在断点的地方停住，如图所示

![debug.png](debug.png)

从断点可以看到，我们执行flutter的参数是run。

除了以上这种方式，我们也可以使用第二种方法，即直接在 Android Studio 或者 Intellij Idea 中直接运行指定命令，从而进行调试。新建一个Dart Command Line App的Configuration。

Edit Configurations -》New -》 Dart Command Line App。

其中Dart file指向flutter_tools.dart文件，Program arguments中填写需要执行的命令，假如我们要构建apk，正常来说需要执行flutter build apk命令进行构建，此时则填写build apk，如图所示

![debug_run.png](debug_run.png)

然后以debug的方式运行该新建的configuration，如图所示

![direct_run.png](direct_run.png)

最终效果是一样的，从断点中可以看出我们执行构建的参数是build apk，如图所示

![direct_run_breakpoint.png](direct_run_breakpoint.png)

#### 修改源码调试

除了断点调试外，有时候我们可能需要修改一下flutter tools的代码，加入一些日志等，这时候你会发现执行构建后修改的代码并不会生效。其实解决该问题很简单，我们只需要删除一个文件即可。

删除该文件

```
/path/to/flutter/bin/cache/flutter_tools.stamp
```

当我们运行flutter命令时候会去校验该文件，不存在的话就会重新构建/path/to/flutter/packages/flutter_tools代码生成flutter_tools.snapshot，从而让我们的改动生效。

删除该文件后，再重新执行flutter命令，便会看到重建flutter tools的日志输出，如图所示。

![build_tools.png](build_tools.png)

### Flutter App 调试

Flutter App的调试也有两种方式，第一种是直接以debug的方式运行，从而执行断点调试，这种方式比较简单，不过多说明。另一种方式是针对正在运行的App，直接attach debug进程进行调试。

首先我们需要先运行Flutter App，并进入Flutter界面，假如此时我们此时需要attach到该进程进行debug。首先我们需要获取到设备上Observatory的端口号，该端口最终会映射到PC上的某个端口号，我们需要找到PC上的该端口号，那么如何才能获取到该端口号呢？其中一种方式是运行flutter run的时候加入\-\-verbose参数，最终会输出日志，如下

```
15:49:23.667 1138 info flutter.tools [        ] Waiting for observatory port to be available...
15:49:42.327 1139 info flutter.tools Observatory URL on device: http://127.0.0.1:37649/
15:49:42.327 1140 info flutter.tools [+18661 ms] executing: /Users/lizhangqu/AndroidSDK/platform-tools/adb -s fc85f109 forward tcp:0 tcp:37649
15:49:42.350 1141 info flutter.tools [  +24 ms] 63899
15:49:42.350 1142 info flutter.tools Forwarded host port 63899 to device port 37649 for Observatory
15:49:42.358 1143 info flutter.tools [   +6 ms] Connecting to service protocol: http://127.0.0.1:63899/
15:49:42.558 1144 info flutter.tools [ +199 ms] Successfully connected to service protocol: http://127.0.0.1:63899/
```

此时，63899就是我们需要的那个端口号，然后使用Dart Remote Debug直接attach到该端口号上即可。

但是实际情况并非如此，一般我们已经运行了该App，并且也没有使用verbose参数输出日志，那么要怎么获取该端口号呢?这里有一个投机的方式，就是使用adb forward命令查看端口转发映射关系

```
adb forward --list
```

这时候会输出一些端口映射

```
➜  ~ adb forward --list
fc85f109 tcp:64698 tcp:43007
fc85f109 tcp:64783 tcp:38903
fc85f109 tcp:65171 tcp:37303
fc85f109 tcp:8010 tcp:39345
fc85f109 tcp:49879 tcp:42331
fc85f109 tcp:50094 tcp:40259
fc85f109 tcp:50736 tcp:39359
fc85f109 tcp:55097 tcp:42149
fc85f109 tcp:63899 tcp:37649
➜  ~ 
```

一般情况下，最后一行就是我们需要找的端口号，左侧一列是设备标示符，中间一列是PC的端口号，右侧一列是手机设备的端口号，这里我们要的端口号就是最后一行的中间一列，即63899。

假如最后一个不是的话，那我们就一个一个从后往前试，总有一个会是的，只要能attach成功端口就是对的，或者直接在浏览器中直接打开该端口，比如 [http://127.0.0.1:63899](http://127.0.0.1:63899)。如果可以打开，并且内容如下所示，那么端口基本也是对的。

![browser.png](browser.png)

找到端口号后，使用Dart Remote Debug直接attach到该端口号上即可，Host保持不变还是使用127.0.0.1，最终只要能看到Connected就表示成功了，如图所示

![connected.png](connected.png)

### 总结

万变不离其宗，调试的方式总是相通的。