title: Gradle函数复用的一点实践
date: 2017-01-12 17:05:29
categories: [Gradle]
tags: [Android, Gradle]
---

>阅读本篇文章需要1~2分钟，没有技术含量，只是谈谈经验。

前段时间在搞组件化，其中遇到一个问题，各个模块中的gradle文件需要一些辅助函数，比如用于判断当前构建的任务是否在jenkins上构建，并且这些函数可能会被多次使用。最开始的时候只有一个gradle文件用到了，就直接在用到的gradle文件中编写对应的函数。后来发现，很多gradle文件都会用到，一开始并没有考虑太多，用到的时候就copy一下对应的函数，久而久之，发现很多文件中存在着相同的函数，十分不好维护，由于现有的方法实在是太蠢了以至于自己都看不下去了，于是不得不去解决这个问题。

那么在gradle中，有没有一种方法让公共函数复用呢？答案是肯定的，如果没有的话也就没有此文了。

我们回想一下，我们如何将lib库发布到maven私服，一般会有以下几个步骤：

  1. 应用maven插件
  2. 定义lib库坐标
  3. 利用uploadArchives这个Task发布到maven私服

最简单的代码如下，将lib库发布到了本地的一个目录下。

```
apply plugin: 'maven'
ext {
    PUBLISH_GROUP_ID = "com.fucknmb"
    PUBLISH_ARTIFACT_ID = "test"
    PUBLISH_VERSION = "0.0.1"
}
uploadArchives {
    repositories {
        mavenDeployer {
            pom.groupId = PUBLISH_GROUP_ID
            pom.artifactId = PUBLISH_ARTIFACT_ID
            pom.version = PUBLISH_VERSION
            repository(url: uri('../repo'))
        }
    }
}
```

可以看到，我们会将groupId,artifactId以及version定义到project.ext中，然后直接通过变量名来访问对应的值，这样做的好处就是便于统一管理各个变量。其实这是变量复用的一种体现，既然变量可以如此复用，那么是否可以参考变量复用的方式，来复用函数呢？

假设现在我们现在需要判断当前的构建环境是否在jenkins上，一般需要通过环境变量来判断是否存在JOB_NAME和BUILD_NUMBER两个变量，这时候就会有如下函数：

```
/**
 * 是否在Jenkins平台上打包
 * @return
 */
boolean isJenkins() {
    Map<String, String> map = System.getenv()
    if (map == null){
    	return false
    }
    boolean hasBuildJob = map.containsKey("JOB_NAME")
    boolean hasBuildNumber = map.containsKey("BUILD_NUMBER")
    if (hasBuildJob && hasBuildNumber) {
        return true
    }
    return false
}
```

这时候A模块可能需要用到这个函数，于是毫不犹豫的把这个函数拷贝到了A模块下的build.gradle文件中，OK完事。

过了一段时间，B模块过来问，有没有一个函数可以判断是否在Jenkins上，OK，有，又拷了一次这个函数。

久而久之，这种相同的基础函数，会散落在各个gradle文件中，非常不利于维护，后期要修改，可能会出现改了这个文件，忘了那个文件的情况。于是，必须要寻找出一个方法来复用这些函数。参考变量复用，我们在ext中定义函数。

新建一个common_function.gradle文件，用于复用这些函数。目前为止，这个文件中暂时还只有isJenkins这个函数。除此之外，我们要做的就是把这个函数导出。导出方式也很简单：

```
//导出函数
ext {
    isJenkins = this.&isJenkins
}
```

怎么样，是不是有点js中的ES6中的export的感觉。注意导出的时候需要加上&，有点像C++中的取地址。整个文件现在是这样的：


```
/**
 * 是否在Jenkins平台上打包
 * @return
 */
boolean isJenkins() {
    Map<String, String> map = System.getenv()
    if (map == null){
    	return false
    }
    boolean hasBuildJob = map.containsKey("JOB_NAME")
    boolean hasBuildNumber = map.containsKey("BUILD_NUMBER")
    if (hasBuildJob && hasBuildNumber) {
        return true
    }
    return false
}
//导出函数
ext {
    isJenkins = this.&isJenkins
}
```

目前为止，公共函数的定义以及导出已经完成了，接下来要做的就是引用了。引用就和应用插件是一样的。直接应用该common_function.gradle文件即可。

```
//公共函数
apply from: "${project.rootProject.file('common_function.gradle')}"
```

之后，你就可以在对应引用了common_function.gradle的文件中，随意使用isJenkins函数了。


打个比方，有个最简单的场景，比如热修复可能要记录一些文件，但是记录的的同时可能会降低编译速度，而在本地打包的时候又恰恰不需要，于是本地打包的时候就不需要应用该插件。改造后的脚本如下：

```
apply plugin: 'com.android.application'

//hotpatch配置，只有在打包平台上时才应用
if (isJenkins()) {
    apply plugin: "com.fucknmb.tinker"
    tinker {
        //...一系列的配置项
    }
}
```

本篇文章虽然没有什么，但是掌握了的话，对gradle代码的可维护性是可以大大提高。