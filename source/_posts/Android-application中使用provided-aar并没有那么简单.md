title: Android application中使用provided aar并没有那么简单
date: 2017-12-24 14:55:16
categories: [Android]
tags: [gradle, android, providedAar, maven]
---

### 前言 

首先简单讲一下这个需求的背景，大部分场景下，是没有这个需求的，这个需求出现在插件化中，当一个android插件引用aar中的类的时候，并且这个插件是使用com.android.application 这个gradle插件进行打包的，但是这个类已经在宿主中或者其他插件中，其实就没有必要将这个重复类打包到插件中，因此只需要进行引用，不需要打包到插件中。引用是其中一个目的，保证混淆的正确性则是另一个目的。寻找这个需求的解决方案的过程中，发现这个问题其实并没有想象中的那么好解决，会遇到许许多多的细节问题。

<!-- more -->

### Atlas的解决方案

atlas的插件并没有使用com.android.application进行编译，而是使用com.android.library进行编译，然后发布maven中的也只是aar(awb)，真正编译插件的时机是在宿主中，使用bundleCompile引用插件aar，在编译宿主的过程中会执行插件编译，然后将编译好的插件放入动态库armeabi目录，而在com.android.library中使用provided aar是完全可以的，于是atlas也就没有了在com.android.application中使用provided aar的需求，完全不存在这个问题。但是假设我们的插件在集成到宿主中前就已经编译好了，因此就需要使用com.android.application进行编译，对于一些宿主中或其他插件中存在的重复类，就必然需要使用到provided的功能，对于jar来说，没有问题，正常使用即可，但是对于aar来说，android gradle plugin肯定会爆出一个问题，该问题如下

```
Provided dependencies can only be jars.
```

因此必须寻找一个在com.android.application中使用provided aar的方法。

### 方法一：自定义Configuration

使用自定义的Configuration，然后将provided这个Configuration继承我们自定义的Configuration，这个方法理所当然的会最先被想到。

首先创建一个自定义的Configuration对象providedAar，然后将providedAar中的所有依赖解析出来，将解析出来的文件进行判断处理，如果是aar，则提取classes.jar，如果是jar，则直接使用，然后添加到provided的scope上。这样就完成了，代码如下：

```
@Override
void apply(Project project) {
    //创建自定义的configuration，且进行传递依赖，SNAPSHOT版本立即更新
    Configuration configuration = project.getConfigurations().create("providedAar") {
        //进行传递依赖
        it.setTransitive(true)
        it.resolutionStrategy {
            //SNAPSHOT版本更新时间为0s
            cacheChangingModulesFor(0, 'seconds')
            //动态版本更新实际为5分钟
            cacheDynamicVersionsFor(5, 'minutes')
        }
    }
    //遍历解析出来的所有依赖
    configuration.incoming.dependencies.all {
        //过滤收集aar和jar
        FileCollection collection = configuration.fileCollection(it).filter {
            return it.name.endsWith(".aar") || it.name.endsWith(".jar")
        }
        //遍历过滤后的文件
        collection.each {
            if (it.name.endsWith(".aar")) {
                //如果是aar，则提取里面的jar文件
                FileCollection jarFormAar = project.zipTree(it).filter {
                    it.name == "classes.jar"
                }
                //将jar依赖添加到provided的scope中
                project.dependencies.add("provided", jarFormAar)
            } else if (it.name.endsWith(".jar")) {
                //如果是jar则直接添加
                //将jar依赖添加到provided的scope中
                project.dependencies.add("provided", project.files(it))
            }
        }
    }
}
```

这里需要注意，如果要添加provided依赖的jar文件，只需要调用project.dependencies.add("provided", FileCollection fileCollection)方法进行添加即可。

其实上面的代码忽视了一个十分重要的问题，即完全无视了gradle的生命周期。依赖对应的文件类型FileCollection，只有依赖被解析之后才能拿到，即在afterResolve回调之后才能拿到，而afterResolve之后如果再对dependencies对象继续修改，必然会抛出一个异常

```
Cannot change dependencies of configuration ':app:providedAar' after it has been resolved
```

所以这段代码思路是行不通的，会存在一个循环依赖的问题，添加依赖前无法获取依赖文件，获取到依赖文件后，无法添加到provided scope依赖中去。这就是这种方法行不通的根本原因。

### 方法二：实现maven下载协议

参考这篇文章 [如何在Android Application里provided-aar](https://mp.weixin.qq.com/s/f8BUMXImp7bCLP04_yjQ2Q)，解决的思路是在beforeResolve中添加依赖，但是在beforeResolve是拿不到依赖对应的文件FileCollection对象的，于是这个方法最大的问题变成了如何获取依赖文件。这个文件获取如果要做的完美，其实是很复杂的，涉及到整个依赖树的有向图构建，版本冲突解决，以及传递依赖的递归问题。

首先来了解一下maven下载的最简单的逻辑。

对于release版本的依赖，其实很简单，拼接依赖的path路径即可，路径格式为

```
/$groupId[0]/../${groupId[n]/$artifactId/$version/$artifactId-$version.$extension
```

假设依赖为io.github.lizhangqu:test:1.0.0，则pom文件对应的依赖path路径以及pom文件对应的md5和sha1文件路径为

```
/io/github/lizhangqu/test/1.0.0/test-1.0.0.pom
/io/github/lizhangqu/test/1.0.0/test-1.0.0.pom.md5
/io/github/lizhangqu/test/1.0.0/test-1.0.0.pom.sha1
```

根据这个路径获取到pom文件中的内容，读取pom.xml中的packaging的值，假设pom.xml文件内容为

```
<?xml version="1.0" encoding="UTF-8"?>
<project xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd" xmlns="http://maven.apache.org/POM/4.0.0"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <modelVersion>4.0.0</modelVersion>
  <groupId>io.github.lizhangqu</groupId>
  <artifactId>test</artifactId>
  <version>1.0.0</version>
  <packaging>aar</packaging>
</project>

```

从上述内容很容易得到这里packaging的值为aar，则对应的文件以及该文件对应的md5和sha1文件路径为

```
/io/github/lizhangqu/test/1.0.0/test-1.0.0.aar
/io/github/lizhangqu/test/1.0.0/test-1.0.0.aar.md5
/io/github/lizhangqu/test/1.0.0/test-1.0.0.aar.sha1
```

如果该依赖存在classifier，则路径更复杂，比如javadoc和sources，其路径格式会变成

```
/$groupId[0]/../$groupId[n]/$artifactId/$version/$artifactId-$version-$classifier.$extension
```

上述依赖的classifier路径及classifier文件对应的md5和sha1文件的路径则是

```
/io/github/lizhangqu/test/1.0.0/test-1.0.0-javadoc.jar
/io/github/lizhangqu/test/1.0.0/test-1.0.0-javadoc.jar.md5
/io/github/lizhangqu/test/1.0.0/test-1.0.0-javadoc.jar.sha1
/io/github/lizhangqu/test/1.0.0/test-1.0.0-sources.jar
/io/github/lizhangqu/test/1.0.0/test-1.0.0-sources.jar.md5
/io/github/lizhangqu/test/1.0.0/test-1.0.0-sources.jar.sha1
```

如果classifier不是jar文件，则gradle中必须强制手动指定extension，否则会提示找不到对应的classifier文件。假设classifier为so文件，则需要强制指定为

```
io.github.lizhangqu:test:1.0.0:javadoc@so
io.github.lizhangqu:test:1.0.0:sources@so
```

而对于SNAPSHOT版本，就比较复杂了，假设依赖为io.github.lizhangqu:test:1.0.0-SNAPSHOT，则我们需要获取该版本的maven-metadata.xml文件，对应的path路径及其md5和sha1值的文件路径为

```
/io/github/lizhangqu/test/1.0.0-SNAPSHOT/maven-metadata.xml
/io/github/lizhangqu/test/1.0.0-SNAPSHOT/maven-metadata.xml.md5
/io/github/lizhangqu/test/1.0.0-SNAPSHOT/maven-metadata.xml.sha1
```

假设这个文件内容如下

```
<metadata>
  <groupId>io.github.lizhangqu</groupId>
  <artifactId>test</artifactId>
  <version>1.0.0-SNAPSHOT</version>
  <versioning>
    <snapshot>
      <timestamp>20171222.013814</timestamp>
      <buildNumber>200</buildNumber>
    </snapshot>
    <lastUpdated>20171222013814</lastUpdated>
  </versioning>
</metadata>
```

从该文件中看出当前1.0.0-SNAPSHOT的信息是这个artifact发布了200次，最新发布的时间是20171222.013814，拼接这两个值，得到20171222.013814-200，于是就获得了该依赖版本的最新快照的path路径以及md5和sha1文件路径

```
/io/github/lizhangqu/test/1.0.0-SNAPSHOT/test-1.0.0-20171222.013814-200.pom
/io/github/lizhangqu/test/1.0.0-SNAPSHOT/test-1.0.0-20171222.013814-200.pom.md5
/io/github/lizhangqu/test/1.0.0-SNAPSHOT/test-1.0.0-20171222.013814-200.pom.sha1
```

假设这个pom.xml文件中的内容如下

```
<?xml version="1.0" encoding="UTF-8"?>
<project xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd" xmlns="http://maven.apache.org/POM/4.0.0"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <modelVersion>4.0.0</modelVersion>
  <groupId>io.github.lizhangqu</groupId>
  <artifactId>test</artifactId>
  <version>1.0.0-SNAPSHOT</version>
  <packaging>aar</packaging>
</project>
```

从pom.xml中可以看到packaging为aar，则对应的文件的路径及该文件的md5和sha1文件路径为

```
/io/github/lizhangqu/test/1.0.0-SNAPSHOT/test-1.0.0-20171222.013814-200.aar
/io/github/lizhangqu/test/1.0.0-SNAPSHOT/test-1.0.0-20171222.013814-200.aar.md5
/io/github/lizhangqu/test/1.0.0-SNAPSHOT/test-1.0.0-20171222.013814-200.aar.sha1
```

之后的处理就和release版本是一样的。

依赖部分的path知道了，那么还需要知道maven服务所在地址，可通过gradle直接拿到

```
project.getGradle().addListener(new DependencyResolutionListener() {
    @Override
    void beforeResolve(ResolvableDependencies dependencies) {
      //此回调会多次进入，我们只需要解析一次，因此只要进入，就remove，然后执行我们的解析操作
      roject.gradle.removeListener(this)
      project.getRepositories().each { def repository ->
          //repository.url就是maven服务的前缀路径，可能是文件协议，也可能是http协议，或是其他协议，如ftp
      }
    }

    @Override
    void afterResolve(ResolvableDependencies resolvableDependencies) {

    }
})

```

拼接最终的地址，如下

```
#[]内的内容为可选
$repository.url/$groupId[0]/../$groupId[n]/$artifactId/$version/$artifactId-$version[-$classifier].$extension
```

上述只是简单的讲了下下载的逻辑。文件是如何缓存的，如何更新本地的SNAPSHOT版本，如何将本地信息与远程信息进行合并，以及传递依赖是如何处理的都没有讲到，实际情况要比这个远远复杂的多。

就拿缓存路径来说，对于mavenLocal，其本地文件缓存的路径是最简单的，为

```
#[]内的内容为可选
~/.m2/repository/$groupId[0]/../$groupId[n]/$artifactId/$version/$artifactId-$version[-$classifier].$extension
```

而gradle的缓存目录十分复杂，由gradle自己处理，且各个版本路径可能会有差异，大致位于

```
#[]内的内容为可选
~/.gradle/caches/modules-2/files-2.1/$groupId/$artifactId/$version/$sha1Value/$artifactId-$version[-$classifier].$extension
```

其中sha1Value的值为\$artifactId-\$version[-\$classifier].\$extension文件对应的sha1值

gradle的缓存策略可以见文档 [gradle caching](https://github.com/gradle/gradle-talks/blob/master/talks/dependency-resolution/src/slides/04-caching.md)

gradle各个版本元数据的缓存目录如下

```
public LocallyAvailableResourceFinder<ModuleComponentArtifactMetadata> create() {
    List<LocallyAvailableResourceFinder<ModuleComponentArtifactMetadata>> finders = new LinkedList<LocallyAvailableResourceFinder<ModuleComponentArtifactMetadata>>();

    // Order is important here, because they will be searched in that order

    // The current filestore
    finders.add(new LocallyAvailableResourceFinderSearchableFileStoreAdapter<ModuleComponentArtifactMetadata>(new FileStoreSearcher<ModuleComponentArtifactMetadata>() {
        @Override
        public Set<? extends LocallyAvailableResource> search(ModuleComponentArtifactMetadata key) {
            return fileStore.search(key.getId());
        }
    }));

    // 1.8
    addForPattern(finders, "artifacts-26/filestore/[organisation]/[module](/[branch])/[revision]/[type]/*/[artifact]-[revision](-[classifier])(.[ext])");

    // 1.5
    addForPattern(finders, "artifacts-24/filestore/[organisation]/[module](/[branch])/[revision]/[type]/*/[artifact]-[revision](-[classifier])(.[ext])");

    // 1.4
    addForPattern(finders, "artifacts-23/filestore/[organisation]/[module](/[branch])/[revision]/[type]/*/[artifact]-[revision](-[classifier])(.[ext])");

    // 1.3
    addForPattern(finders, "artifacts-15/filestore/[organisation]/[module](/[branch])/[revision]/[type]/*/[artifact]-[revision](-[classifier])(.[ext])");

    // 1.1, 1.2
    addForPattern(finders, "artifacts-14/filestore/[organisation]/[module](/[branch])/[revision]/[type]/*/[artifact]-[revision](-[classifier])(.[ext])");

    // rc-1, 1.0
    addForPattern(finders, "artifacts-13/filestore/[organisation]/[module](/[branch])/[revision]/[type]/*/[artifact]-[revision](-[classifier])(.[ext])");

    // Milestone 8 and 9
    addForPattern(finders, "artifacts-8/filestore/[organisation]/[module](/[branch])/[revision]/[type]/*/[artifact]-[revision](-[classifier])(.[ext])");

    // Milestone 7
    addForPattern(finders, "artifacts-7/artifacts/*/[organisation]/[module](/[branch])/[revision]/[type]/[artifact]-[revision](-[classifier])(.[ext])");

    // Milestone 6
    addForPattern(finders, "artifacts-4/[organisation]/[module](/[branch])/*/[type]s/[artifact]-[revision](-[classifier])(.[ext])");
    addForPattern(finders, "artifacts-4/[organisation]/[module](/[branch])/*/pom.originals/[artifact]-[revision](-[classifier])(.[ext])");

    // Milestone 3
    addForPattern(finders, "../cache/[organisation]/[module](/[branch])/[type]s/[artifact]-[revision](-[classifier])(.[ext])");

    // Maven local
    try {
        File localMavenRepository = localMavenRepositoryLocator.getLocalMavenRepository();
        if (localMavenRepository.exists()) {
            addForPattern(finders, localMavenRepository, new M2ResourcePattern("[organisation]/[module]/[revision]/[artifact]-[revision](-[classifier])(.[ext])"));
        }
    } catch (CannotLocateLocalMavenRepositoryException ex) {
        finders.add(new NoMavenLocalRepositoryResourceFinder(ex));
    }
    return new CompositeLocallyAvailableResourceFinder<ModuleComponentArtifactMetadata>(finders);
}
```

知道了这些后，我们可以自己去实现一套maven下载协议，但是还是十分复杂的，所以个人认为这没有必要，如果自己去实现，首先，不能复用gradle现有的缓存，其次自己下载的缓存，无法正常的与gradle缓存进行合并，虽然可以放到mavenLocal目录下，但是一些策略性的问题，不能考虑得十分周全，如SNAPSHOT版本的更新。因此，这里就不自己实现一套下载协议，而是复用gradle内部的下载代码及现有的缓存。不过经过测试，很遗憾，不支持传递依赖。具体是怎么实现的请见方法三里的一部分处理。


### 方法三：合理使用反射，Hack一下代码

方法三，是看了几天android gradle plugin以及gradle代码总结出来的，看代码的过程是十分痛苦的，只能一点点猜测相关的类在哪里，不过最后实现的脑洞比较大，比较黑科技。

既然在com.android.application中使用provided aar会报出Provided dependencies can only be jars. 异常，那么有没有办法把这个异常消除掉呢。我们发现在com.android.library中是支持provided aar的，这说明android gradle plugin其自身是支持provided aar的，只是在哪个环节做了下校验，在com.android.application中抛出了异常而已。简单的浏览了下android gradle plugin的代码，发现是完全可以行的通的，不过比较遗憾的是只能消除2.2.0之后的版本的异常，2.2.0之前的版本能消除，但是无法正常使用provided功能，即使是provided的，也会被看成是compile依赖，所以2.2.0之前的版本需要单独处理一下。除此之外，3.0.0与之前的版本消除方式不大一样，需要做区分处理。而对于2.2.0以下的版本怎么做呢？答案是使用方法二中的复用gradle现有代码及缓存。

于是我们需要进行一下android gradle plugin的版本区分，这里做了如下分界

 - android gradle plugin [1.5.0,2.2.0), 不支持传递依赖 ，且gradle版本必须为2.10以上，而android gradle plugin 1.5.0以下版本太过久远，就不支持了
 - android gradle plugin [2.2.0,2,5.0), 支持传递依赖 ，使用反射消除异常
 - android gradle plugin [2.5.0,3.1.0+], 支持传递依赖 ，使用反射替换task执行逻辑，将抛异常修改为输出日志信息

其中,2.4.0+和2.5.0+都未发布过正式版本，而2.4.0预览版代码比较趋向于2.3.0的代码，2.5.0预览版代码比较趋向于3.0.0的代码，于是产生了上述的分界。

先从最简单的版本开始，我们先处理[2.2.0,2,5.0)的版本，这里以2.3.3的代码为例，只要在[2.2.0,2,5.0)这个区间内的版本，都可以适用。

通过搜索 Provided dependencies can only be jars，发现这个异常在com.android.build.gradle.internal.dependency.DependencyChecker中被记录，类型type为7，错误严重级别为2，在配置评估阶段只会打出WARNING的日志，而真正抛出异常的地方是在PrepareDependenciesTask执行的时候抛出的。其关键代码如下

```
private final List<DependencyChecker> checkers = Lists.newArrayList();
@TaskAction
protected void prepare() {
    //省略代码...
    boolean foundError = false;
    //省略代码...
    for (SyncIssue syncIssue : checker.getSyncIssues()) {
        if (syncIssue.getSeverity() == SyncIssue.SEVERITY_ERROR) {
            foundError = true;
            getLogger().error(syncIssue.getMessage());
        }
    }

    if (foundError) {
        throw new GradleException("Dependency Error. See console for details.");
    }

}
```

也就是说我们只要在这个task action被执行前，把checkers变量中对应类型的异常remove掉，就不会出现报错了，实现一下，具体代码如下

```
//遍历所有变体
android.applicationVariants.all { def variant ->
  //获得该变体对应的prepareDependencies task
  def prepareDependenciesTask = project.tasks.findByName("prepare${variant.getName().capitalize()}Dependencies")
  //如果存在该task，则处理，否则无视
  if (prepareDependenciesTask) {
      //移除异常的闭包操作，因为需要复用，所以这里提取成了闭包
      def removeSyncIssues = {
          try {
              //反射获取checkers List<DependencyChecker>对象
              Class prepareDependenciesTaskClass = Class.forName("com.android.build.gradle.internal.tasks.PrepareDependenciesTask")
              Field checkersField = prepareDependenciesTaskClass.getDeclaredField('checkers')
              checkersField.setAccessible(true)
              //得到checkers字段值
              def checkers = checkersField.get(prepareDependenciesTask)
              //因为要进行移除操作，所以用迭代器去遍历checkers
              checkers.iterator().with { checkersIterator ->
                  checkersIterator.each { dependencyChecker ->
                      //需要将DependencyChecker对象中的syncIssues进行遍历，获得对应类型，将其移除
                      //遍历checker中的syncIssues
                      def syncIssues = dependencyChecker.syncIssues
                      syncIssues.iterator().with { syncIssuesIterator ->
                          syncIssuesIterator.each { syncIssue ->
                              //如果类型是7，并且错误严重级别为2，则将其移除，并且输出日志提示
                              if (syncIssue.getType() == 7 && syncIssue.getSeverity() == 2) {
                                  project.logger.lifecycle "[providedAar] WARNING: providedAar has been enabled in com.android.application you can ignore ${syncIssue}"
                                  //移除
                                  syncIssuesIterator.remove()
                              }
                          }
                      }
                  }
              }
          } catch (Exception e) {
              e.printStackTrace()
          }
      }
      //在配置阶段执行该闭包
      prepareDependenciesTask.configure removeSyncIssues
  }
}
```

简单测试一下，跑了下，没问题，后面测试了下兼容性，在[2.2.0,2,5.0)内的版本都适用该代码，不过有个细节性的问题需要处理，即2.4.0+预览版的gradle，其代码虽然偏向2.3.0+的代码，但是内部一些逻辑还是比较偏向于3.0.0的代码的，经过试验发现，不能在prepareDependenciesTask.configure去执行该闭包，那个时候checkers中的syncIssues还是空的，因此需要延迟执行，但必须在任务执行前执行，因此需要将其移到doFirst中去执行，但是对于非2.4.0+预览版的版本，doFirst执行就太晚了，必须在configure阶段进行移除，否则就会报异常，所以需要做下版本区分，需要获取gradle的版本号，那么这个版本号怎么获取呢。很简单，代码如下

```
String getAndroidGradlePluginVersionCompat() {
    String version = null
    try {
        Class versionModel = Class.forName("com.android.builder.model.Version")
        def versionFiled = versionModel.getDeclaredField("ANDROID_GRADLE_PLUGIN_VERSION")
        versionFiled.setAccessible(true)
        version = versionFiled.get(null)
    } catch (Exception e) {
        version = "unknown"
    }
    return version
}
```

然后做下版本区分

```
String androidGradlePluginVersion = getAndroidGradlePluginVersionCompat()

if (androidGradlePluginVersion.startsWith("2.2") || androidGradlePluginVersion.startsWith("2.3")) {
    prepareDependenciesTask.configure removeSyncIssues //configure阶段执行
} else if (androidGradlePluginVersion.startsWith("2.4")) {
    prepareDependenciesTask.doFirst removeSyncIssues //configure阶段过早，无法正常异常，延迟到doFirst中去执行
}
```

这样[2.2.0,2,5.0)这个区间内的版本就处理完了，接下来处理第二复杂的版本，即[2.5.0,3.1.0+]，这里以3.0.1的代码为例，修改代码适用于[2.5.0,3.1.0+]区间内的所有版本

对于这个区间范围内的版本，如果在com.android.application中使用provided aar，则会报出这个错误信息

```
Android dependency '$dependency' is set to compileOnly/provided which is not supported
```

通过搜索报错的关键字符串信息，可以定位到这个异常是在AppPreBuildTask中报出来的，其关键代码如下

```
private ArtifactCollection compileManifests;
private ArtifactCollection runtimeManifests;

@TaskAction
void run() {
    Set<ResolvedArtifactResult> compileArtifacts = compileManifests.getArtifacts();
    Set<ResolvedArtifactResult> runtimeArtifacts = runtimeManifests.getArtifacts();

    // create a map where the key is either the sub-project path, or groupId:artifactId for
    // external dependencies.
    // For external libraries, the value is the version.
    Map<String, String> runtimeIds = Maps.newHashMapWithExpectedSize(runtimeArtifacts.size());

    // build a list of the runtime artifacts
    for (ResolvedArtifactResult artifact : runtimeArtifacts) {
        handleArtifact(artifact.getId().getComponentIdentifier(), runtimeIds::put);
    }

    // run through the compile ones to check for provided only.
    for (ResolvedArtifactResult artifact : compileArtifacts) {
        final ComponentIdentifier compileId = artifact.getId().getComponentIdentifier();
        handleArtifact(
                compileId,
                (key, value) -> {
                    String runtimeVersion = runtimeIds.get(key);
                    if (runtimeVersion == null) {
                        String display = compileId.getDisplayName();
                        throw new RuntimeException(
                                "Android dependency '"
                                        + display
                                        + "' is set to compileOnly/provided which is not supported");
                    } else if (!runtimeVersion.isEmpty()) {
                        // compare versions.
                        if (!runtimeVersion.equals(value)) {
                            throw new RuntimeException(
                                    String.format(
                                            "Android dependency '%s' has different version for the compile (%s) and runtime (%s) classpath. You should manually set the same version via DependencyResolution",
                                            key, value, runtimeVersion));
                        }
                    }
                });
    }
}

private void handleArtifact(
        @NonNull ComponentIdentifier id, @NonNull BiConsumer<String, String> consumer) {
    if (id instanceof ProjectComponentIdentifier) {
        consumer.accept(((ProjectComponentIdentifier) id).getProjectPath().intern(), "");
    } else if (id instanceof ModuleComponentIdentifier) {
        ModuleComponentIdentifier moduleComponentId = (ModuleComponentIdentifier) id;
        consumer.accept(
                moduleComponentId.getGroup() + ":" + moduleComponentId.getModule(),
                moduleComponentId.getVersion());
    } else if (id instanceof OpaqueComponentArtifactIdentifier) {
        // skip those for now.
        // These are file-based dependencies and it's unlikely to be an AAR.
    } else {
        getLogger()
                .warn(
                        "Unknown ComponentIdentifier type: "
                                + id.getClass().getCanonicalName());
    }
}
```

简单说下上述代码的逻辑
 
  - 获取Android aar依赖的编译期依赖compileManifests和运行期依赖runtimeManifests
  - 创建一个map对象runtimeIds，遍历运行期依赖，将依赖的坐标作为key，依赖的版本号作为值
  - 遍历编译期依赖，用依赖的坐标从runtimeIds map中取值，如果取到的值，即依赖的版本号为空，则表示编译期的aar依赖在运行期依赖中不存在，于是抛出Android dependency '$dependency' is set to compileOnly/provided which is not supported异常
  - 如果版本号不为空，则比较编译期和运行期的版本号，如果不一致，则抛版本号不一致的异常，这个需要业务上控制版本号一致，不需要特殊处理

从上面的分析可以看出，抛出异常的原因是aar的编译期依赖在运行期依赖中不存在。所以消除这个异常的方法就是那么我们让其存在即可，但是如果让其存在，最终编译期provided的aar也会被编译进apk中去，这不是我们想要的。换一种方式，替换执行逻辑。因此我们需要替换这个task真正执行的内容，让其抛出异常的部分修改为打日志。具体的修改代码如下，可以直接看注释，关键部分就是将抛异常的逻辑修改为输出日志，其他逻辑和原代码一样。还有一点需要注意的是2.5.0+预览版的代码和3.0.0+版本的代码有一点区别，需要进行兼容处理。

```
//寻找pre${buildType}Build任务
def prepareBuildTask = project.tasks.findByName("pre${variant.getName().capitalize()}Build")
//如果task存在，则进行处理
if (prepareBuildTask) {
    //是否需要重定向执行的action内容
    boolean needRedirectAction = false
    //迭代该任务的actions，如果存在AppPreBuildTask这个名字，则将其移除，标记重定向标记为true
    prepareBuildTask.actions.iterator().with { actionsIterator ->
        actionsIterator.each { action ->
            //取action名字，判断是否包含AppPreBuildTask字符串
            if (action.getActionClassName().contains("AppPreBuildTask")) {
                //移除，并进行标记需要重定向实现
                actionsIterator.remove()
                needRedirectAction = true
            }
        }
    }
    //如果重定向标记为true，则将原有逻辑拷贝下来，用反射实现一遍，然后将抛异常的部分修改为输出日志
    if (needRedirectAction) {
        //添加新的action，代替被移除的action执行逻辑
        prepareBuildTask.doLast {
            //下面一大坨是兼容处理，3.0.0+的版本是compileManifests和runtimeManifests，并且在配置阶段这两个值已经被赋值，2.5.0+预览版的代码是compileClasspath和runtimeClasspath，其值在执行时通过variantScope获取
            def compileManifests = null
            def runtimeManifests = null
            Class appPreBuildTaskClass = Class.forName("com.android.build.gradle.internal.tasks.AppPreBuildTask")
            try {
                //3.0.0+的版本直接取compileManifests和runtimeManifests字段的值
                Field compileManifestsField = appPreBuildTaskClass.getDeclaredField("compileManifests")
                Field runtimeManifestsField = appPreBuildTaskClass.getDeclaredField("runtimeManifests")
                compileManifestsField.setAccessible(true)
                runtimeManifestsField.setAccessible(true)
                compileManifests = compileManifestsField.get(prepareBuildTask)
                runtimeManifests = runtimeManifestsField.get(prepareBuildTask)
            } catch (Exception e) {
                try {
                    //2.5.0+的版本，由于其值是在run阶段赋值的，因此我们需要换一个方式获取，通过variantScope去拿对应的内容
                    Field variantScopeField = appPreBuildTaskClass.getDeclaredField("variantScope")
                    variantScopeField.setAccessible(true)
                    def variantScope = variantScopeField.get(prepareBuildTask)
                    //为了兼容，需要避免import导包，这里使用全类名路径进行引用，且使用注释消除ide警告
                    //noinspection UnnecessaryQualifiedReference
                    compileManifests = variantScope.getArtifactCollection(com.android.build.gradle.internal.publishing.AndroidArtifacts.ConsumedConfigType.COMPILE_CLASSPATH, com.android.build.gradle.internal.publishing.AndroidArtifacts.ArtifactScope.ALL, com.android.build.gradle.internal.publishing.AndroidArtifacts.ArtifactType.MANIFEST)
                    runtimeManifests = variantScope.getArtifactCollection(com.android.build.gradle.internal.publishing.AndroidArtifacts.ConsumedConfigType.RUNTIME_CLASSPATH, com.android.build.gradle.internal.publishing.AndroidArtifacts.ArtifactScope.ALL, com.android.build.gradle.internal.publishing.AndroidArtifacts.ArtifactType.MANIFEST)
                } catch (Exception e1) {
                }
            }
            try {
                //下面还原原有action的逻辑

                //获取编译期和运行期android aar依赖
                Set<ResolvedArtifactResult> compileArtifacts = compileManifests.getArtifacts()
                Set<ResolvedArtifactResult> runtimeArtifacts = runtimeManifests.getArtifacts()

                //创建Map
                Map<String, String> runtimeIds = new HashMap<>(runtimeArtifacts.size())

                //原有的handleArtifact函数，这里改成了闭包
                def handleArtifact = { id, consumer ->
                    if (id instanceof ProjectComponentIdentifier) {
                        consumer(((ProjectComponentIdentifier) id).getProjectPath().intern(), "")
                    } else if (id instanceof ModuleComponentIdentifier) {
                        ModuleComponentIdentifier moduleComponentId = (ModuleComponentIdentifier) id
                        consumer(
                                moduleComponentId.getGroup() + ":" + moduleComponentId.getModule(),
                                moduleComponentId.getVersion())
                    } else {
                        getLogger()
                                .warn(
                                "Unknown ComponentIdentifier type: "
                                        + id.getClass().getCanonicalName())
                    }
                }

                //处理原有的for循环逻辑，将runtime部分放入runtimeIds的map，键是坐标，值为版本号
                runtimeArtifacts.each { def artifact ->
                    def runtimeId = artifact.getId().getComponentIdentifier()
                    def putMap = { def key, def value ->
                        runtimeIds.put(key, value)
                    }
                    handleArtifact(runtimeId, putMap)
                }

                //遍历compile依赖部分的内容，判断是否在runtime依赖中存在版本号，如果不存在，则会抛异常
                compileArtifacts.each { def artifact ->
                    final ComponentIdentifier compileId = artifact.getId().getComponentIdentifier()
                    def checkCompile = { def key, def value ->
                        String runtimeVersion = runtimeIds.get(key)
                        if (runtimeVersion == null) {
                            String display = compileId.getDisplayName()
                            //这里抛的异常，修改为打日志，仅此一处修改
                            project.logger.lifecycle(
                                    "[providedAar] WARNING: providedAar has been enabled in com.android.application you can ignore 'Android dependency '"
                                            + display
                                            + "' is set to compileOnly/provided which is not supported'")
                        } else if (!runtimeVersion.isEmpty()) {
                            // compare versions.
                            if (!runtimeVersion.equals(value)) {
                                throw new RuntimeException(
                                        String.format(
                                                "Android dependency '%s' has different version for the compile (%s) and runtime (%s) classpath. You should manually set the same version via DependencyResolution",
                                                key, value, runtimeVersion));
                            }
                        }
                    }
                    handleArtifact(compileId, checkCompile)
                }
            } catch (Exception e) {
                e.printStackTrace()
            }
        }
    }
}
```

[2.5.0,3.1.0+]区间内的版本也搞定了，通过兼容性测试，发现这段代码完美的适配了[2.5.0,3.1.0+]这个区间内的所有版本。

当然，为了进行各个版本的区分处理，需要进行一些逻辑上的自定义，所以，我们最好不要直接使用provided这个configuration，而是创建自定义的providedAar，这么做的好处就是为了后续扩展，提供更加灵活的途径，而不需要业务修改现有的代码。这部分的代码如下:

```
//如果没有引用com.android.application插件，直接return
if (!project.getPlugins().hasPlugin("com.android.application")) {
    return
}
//如果已经添加过providedAar，直接return
if (project.getConfigurations().findByName("providedAar") != null) {
    return
}
//如果不存在provided，直接return
Configuration providedConfiguration = project.getConfigurations().findByName("provided")
if (providedConfiguration == null) {
    return
}
//创建providedAar
Configuration providedAarConfiguration = project.getConfigurations().create("providedAar")
//获取android gradle plugin版本号
String androidGradlePluginVersion = getAndroidGradlePluginVersionCompat()
//这里只处理2.2.0+的版本的provided与providedAar的继承关系，2.2.0以下的版本，不能添加这个继承关系，添加了会报错，且无法消除错误
if (androidGradlePluginVersion.startsWith("2.2") || androidGradlePluginVersion.startsWith("2.3") || androidGradlePluginVersion.startsWith("2.4") || androidGradlePluginVersion.startsWith("2.5") || androidGradlePluginVersion.startsWith("3.")) {
    //大于2.2.0的版本让provided继承providedAar，低于2.2.0的版本，手动提取aar中的jar添加依赖到scope为provided的依赖中去
    providedConfiguration.extendsFrom(providedAarConfiguration)
}
```

业务上使用

```
dependencies {
  providedAar 'com.tencent.tinker:tinker-android-lib:1.9.1'
}
```

不要使用


```
dependencies {
  provided 'com.tencent.tinker:tinker-android-lib:1.9.1'
}
```

值得注意的是2.2.0+以上的版本，处理后providedAar是支持传递依赖的，但是2.2.0以下由于其特殊性，不能支持传递依赖。

接下里就是最蛋疼的2.2.0以下的版本的处理，2.2.0以下的版本，虽然也可以使用[2.2.0,2.5.0)这个区间的方法将异常进行消除，但是即使消除了，因为其代码的特殊性，导致即使是provided依赖的aar，最终也会被打包进apk中，这里以2.1.3的代码为例，如下:

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

从两个版本的代码中可以看出有一处不同，如果不存在provided aar问题的话，2.2.0以下的版本在com.android.library中会将lib设为可选，但是在com.android.application就会直接抛出异常，具体的区别代码如下

```
if (isLibrary || lib.isOptional()) {
    //如果是com.android.library或者是可选的，则设置该lib为可选
    lib.setIsOptional(true);
} else {
   //抛异常
}
```

一旦将lib设置为可选，后续就不会打包进apk，那么我们能不能将其设置为可选从而跳过该异常呢，答案是不能，第一个原因是时机过早，无法替换，第二个原因是待替换部分的代码过多，并且该逻辑在DependencyManager中，这个类比较关键，能不改还是不要改的比较好。于是只能回退到最原始的解决方案，复用gradle下载依赖的逻辑和缓存策略，手动获取aar，提取jar文件，添加到provided这个scope上。所以这个问题拆分出来就变成了如下问题。

 - 如何判断当前是否在离线模式
 - 如何在非离线模式下使用gradle现有代码获取最新的依赖文件
 - 如何在离线模式下使用现有的gradle缓存
 - 在线获取失败的情况下使用本地缓存进行重试，如场景：公司maven，外网无法访问，但是本地有缓存
 - SNAPSHOT版本的获取
 - Release版本的获取

对于第一个问题，如何判断当前gradle是否在离线模式下，很简单，这个值位于project.gradle.startParameter中，调用其isOffline()函数即可获取是否在离线模式下

```
 /**
 * 获取是否是离线模式
 */
StartParameter startParameter = project.gradle.startParameter
boolean isOffline = startParameter.isOffline()
project.logger.lifecycle("[providedAar] gradle offline: ${isOffline}")
if (isOffline) {
    project.logger.lifecycle("[providedAar] use local cache dependency because offline is enabled")
} else {
    project.logger.lifecycle("[providedAar] use remote dependency because offline is disabled")
}
```

对于第2，3，4个问题，其解决问题的大致伪代码如下

```
project.getGradle().addListener(new DependencyResolutionListener() {
    @Override
    void beforeResolve(ResolvableDependencies dependencies) {
        //此回调会多次进入，我们只需要解析一次，因此只要进入，就remove，然后执行我们的解析操作
        project.gradle.removeListener(this)
        //遍历所有依赖进行解析
        resolveDependencies(project, isOffline)
    }

    @Override
    void afterResolve(ResolvableDependencies resolvableDependencies) {

    }
})

def resolveDependencies = { Project project, boolean offline ->
    //遍历providedAar的所有依赖
    project.getConfigurations().getByName("providedAar").getDependencies().each {
        def dependency ->
            //解析依赖，将必要的参数传入，最后一个参数为是否强制使用本地缓存
            boolean matchArtifact = resolveArtifactFromRepositories(project, dependency, offline, false)
            if (!matchArtifact && offline) {
                //如果解析不成功并且是离线模式，则输出日志，提示无法解析
                project.logger.lifecycle("[providedAar] can't resolve ${dependency.group}:${dependency.name}:${dependency.version} from local cache, you must disable offline model in gradle")
            } else if (!matchArtifact && !offline) {
                //如果解析不成功并且是在线模式，则使用本地缓存进行重试
                project.logger.lifecycle("[providedAar] can't resolve ${dependency.group}:${dependency.name}:${dependency.version} from remote, is this dependency correct?")
                //重试本地缓存，最后一个参数表示强制使用本地缓存
                boolean matchArtifactFromRetryLocalCache = resolveArtifactFromRepositories(project, dependency, offline, true)
                if (matchArtifactFromRetryLocalCache) {
                    //如果本地缓存重试成功了，则输出日志提醒
                    project.logger.lifecycle("[providedAar] retry resolve ${dependency.group}:${dependency.name}:${dependency.version} from local cache success, you'd better disable offline model in gradle")
                }
            }
    }
}
```

于是问题就变成了resolveArtifactFromRepositories函数的实现，该函数中需要做的就是遍历每一个maven仓库，判断依赖是否存在，找到一个就返回，平时我们在gradle中使用each去遍历，而我们只要找到一个需要的值就返回，因此这里需要用到any去遍历，找到之后返回true，其大致代码如下

```
 /**
 * 从所有仓库解析，只要找到就返回
 */
def resolveArtifactFromRepositories = { Project project,
                                        Dependency dependency,
                                        boolean offline,
                                        boolean forceLocalCache ->
    //从repositories中去找，用any是因为只要找到一个就需要return
    boolean matchArtifact = project.getRepositories().any {
        def repository ->
            //只处理maven
            if (repository instanceof DefaultMavenArtifactRepository) {
                boolean resolveArtifactFromRepositoryResult = resolveArtifactFromRepository(project, repository, dependency, offline, forceLocalCache)
                if (resolveArtifactFromRepositoryResult) {
                    return true
                }
            }
    }
    return matchArtifact
}
```

最终代码变成了resolveArtifactFromRepository函数的实现，该函数的功能主要是从单个maven仓库中进行解析。其代码如下

```
/**
 * 从单个mavan仓库解析
 */
def resolveArtifactFromRepository = { Project project,
                                      def repository,
                                      Dependency dependency,
                                      boolean offline,
                                      boolean forceLocalCache ->
    //从repository对象中创建MavenResolver解析对象
    MavenResolver mavenResolver = repository.createResolver()
    //创建依赖的信息持有类，这是一个简单的java bean对象，反射创建，因为不同gralde版本类名发生了变化
    def moduleComponentArtifactMetadata = createModuleComponentArtifactMetaData(mavenResolver, offline, forceLocalCache, dependency.group, dependency.name, dependency.version, "aar", "aar")
    if (moduleComponentArtifactMetadata != null) {
        //创建Artifact解析器对象，反射创建，因为一些函数和字段是私有的
        ExternalResourceArtifactResolver externalResourceArtifactResolver = createArtifactResolver(mavenResolver)
        if (externalResourceArtifactResolver != null) {
            //强制本地缓存或者离线模式，走本地缓存
            if (forceLocalCache || offline) {
                //获取本地缓存查找器，反射创建，因为一些函数和字段是私有的
                LocallyAvailableResourceFinder locallyAvailableResourceFinder = getLocallyAvailableResourceFinder(externalResourceArtifactResolver)
                if (locallyAvailableResourceFinder != null) {
                    //从缓存中查找，找到了就返回true
                    boolean fetchFromLocalCacheResult = fetchFromLocalCache(project, locallyAvailableResourceFinder, moduleComponentArtifactMetadata, dependency)
                    if (fetchFromLocalCacheResult) {
                        return true
                    }
                }
            } else {
                //在线模式，走远程依赖，实际逻辑gradle内部处理，找到了就返回true
                boolean fetchFromRemoteResult = fetchFromRemote(project, externalResourceArtifactResolver, moduleComponentArtifactMetadata, dependency)
                if (fetchFromRemoteResult) {
                    return true
                }
            }
        }
    }
    return false
}
```


由resolveArtifactFromRepository函数，拆分问题，于是问题变成了createModuleComponentArtifactMetaData函数、
createArtifactResolver函数，getLocallyAvailableResourceFinder函数，fetchFromLocalCache函数，fetchFromRemote函数的实现逻辑

首先来看createModuleComponentArtifactMetaData函数，具体的逻辑见代码中的注释

```
/**
 * 创建ModuleComponentArtifactMetaData对象，之所以用反射，是因为gradle的不同版本，这个类的名字发生了变化，低版本可能是DefaultModuleComponentArtifactMetaData，而高版本改成了org.gradle.internal.component.external.model.DefaultModuleComponentArtifactMetadata
 */
def createModuleComponentArtifactMetaData = { MavenResolver mavenResolver, boolean offline, boolean forceLocalCache, String group, String name, String version, String type, String extension ->
    try {
        //调用静态函数，传入group,name,version,返回一个ModuleComponentIdentifier对象
        ModuleComponentIdentifier componentIdentifier = DefaultModuleComponentIdentifier.newId(group, name, version)

        //获得ModuleComponentArtifactMetadata的class对象，之所以用反射，是因为不同的gradle版本，这个类的类名发生了变化，从DefaultModuleComponentArtifactMetaData变成了DefaultModuleComponentArtifactMetadata
        Class moduleComponentArtifactMetadataClass = null
        try {
            moduleComponentArtifactMetadataClass = Class.forName("org.gradle.internal.component.external.model.DefaultModuleComponentArtifactMetaData")
        } catch (ClassNotFoundException e) {
            try {
                moduleComponentArtifactMetadataClass = Class.forName("org.gradle.internal.component.external.model.DefaultModuleComponentArtifactMetadata")
            } catch (ClassNotFoundException e1) {
            }
        }
        //找不到类则直接返回
        if (moduleComponentArtifactMetadataClass == null) {
            return null
        }
        //获得ModuleComponentArtifactMetadata类的构造函数
        Constructor moduleComponentArtifactMetadataConstructor = moduleComponentArtifactMetadataClass.getDeclaredConstructor(ModuleComponentArtifactIdentifier.class)
        moduleComponentArtifactMetadataConstructor.setAccessible(true)

        //离线模式或者强制使用本地缓存时不需要进行SNAPSHOT处理，gradle能够查找到SNAPSHOT本地缓存
        //在线模式并且版本号是以-SNAPSHOT结尾，进行处理，如果不处理，gradle无法定位当前最新的快照版本
        if (!offline && !forceLocalCache && version.toUpperCase().endsWith("-SNAPSHOT")) {
            //调用MavenResolver对象的findUniqueSnapshotVersion函数，获取当前SNASHOP版本的最新快照版本
            //之所以用反射是因为这个函数不是公共的
            Method findUniqueSnapshotVersionMethod = MavenResolver.class.getDeclaredMethod("findUniqueSnapshotVersion", ModuleComponentIdentifier.class, ResourceAwareResolveResult.class)
            findUniqueSnapshotVersionMethod.setAccessible(true)
            def mavenUniqueSnapshotModuleSource = findUniqueSnapshotVersionMethod.invoke(mavenResolver, componentIdentifier, new DefaultResourceAwareResolveResult())
            if (mavenUniqueSnapshotModuleSource != null) {
                //如果定位到了最新的快照版本，则使用MavenUniqueSnapshotComponentIdentifier对象对componentIdentifier和mavenUniqueSnapshotModuleSource重新包装，将依赖坐标和时间戳传入
                MavenUniqueSnapshotComponentIdentifier mavenUniqueSnapshotComponentIdentifier = new MavenUniqueSnapshotComponentIdentifier(componentIdentifier.getGroup(),
                        componentIdentifier.getModule(),
                        componentIdentifier.getVersion(),
                        mavenUniqueSnapshotModuleSource.getTimestamp())
                //创建DefaultModuleComponentArtifactIdentifier对象，只要传入包装过的mavenUniqueSnapshotComponentIdentifier对象和name, type, extension即可
                DefaultModuleComponentArtifactIdentifier moduleComponentArtifactIdentifier = new DefaultModuleComponentArtifactIdentifier(mavenUniqueSnapshotComponentIdentifier, name, type, extension)
                return moduleComponentArtifactMetadataConstructor.newInstance(moduleComponentArtifactIdentifier)
            }
        } else {
            //如果是release版本或者本地缓存，其版本是唯一的，不需要查找对应的时间戳，因此直接创建DefaultModuleComponentArtifactIdentifier
            DefaultModuleComponentArtifactIdentifier moduleComponentArtifactIdentifier = new DefaultModuleComponentArtifactIdentifier(componentIdentifier, name, type, extension)
            return moduleComponentArtifactMetadataConstructor.newInstance(moduleComponentArtifactIdentifier)
        }
    } catch (Exception e) {
    }
    return null
}

```

然后是createArtifactResolver函数，这个函数为了获取ExternalResourceArtifactResolver，实现是调用MavenResolver对象的父类函数createArtifactResolver进行创建

```
/**
 * 创建ExternalResourceArtifactResolver对象，用反射的原因是这个方法是protected的
 */
def createArtifactResolver = { MavenResolver mavenResolver ->
    if (mavenResolver != null) {
        try {
            Method createArtifactResolverMethod = ExternalResourceResolver.class.getDeclaredMethod("createArtifactResolver")
            createArtifactResolverMethod.setAccessible(true)
            return createArtifactResolverMethod.invoke(mavenResolver)
        } catch (Exception e) {
            e.printStackTrace()
        }
    }
    return null
}
```

接下来是getLocallyAvailableResourceFinder函数，这个函数是为了获取本地缓存文件的查找器LocallyAvailableResourceFinder对象

```
/**
 * 反射获取locallyAvailableResourceFinder，反射获取的原因是locallyAvailableResourceFinder这个字段是私有的
 */
def getLocallyAvailableResourceFinder = { ExternalResourceArtifactResolver externalResourceArtifactResolver ->
    if (externalResourceArtifactResolver != null) {
        try {
            Field locallyAvailableResourceFinderField = Class.forName("org.gradle.api.internal.artifacts.repositories.resolver.DefaultExternalResourceArtifactResolver").getDeclaredField("locallyAvailableResourceFinder")
            locallyAvailableResourceFinderField.setAccessible(true)
            return locallyAvailableResourceFinderField.get(externalResourceArtifactResolver)
        } catch (Exception e) {
            e.printStackTrace()
        }
    }
    return null
}
```

剩下的两个函数，是最重要的两个函数，即fetchFromLocalCache函数和fetchFromRemote函数

先来看怎么从本地缓存中获取对应的依赖文件，具体逻辑已经在代码中进行了注释说明

```
/**
 * 从本地缓存获取
 */
def fetchFromLocalCache = { Project project,
                            LocallyAvailableResourceFinder locallyAvailableResourceFinder,
                            def moduleComponentArtifactMetadata,
                            def dependency ->
    //获取本地可选的候选列表
    LocallyAvailableResourceCandidates locallyAvailableResourceCandidates = locallyAvailableResourceFinder.findCandidates(moduleComponentArtifactMetadata)
    //如果本地的候选列表不为空
    if (!locallyAvailableResourceCandidates.isNone()) {
        //候选列表的其中一个实现，组合候选列表对象CompositeLocallyAvailableResourceCandidates
        Class compositeLocallyAvailableResourceCandidatesClass = Class.forName('org.gradle.internal.resource.local.CompositeLocallyAvailableResourceFinder$CompositeLocallyAvailableResourceCandidates')
        //如果是CompositeLocallyAvailableResourceCandidates的实例
        if (compositeLocallyAvailableResourceCandidatesClass.isInstance(locallyAvailableResourceCandidates)) {
            //获取这个组合的候选列表字段allCandidates并遍历它，allCandidates是持有组合对象的字段，我们取其中一个，只要找到然后return就可以了
            Field allCandidatesField = compositeLocallyAvailableResourceCandidatesClass.getDeclaredField("allCandidates")
            allCandidatesField.setAccessible(true)
            List<LocallyAvailableResourceCandidates> allCandidates = allCandidatesField.get(locallyAvailableResourceCandidates)
            //当list不为空的时候，遍历，取其中一个文件
            if (allCandidates != null) {
                FileCollection aarFiles = null
                //用any的原因是为了取一个就返回
                allCandidates.any { candidate ->
                    //判断是否是LazyLocallyAvailableResourceCandidates实例
                    if (candidate instanceof LazyLocallyAvailableResourceCandidates) {
                        //如果该候选列表存在文件，则获取文件，然后过滤aar文件，返回
                        if (!candidate.isNone()) {
                            //getFiles函数获取文件列表
                            Method getFilesMethod = LazyLocallyAvailableResourceCandidates.class.getDeclaredMethod("getFiles")
                            getFilesMethod.setAccessible(true)
                            List<File> candidateFiles = getFilesMethod.invoke(candidate)
                            //过滤aar文件
                            aarFiles = project.files(candidateFiles).filter {
                                it.name.endsWith(".aar")
                            }
                            //如果不为空，表示找到了，返回true
                            if (!aarFiles.empty) {
                                return true
                            }
                        }
                    }
                }
                //如果找到了aar文件，则提取jar，添加到provided的scope上
                if (!aarFiles.empty) {
                    //遍历找到的aar文件列表
                    aarFiles.files.each { File aarFile ->
                        FileCollection jarFromAar = project.zipTree(aarFile).filter {
                            it.name == "classes.jar"
                        }
                        //添加到provided的scope上
                        project.getDependencies().add("provided", jarFromAar)
                        //输出日志信息
                        project.logger.lifecycle("[providedAar] convert aar ${dependency.group}:${dependency.name}:${dependency.version} to jar and add provided file ${jarFromAar.getAsPath()} from ${aarFile}")
                    }
                    return true
                }
            }
        }
    }
    return false
}
```

然后是从远程获取对应的依赖，更新本地文件，具体的实现逻辑由gradle内部取保证，我们只要调用其函数即可。

```
/**
 * 从远程获取
 */
def fetchFromRemote = { Project project,
                        ExternalResourceArtifactResolver externalResourceArtifactResolver,
                        def moduleComponentArtifactMetadata,
                        def dependency ->
    try {
        if (moduleComponentArtifactMetadata != null) {
            //判断当前maven仓库上是否存在该依赖
            boolean artifactExists = externalResourceArtifactResolver.artifactExists(moduleComponentArtifactMetadata, new DefaultResourceAwareResolveResult())
            //如果该远程仓库存在该依赖
            if (artifactExists) {
                //进行依赖解析，获得本地可用文件
                LocallyAvailableExternalResource locallyAvailableExternalResource = externalResourceArtifactResolver.resolveArtifact(moduleComponentArtifactMetadata, new DefaultResourceAwareResolveResult())

                if (locallyAvailableExternalResource != null) {
                    //获取解析到的文件
                    File aarFile = null
                    try {
                        def locallyAvailableResource = locallyAvailableExternalResource.getLocalResource()
                        if (locallyAvailableResource != null) {
                            aarFile = locallyAvailableResource.getFile()
                        }
                    } catch (Exception e) {
                        //高版本gradle兼容
                        try {
                            aarFile = locallyAvailableExternalResource.getFile()
                        } catch (Exception e1) {
                        }
                    }
                    //该依赖对应的文件存在的话，提取jar，添加到provided的scope上
                    if (aarFile != null && aarFile.exists()) {
                        FileCollection jarFromAar = project.zipTree(aarFile).filter {
                            it.name == "classes.jar"
                        }
                        //添加到provided的scope上
                        project.getDependencies().add("provided", jarFromAar)
                        //输出日志
                        project.logger.lifecycle("[providedAar] convert aar ${dependency.group}:${dependency.name}:${dependency.version} in ${repository.url} to jar and add provided file ${jarFromAar.getAsPath()} from ${aarFile}")
                        return true
                    }
                }
            }
        }
    } catch (Exception e) {
        //可能会出现ssl之类的异常，无视掉
    }
    return false
}
```

将以上代码进行组合，就得到了[CompatPlugin.groovy中的providedAarCompat函数](https://github.com/lizhangqu/AndroidGradlePluginCompat/blob/master/buildSrc/src/main/groovy/io/github/lizhangqu/plugin/compat/CompatPlugin.groovy)，搜索该文件中的providedAarCompat函数，即最终组合完成的代码。

可以看到，整个实现逻辑还是是否复杂的，尤其是本地缓存依赖和在线依赖的解析部分，以及SNAPSHOT版本时间戳的获取及对应对应的包装。需要理解整个过程还是需要自己过一遍整个代码。

不过遗憾的是，这部分的实现是不支持传递依赖的，如果要支持传递依赖，则会涉及到configuration的传递，逻辑会变得更加复杂，因此这里就不处理了，实际上问题也不大，只需要手动声明传递依赖即可。

### 总结

最重要的还是解决问题的思路，同一个问题，可能有不同的解决方法，需要整体考虑选择何种方式去解决。解决问题的过程就是不断学习的过程，通过实现这个需求，对gradle的依赖管理策略、缓存也更加熟悉了。
