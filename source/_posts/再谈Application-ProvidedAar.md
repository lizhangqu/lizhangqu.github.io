title: 再谈Application ProvidedAar
date: 2018-03-19 12:12:02
categories: [Android]
tags: [gradle, android, providedAar, maven]
---

### 前言 

去年年底的时候，写过一篇博客叫[《Android-application中使用provided-aar并没有那么简单》](/2017/12/24/Android-application中使用provided-aar并没有那么简单/)。当时文章中介绍了android gradle plugin不同版本的实现方式，对android gradle plugin 2.2.0以下版本的实现，是采用使用gradle maven的api实现，利用gradle本地缓存，这种方式不但反射的地方非常多，而且不支持传递依赖，局限性非常大。周末有空，又重新拿起来研究了下，最终实现了android gradle plugin [1.3.0,3.2.0+)版本的传递依赖，在插件化中起着重要意义，几乎是全版本兼容了，通过源码发现使用相同的方式无法进行兼容1.3.0以下的版本，且版本过于久远，所以直接不支持了。建议阅读本篇博客前，强烈建议先将之前的那篇博客看一下，否则可能无法理解。没有特殊说明的情况下，下文将android gradle plugin简称为AGP。

<!-- more -->

### 回顾
providedAar的重要性就在于在com.android.application插件中我需要引用到对应的类或者资源，但是编译打包的时候我又不能将其打包进去，场景就在插件化中，一些公共类和资源定义在宿主中，插件中不能再次定义。除了providedAar这一种实现外，还有一种实现是干预编译过程，在编译期干掉对应的类和资源，典型的实现有VirtualApk和Small。


从之前那篇文章可以知道，之前对于AGP 2.2.0以下的版本，是使用gradle缓存在本地的aar，将classes.jar提取出来，添加到provided这个scope上，这种实现无法进行传递依赖，且添加的只有代码，没有资源。当时也说明了为什么不采用AGP 2.2.0以上的实现，原因如下：

2.2.0以下的版本，虽然也可以使用[2.2.0,2.5.0)这个区间的方法将异常进行消除，但是即使消除了，因为其代码的特殊性，导致即使是provided依赖的aar，最终也会被打包进apk中，这里以2.1.3的代码为例，如下:


```
//遍历过滤后剩余的编译期的依赖
for (LibInfo lib : compiledAndroidLibraries) {
    if (!copyOfPackagedLibs.contains(lib)) {
        if (isLibrary || lib.isOptional()) {
            //如果是com.android.library或者是可选的，则设置该lib为可选
            lib.setIsOptional(true);
        } else {
            //否则，也就是在com.android.application中，将这个问题记录了下来，后续的处理就在PrepareDependenciesTask执行的过程中报异常
            //noinspection ConstantConditions
            variantDeps.getChecker().addSyncIssue(extraModelInfo.handleSyncError(
                    lib.getResolvedCoordinates().toString(),
                    SyncIssue.TYPE_NON_JAR_PROVIDED_DEP,
                    String.format(
                            "Project %s: provided dependencies can only be jars. %s is an Android Library.",
                            project.getName(), lib.getResolvedCoordinates())));
        }
    } else {
        copyOfPackagedLibs.remove(lib);
    }
}
```

对比2.3.3版本的代码

```
//获得maven坐标
MavenCoordinates resolvedCoordinates = compileLib.getCoordinates();
//如果不是com.android.library，也不是com.android.atom，也不是用于测试的com.android.test，即是com.android.application
if (variantType != VariantType.LIBRARY
        && variantType != VariantType.ATOM
        && (testedVariantType != VariantType.LIBRARY || !variantType.isForTesting())) {
    //就会将这个异常记录下来，后续的处理就在PrepareDependenciesTask执行的过程中报异常
    handleIssue(
            resolvedCoordinates.toString(),
            SyncIssue.TYPE_NON_JAR_PROVIDED_DEP,
            SyncIssue.SEVERITY_ERROR,
            String.format(
                    "Project %s: Provided dependencies can only be jars. %s is an Android Library.",
                    projectName,
                    resolvedCoordinates.toString()));
}
```

从两个版本的代码中可以看出有一处不同，2.2.0以下的版本在com.android.library中会将lib设为可选，但是在com.android.application就会直接抛出异常，具体的区别代码如下:

```
if (isLibrary || lib.isOptional()) {
    //如果是com.android.library或者是可选的，则设置该lib为可选
    lib.setIsOptional(true);
} else {
   //抛异常
}
```

一旦将lib设置为可选，后续就不会打包进apk，那么我们能不能将其设置为可选从而不将其打包进去呢，当时给的答案是不能，但是周末研究的时候，发现从PrepareDependenciesTask这个task入手，是可以拿到对应的lib，将其设置为可选的。那么具体实现流程是怎么样的呢？

### 实现

通过查看PrepareDependenciesTask这个类，发现其成员变量checkers(类型是DependencyChecker List)中每一项DependencyChecker持有了VariantDependencies变量，而VariantDependencies这个类中可以拿到当前项目依赖的所有library，该值被存储在libraries中，具体类型是LibraryDependencyImpl List，而LibraryDependencyImpl中有个isOptional的变量，只要将其设为true，就不会被打包进apk了，除此之外，LibraryDependencyImpl中还有一个dependencies变量(类型是LibraryDependency List) ，里面存储对应依赖的传递依赖，因此处理时需要递归处理dependencies变量，将传递依赖的isOptional也设为true，值得特别注意的是isOptional这个变量是final的，在反射调用的时候，要特殊处理一下。

因此只要将2.2.0以下的版本特殊处理一下就可以了，详细代码如下：

```
try {
    Class prepareDependenciesTaskClass = Class.forName("com.android.build.gradle.internal.tasks.PrepareDependenciesTask")
    Field checkersField = prepareDependenciesTaskClass.getDeclaredField('checkers')
    checkersField.setAccessible(true)
    def checkers = checkersField.get(prepareDependenciesTask)
    checkers.iterator().with { checkersIterator ->
        checkersIterator.each { dependencyChecker ->
            def syncIssues = dependencyChecker.syncIssues
            syncIssues.iterator().with { syncIssuesIterator ->
                syncIssuesIterator.each { syncIssue ->
                    if (syncIssue.getType() == 7 && syncIssue.getSeverity() == 2) {
                        project.logger.info "[providedAar] WARNING: providedAar has been enabled in com.android.application you can ignore ${syncIssue}"
                        syncIssuesIterator.remove()
                    }
                }
            }

            //兼容1.3.0~2.1.3版本，为了将provided的aar不参与打包，将isOptional设为true
            if (androidGradlePluginVersion.startsWith("1.3") || androidGradlePluginVersion.startsWith("1.5") || androidGradlePluginVersion.startsWith("2.0") || androidGradlePluginVersion.startsWith("2.1")) {
                def configurationDependencies = dependencyChecker.configurationDependencies
                List libraries = configurationDependencies.libraries
                libraries.each { library ->
                    providedAarConfiguration.dependencies.each { providedDependency ->
                        String libName = library.getName()
                        if (libName.contains(providedDependency.group) && libName.contains(providedDependency.name) && libName.contains(providedDependency.version)) {
                            //final字段
                            Field isOptionalField = library.getClass().getDeclaredField("isOptional")
                            //final类型的修改，先修改modifiers
                            Field modifiersField = Field.class.getDeclaredField("modifiers")
                            modifiersField.setAccessible(true)
                            //去final
                            modifiersField.setInt(isOptionalField, isOptionalField.getModifiers() & ~java.lang.reflect.Modifier.FINAL)
                            isOptionalField.setAccessible(true)
                            //将isOptional设为true
                            isOptionalField.setBoolean(library, true)
                            //为了递归调用可以引用，先声明再赋值
                            def fixDependencies = null
                            fixDependencies = { dependencies ->
                                dependencies.each { dependency ->
                                    if (dependency.getClass() == library.getClass()) {
                                        isOptionalField.setBoolean(dependency, true)
                                        //递归dependencies
                                        fixDependencies(dependency.dependencies)
                                    }
                                }
                            }
                            fixDependencies(library.dependencies)
                        }
                    }
                }
            }
        }
    }
} catch (Exception e) {
    e.printStackTrace()
}

prepareDependenciesTask.configure removeSyncIssues
```

修改完成后简单测试一下，发现成功了，providedAar依赖最终并没有被打入apk中。但是别高兴得太早。成功是在命令行测试可行，但是一旦你点击Android Studio上的sync按钮，你会发现还是会出现那个异常

```
Provided dependencies can only be jars
```

问题出在哪呢，其实Android Studio在构建的时候，会向AGP注入它的一些实现，导致命令行的实现和Android Studio里点击按钮编译是不一样的。那么这个问题怎么解决呢，也很简单，在调用prepareDependenciesTask.configure removeSyncIssues前对2.2.0以下版本做下特殊处理就可以了。

那么要对什么进行处理呢，在BasePlugin中有个taskManager对象，其类型是TaskManager；taskManager中有个叫dependencyManager的对象，其类型是DependencyManager；dependencyManager中有个extraModelInfo，其类型是ExtraModelInfo，这个类的handleSyncIssue函数，会根据当前注入的类型，做不同处理，具体代码如下:

```
@Override
@NonNull
protected SyncIssue handleSyncIssue(
        @Nullable String data,
        int type,
        int severity,
        @NonNull String msg) {
    SyncIssue issue;
    switch (getMode()) {
        case STANDARD:
            if (severity != SyncIssue.SEVERITY_WARNING && !isDependencyIssue(type)) {
                throw new GradleException(msg);
            }
            // if it's a dependency issue we don't throw right away. we'll
            // throw during build instead.
            // but we do log.
            project.getLogger().warn("WARNING: " + msg);
            issue = new SyncIssueImpl(type, severity, data, msg);
            break;
        case IDE_LEGACY:
            // compat mode for the only issue supported before the addition of SyncIssue
            // in the model.
            if (severity != SyncIssue.SEVERITY_WARNING
                    && type != SyncIssue.TYPE_UNRESOLVED_DEPENDENCY) {
                throw new GradleException(msg);
            }
            // intended fall-through
        case IDE:
            // new IDE, able to support SyncIssue.
            issue = new SyncIssueImpl(type, severity, data, msg);
            syncIssues.put(SyncIssueKey.from(issue), issue);
            break;
        default:
            throw new RuntimeException("Unknown SyncIssue type");
    }

    return issue;
}
```

对应命令行调用，它会直接输出日志，对于Android Studio注入的类型，它会抛异常或者记录下来后续由Android Studio报告异常，即后续sync失败的提示内容。这里走的逻辑是存入syncIssues中，后续由Android Studio报告问题。

那么问题就变得很简单了，反射将syncIssues（Map<SyncIssueKey, SyncIssue>对象）中类型是7（Provided dependencies can only be jars），错误级别是2的问题remove掉就好了。具体实现如下：

```
if (androidGradlePluginVersion.startsWith("1.3") || androidGradlePluginVersion.startsWith("1.5") || androidGradlePluginVersion.startsWith("2.0") || androidGradlePluginVersion.startsWith("2.1")) {
    //这里不处理as sync的时候会出错
    //获取AppPlugin
    def appPlugin = project.getPlugins().findPlugin("com.android.application")
    //获取TaskManager
    def taskManager = appPlugin.getMetaClass().getProperty(appPlugin, "taskManager")
    //获取DependencyManager，注意调用getSuperclass()，否则无法找到字段
    def dependencyManager = taskManager.getClass().getSuperclass().getMetaClass().getProperty(taskManager, "dependencyManager")
    //获取ExtraModelInfo
    def extraModelInfo = dependencyManager.getMetaClass().getProperty(dependencyManager, "extraModelInfo")
    //获取syncIssues，类型是Map<SyncIssueKey, SyncIssue>，只要遍历这个map，将value中type=7&severity=2的项移除即可
    Map<?, ?> syncIssues = extraModelInfo.getSyncIssues()
    //groovy迭代器遍历
    syncIssues.iterator().with { syncIssuesIterator ->
        syncIssuesIterator.each { syncIssuePair ->
            if (syncIssuePair.getValue().getType() == 7 && syncIssuePair.getValue().getSeverity() == 2) {
                syncIssuesIterator.remove()
            }
        }
    }
    //下面同2.2.0+处理
    prepareDependenciesTask.configure removeSyncIssues
}
```

修改完成后再次点击Android Studio中sync按钮，发现不再报错了，再次测试，发现一切都正常。

代码的具体修改可以参见这个提交 [支持到android gradle plugin 1.3.0传递依赖](https://github.com/lizhangqu/AndroidGradlePluginCompat/commit/3e8cfaa643817c4efb82ff731a21bbff6e9a8d67)

### 总结

   时隔3个多月，再次深入研究，收获颇多。完美解决了AGP 1.3.0+ 的providedAar功能，并支持传递依赖。

