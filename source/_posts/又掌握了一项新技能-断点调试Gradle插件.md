title: 又掌握了一项新技能-断点调试Gradle插件
date: 2017-07-05 09:07:10
categories: [Android]
tags: [Android, Android Gradle Plugin, Debug]
---

### 前言

最初开发Android应用程序的时候，肯定是在打log调试，然后慢慢地觉得打log效率太低下了，不能快速定位问题，于是走上了断点调试之路。Gradle插件也一样，从会写插件那一刻起到现在，一直用的是打log调试功能，但是同样的这种方式效率也太低下了，这之前，我也尝试过寻找断点调试的方式，但是一直没有成功，昨天偶然之间调通了，于是记录一发。

<!-- more -->


### 之前失败的方式


之前测试断点调试的功能的时候，一直在build.gradle中直接测代码，测试的代码也是在project.afterEvaluate之后，然后遍历android..applicationVariants，获取各个信息，就像这样子

```
buildscript {
    repositories {
        jcenter()
    }
    dependencies {
        classpath 'com.android.tools.build:gradle:2.3.3'
    }
}

dependencies {
    compile gradleApi()
    compile localGroovy()
}

import com.android.build.gradle.api.TestVariant
import com.android.build.gradle.api.UnitTestVariant
import com.android.build.gradle.internal.variant.ApplicationVariantData
import com.android.build.gradle.internal.api.ApplicationVariantImpl

project.afterEvaluate {
    if (project.plugins.hasPlugin("com.android.application")) {
        def android = project.extensions.getByName("android")
        android.applicationVariants.all { ApplicationVariantImpl variant ->
            project.logger.error "DebuggerPlugin:${variant}"
            ApplicationVariantData apkVariantData = variant.getApkVariantData()
            ApplicationVariantData variantData = variant.getVariantData()
            TestVariant testVariant = variant.getTestVariant()
            UnitTestVariant unitTestVariant = variant.getUnitTestVariant()
        }
    }
}
```

于是这个断点我打了一年硬是没打住，恩，没错，这个东西我断断续续实验了一年也没有成功过，也有点无语，原因也不知道。昨日发现，必须得在外面包一层plugin才能打住断点，就像这样子

```

buildscript {
    repositories {
        jcenter()
    }
    dependencies {
        classpath 'com.android.tools.build:gradle:2.3.3'
    }
}

dependencies {
    compile gradleApi()
    compile localGroovy()
}


apply plugin: DebuggerPlugin

import com.android.build.gradle.api.TestVariant
import com.android.build.gradle.api.UnitTestVariant
import com.android.build.gradle.internal.variant.ApplicationVariantData
import com.android.build.gradle.internal.api.ApplicationVariantImpl

class DebuggerPlugin implements Plugin<Project> {
    void apply(Project project) {
        project.afterEvaluate {
            if (project.plugins.hasPlugin("com.android.application")) {
                def android = project.extensions.getByName("android")
                android.applicationVariants.all { ApplicationVariantImpl variant ->
                    project.logger.error "DebuggerPlugin:${variant}"
                    ApplicationVariantData apkVariantData = variant.getApkVariantData()
                    ApplicationVariantData variantData = variant.getVariantData()
                    TestVariant testVariant = variant.getTestVariant()
                    UnitTestVariant unitTestVariant = variant.getUnitTestVariant()
                }
            }
        }
    }
}

```

具体原因也找不到，理论上来讲，两者没有什么大的区别，除非不包plugin的代码编译后代码位置发生了变化，导致打不到断点。

其实这事也怪自己，如果一开始直接用插件项目来测，将其发布到本地maven，然后执行去打断点，估计老早就成功了，硬是在build.gradle中写零碎的代码来测试，往事不提也罢。

### 一个坑

以上代码执行过程会先出现一个错，如下：

```
Error:The closure 'DebuggerPlugin$_apply_closure1$_closure2@20825b3e' is not valid as an action for argument 'com.android.build.gradle.internal.api.ApplicationVariantImpl_Decorated@1103b69d'. It should accept no parameters, or one compatible with type 'com.android.build.gradle.internal.api.ApplicationVariantImpl_Decorated'. It accepts (com.android.build.gradle.internal.api.ApplicationVariantImpl).
```

这个错出现的时候，只需要将**ApplicationVariantImpl variant**改成**def variant**即可，然后继续运行，会出现另一个问题。

即出现了一个**cannot cast object with class A to A**的问题，如下

```
Error:Cannot cast object 'ApplicationVariantData{debug}' with class 'com.android.build.gradle.internal.variant.ApplicationVariantData' to class 'com.android.build.gradle.internal.variant.ApplicationVariantData'
```

可以看到虽然两个对象obj1和obj2的类的名字相同，但是这两个类是由不同的类加载器实例来加载的，因此不被虚拟机认为是相同的，所以抛出了ClassCastException异常。

那么怎么解决呢，将项目中所有buildscript中的dependencies下引用的android gradle plugin 版本都改成同一个，即

```
buildscript {
    repositories {
        jcenter()
    }
    dependencies {
        classpath "com.android.tools.build:gradle:${global_gradle_plugin_version}"
    }
}
```

之后将~/.gradle/daemon/目录下内容全部删除，然后看看是否解决了，如果没有解决，则继续删除~/.gradle/daemon/，然后重启电脑。TM的如果还没好，那么请确定项目中所有引用的插件中的compile的android gradle plugin版本是否都一致，如果不一致，请保持一致，不然也有问题。

这问题就算完事了，大概可能和Gradle的守护进程、插件引用的android gradle plugin版本不一致有那么一点关系。


### 断点调试方式1

说完了以上坑，正式进入断点调试的环节，方式一很简单，直接利用gradle的参数让其等待我们的调试进程attach上去。比如我要执行gradle clean这个task，则加上两个额外参数即可

 - 一个是开启debug
 - 一个是不使用守护进程

 具体例子如下：

 ```
 gradle :app:clean -Dorg.gradle.debug=true  --no-daemon

 ```

 之后这个进程就会一直等待，直到我们attach我们的调试进程。如下图所示：

 ![wait.png](wait.png)

然后参考这篇文章[Intellij-IDEA远程调试](/2017/04/07/Intellij-IDEA远程调试/)，利用Android Studio或者Intellij IDEA的remote debug进行调试，端口号填5005.

如图

![remote_config.png](remote_config.png)

然后运行remote

![start_debug.png](start_debug.png)

之后就会attach上去我们的进程

![attach_debug.png](attach_debug.png)

然后看看效果

![result.png](result.png)

从此可以愉快的断点调试了。

### 断点调试方式2

和方式一差不多，只不过不是用gradle的参数来开启debug，而是用环境变量

```
export GRADLE_OPTS="-Xdebug -Xrunjdwp:transport=dt_socket,server=y,suspend=y,address=5005" 
```

之后就跟正常执行任务一样

```
gradle clean
```

剩下的操作和方式1一样。