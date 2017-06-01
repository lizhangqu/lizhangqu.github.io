title: Android Gradle Plugin源码阅读与编译
date: 2017-06-01 11:09:21
categories: [Gradle]
tags: [Android, Gradle, Instant Run, AOSP]
---

### 前言

为了解一些Andorid的构建流程，有时候需要阅读Android Gradle Plugin的相关源码的。自己阅读Android Gradle Plugin源码主要经历了三个时期：
   
   - 1、AOSP上打包源码压缩包，然后下载下来看
   - 2、通过依赖相关库，结合IntelliJ IDEA的快捷键：Command+左键、Alt+Command+F7 跟踪源码调用来看
   - 3、repo下载AOSP构建工具分支上的源码，完整项目导入IntelliJ IDEA看

<!-- more -->


### 方式1：AOSP上打包源码为压缩包

AOSP上打了tag的版本，貌似只有整数的大版本，没有小版本，即只有2.3.0、2.2.0、2.0.0、1.5.0等，没有2.3.2等版本，需要注意。

 - [gradle_2.3.0 源码](https://android.googlesource.com/platform/tools/base/+/gradle_2.3.0/build-system/)
 - [gradle_2.2.0 源码](https://android.googlesource.com/platform/tools/base/+/gradle_2.2.0/build-system/)
 - [gradle_2.0.0 源码](https://android.googlesource.com/platform/tools/base/+/gradle_2.0.0/build-system/)
 - [gradle_1.5.0 源码](https://android.googlesource.com/platform/tools/base/+/gradle_1.5.0/build-system/)
 - [gradle_1.2.0 源码](https://android.googlesource.com/platform/tools/base/+/gradle_1.2.0/build-system/)
 - [gradle_1.1.0 源码](https://android.googlesource.com/platform/tools/base/+/gradle_1.1.0/build-system/)
 - [gradle_1.0.0 源码](https://android.googlesource.com/platform/tools/base/+/gradle_1.0.0/build-system/)

 打开上面自己需要的一个版本的链接，点击页面上的tgz链接，然后就会下载下来一个压缩包，解压此压缩包，然后导入Android Studio或者IntelliJ IDEA，即可查看。

 但是有缺陷，导入项目后由于缺少了很大一部分依赖，导致项目大片爆红，加上没有相关的项目间依赖关系，绝大部分代码无法进行跳转，需要自己手动搜索代码，找到代码调用处，极其痛苦，所以，不建议使用此方法阅读源码，后期，自己也不再通过此方法查看源码了，太蛋疼。

### 方式2：通过依赖相关库查看源码

 这种方式比较轻量，建议初学者通过此方式学习，这种方式很简单，只需要建立一个空的Gradle项目，在其依赖中加入两行依赖，如我要查看gradle2.3.2的源码只需要加入依赖

```
compile gradleApi()
compile 'com.android.tools.build:gradle:2.3.2'
```

值得注意的是，可能并不是所有的android gradle plugin版本都附带有源码的jar，如果遇到了一些没有源码的，即打开后看到的内容是反编译的class或者是没有javadoc的内容，你最好换一个版本。

我建了一个简单的示例项目[https://github.com/lizhangqu/AndroidGradlePluginCodeViewer](https://github.com/lizhangqu/AndroidGradlePluginCodeViewer)，使用IntelliJ IDEA导入即可，如图

![gradle_dep.png](gradle_dep.png)

![gradle_src.png](gradle_src.png)


之后，结合Command+左键或者Alt+Command+F7就可以找到源码对应的调用处，跟踪查看了。

### 方式3：repo下载AOSP完整gradle源码

如果你有编译Android Gradle Plugin的需求，可以用此方法。当然缺点很明显，项目十分巨大，需要占用大量的硬盘资源，如果硬盘资源不足，建议还是不要尝试了，举个例子：gradle_2.3.0分支上的代码，大概释放后有30G左右。

```
$ mkdir gradle_2.3.0
$ cd gradle_2.3.0
$ repo init -u https://android.googlesource.com/platform/manifest -b gradle_2.3.0
$ repo sync
```

源码同步时间较长，大概需要1-3小时，耐心等待。

国内墙可能太高，可以使用中国科学技术大学的AOSP源或者清华大学的AOSP源

 - [清华大学的AOSP源](https://mirrors.tuna.tsinghua.edu.cn/help/AOSP/)
 - [中国科学技术大学的AOSP源](https://lug.ustc.edu.cn/wiki/mirrors/help/aosp)

如果repo init 提示无法连接到 gerrit.googlesource.com，查看对应的源解决方法页面进行解决

 - [清华大学 Git Repo 镜像使用帮助](https://mirrors.tuna.tsinghua.edu.cn/help/git-repo/)
 - [中国科学技术大学 附录_brillo](https://lug.ustc.edu.cn/wiki/mirrors/help/aosp#附录_brillo)

 同步完成后，进入gradle_2.3.0/tools目录，用gradlew执行一些构建前的初始化工作

```
$ cd tools
$ ./gradlew init
```

之后用IntelliJ IDEA打开tools/base目录即可查看，该目录下有一个.idea目录，已经是IntelliJ IDEA项目了，直接打开即可

导入过程比较漫长，耐心等待。导入过程会提示是否导入成gradle项目，如图，点击Import Gradle Project即可

![gradle_import.png](gradle_import.png)

然后勾选use gradle wrapper

![gradle_wrapper.png](gradle_wrapper.png)

导入完成后，大概就长这样子，gradle plugin的源码在tools/base/build-system下

![gradle_project.png](gradle_project.png)

假设当前目录为gradle_2.3.0/tools目录，进行android gradle plugin的编译

```
./gradlew :base:profile:assemble
./gradlew :base:builder-model:assemble
./gradlew :base:builder-test-api:assemble
./gradlew :base:builder:assemble
./gradlew :base:transform-api:assemble
./gradlew :base:gradle-api:assemble
./gradlew :base:gradle-core:assemble
./gradlew :base:instant-run-instrumentation:assemble
./gradlew :base:gradle:assemble
./gradlew :base:gradle-experimental:assemble
./gradlew :base:integration-test:assemble
./gradlew :base:project-test-lib:assemble
./gradlew :base:project-test:assemble
```

编译产物位于gradle_2.3.0/out/build目录下

假设当前目录为gradle_2.3.0/tools目录，将android gradle plugin部署到本地

```
./gradlew :base:profile:publishLocal
./gradlew :base:builder-model:publishLocal
./gradlew :base:builder-test-api:publishLocal
./gradlew :base:builder:publishLocal
./gradlew :base:transform-api:publishLocal
./gradlew :base:gradle-api:publishLocal
./gradlew :base:gradle-core:publishLocal
./gradlew :base:instant-run-instrumentation:publishLocal
./gradlew :base:gradle:publishLocal
./gradlew :base:gradle-experimental:publishLocal
./gradlew :base:integration-test:publishLocal
./gradlew :base:project-test-lib:publishLocal
./gradlew :base:project-test:publishLocal
```

部署产物位于gradle_2.3.0/out/repo目录下

那么如何将我们项目中的gradle插件替换为使用构建好的插件呢

假设现有项目中的依赖是这样的

```
buildscript {
    repositories {
        mavenCentral()
    }
    dependencies {
        classpath 'com.android.tools.build:gradle:2.3.0'
    }
}
```

需要将其指定到本地的部署产物所在repo

```
buildscript {
    repositories {
        maven { url 'path/to/gradle_2.3.0/out/repo' }
    }
    dependencies {
        classpath 'com.android.tools.build:gradle:2.3.0'
    }
}
```

### 对比总结

  - 方式1，缺点明显，大片爆红，不能良好的进行代码跳转
  - 方式2，优点是占用资源少，快速，方便，因此优先推荐此方式，缺点是只能阅读，不能编译、debug了解其整个详细过程
  - 方式3，优点是可以进行编译、debug等操作，缺点很明显，硬盘资源占用过大，没有30G的空余空间，不适合尝试，尤其是对Mac用户来说，SSD可能过小，没有这么大的空间。源码同步时间较长，需要耗费1-3个小时。

因此，对于初学者来说，方式2为最优选择。

### 题外话：instant run源码编译及部署

既然都讲到了android gradle plugin的编译，而instant run源码刚好也在tools/base下，顺带就讲讲instant run的编译

假设当前目录为gradle_2.3.0/tools目录

编译

```
./gradlew :base:instant-run:instant-run-annotations:assemble
./gradlew :base:instant-run:instant-run-common:assemble
./gradlew :base:instant-run:instant-run-client:assemble
./gradlew :base:instant-run:instant-run-runtime:assemble
./gradlew :base:instant-run:instant-run-server:assemble
```

部署

```
./gradlew :base:instant-run:instant-run-annotations:publishLocal
./gradlew :base:instant-run:instant-run-common:publishLocal
./gradlew :base:instant-run:instant-run-client:publishLocal
./gradlew :base:instant-run:instant-run-runtime:publishLocal
./gradlew :base:instant-run:instant-run-server:publishLocal
```


### 参考链接

 - [http://tools.android.com/build/gradleplugin](http://tools.android.com/build/gradleplugin)
 - [http://tools.android.com/build](http://tools.android.com/build)
 - [http://source.android.com/source/downloading.html](http://source.android.com/source/downloading.html)
 - [https://mirrors.tuna.tsinghua.edu.cn/help/AOSP/](https://mirrors.tuna.tsinghua.edu.cn/help/AOSP/)
 - [https://lug.ustc.edu.cn/wiki/mirrors/help/aosp](https://lug.ustc.edu.cn/wiki/mirrors/help/aosp)

