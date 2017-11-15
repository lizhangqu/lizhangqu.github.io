title: aapt2适配之资源id固定
date: 2017-11-15 13:33:42
categories: [Android]
tags: [Android, aapt2, 资源id固定]
---

### 前言

资源id的固定在热修复和插件化中极其重要。在热修复中，构建patch时，需要保持patch包的资源id和基线包的资源id一致；在插件化中，如果插件需要引用宿主的资源，则需要将宿主的资源id进行固定，因此，资源id的固定在这两种场景下是尤为重要的。而在Android Gradle Plugin 3.0.0中，默认开启了aapt2，原先aapt的资源固定方式public.xml也将失效，必须寻找一种新的资源固定的方式，而不是简单的禁用掉aapt2，因此本文来探讨一下开启aapt2的情况下如何进行资源id的固定。

<!-- more -->

### aapt的资源固定方式

在探索aapt2资源固定方式前，先来温习一下aapt原先的资源固定方式。

  - 编译基线包时添加aapt参数-P导出public.xml文件
  - 编译插件或者patch包时，将public.xml文件拷贝至资源merge完成的目录，并根据values.xml中的定义和public.xml中的定义，选择性的生成ids.xml文件

 对应的代码如下

```
apply plugin: PublicPlugin

class PublicPlugin implements Plugin<Project> {
    void apply(Project project) {
        project.afterEvaluate {
            if (project.plugins.hasPlugin("com.android.application")) {
                def android = project.extensions.getByName("android")
                android.applicationVariants.all { def variant ->
                    File publicXmlFile = project.rootProject.file('public.xml')
                    //public文件存在则应用，不存在则生成
                    if (publicXmlFile.exists()) {
                        //aapt的应用需要将文件拷贝到对应的目录
                        //aapt public.xml文件的应用并不是只是拷贝public.xml文件那么简单，还要根据生成的public.xml生成ids.xml文件，并将ids.xml中与values.xml中重复定义的id去除
                        String mergeResourcesTaskName = variant.variantData.getScope().getMergeResourcesTask().name
                        def mergeResourcesTask = project.tasks.getByName(mergeResourcesTaskName)
                        //资源merge的task存在则在其merge完资源后拷贝public.xml并生成ids.xml
                        if (mergeResourcesTask) {
                            mergeResourcesTask.doLast {
                                //拷贝public.xml文件
                                File toDir = new File(mergeResourcesTask.outputDir, "values")
                                project.copy {
                                    project.logger.error "${variant.name}:copy from ${publicXmlFile.getAbsolutePath()} to ${toDir}/public.xml"
                                    from(publicXmlFile.getParentFile()) {
                                        include "public.xml"
                                        rename "public.xml", "public.xml"
                                    }
                                    into(toDir)
                                }
                                //生成ids.xml文件
                                File valuesFile = new File(toDir, "values.xml")
                                File idsFile = new File(toDir, "ids.xml")
                                if (valuesFile.exists() && publicXmlFile.exists()) {
                                    //记录在values.xml中存在的id定义
                                    def valuesNodes = new XmlParser().parse(valuesFile)
                                    Set<String> existIdItems = new HashSet<String>()
                                    valuesNodes.each {
                                        if ("id".equalsIgnoreCase("${it.@type}")) {
                                            existIdItems.add("${it.@name}")
                                        }
                                    }
                                    GFileUtils.deleteQuietly(idsFile)
                                    GFileUtils.touch(idsFile)

                                    idsFile.append("<?xml version=\"1.0\" encoding=\"utf-8\"?>")
                                    idsFile.append("\n")
                                    idsFile.append("<resources>")
                                    idsFile.append("\n")

                                    def publicXMLNodes = new XmlParser().parse(publicXmlFile)
                                    publicXMLNodes.each {
                                        //获取public.xml中定义的id类型item
                                        if ("id".equalsIgnoreCase("${it.@type}")) {
                                            //如果在values.xml中没有定义，则添加到ids.xml中
                                            //如果已经在values.xml中定义，则忽略它
                                            if (!existIdItems.contains("${it.@name}")) {
                                                idsFile.append("\t<item type=\"id\" name=\"${it.@name}\" />\n")
                                            } else {
                                                project.logger.error "already exist id item ${it.@name}, ignore it"
                                            }
                                        }
                                    }
                                    idsFile.append("</resources>")
                                }
                            }
                        }
                    } else {
                        //不存在则生成
                        project.logger.error "${publicXmlFile} not exists, generate it"
                        //aapt 添加-P参数生成
                        aaptOptions.additionalParameters("-P", "${publicXmlFile}")
                    }
                }
            }
        }
    }
}
```

很简单，生成public.xml时使用aapt的参数-P，指定生成的文件路径即可；应用public.xml则将其拷贝到values目录下，唯一需要注意的是这个导出的public.xml文件会存在资源id未定义的情况，因此需要生成ids.xml文件，对未定义的id类型资源进行定义。而这个生成的ids.xml文件，可能与values/values.xml文件中的id存在重复定义的现象，因此生成的时候，则需要判断对应的id名在values.xml文件中是否存在，如果存在则直接忽略，因为它已经定义了；如果不存在，则添加到ids.xml中进行定义。

这种方式不支持删除现有的资源，如果删除了现有的资源，public.xml中的定义也得删除，否则会报资源未定义的错误。

### aapt2的资源固定方式

那么在aapt2中上面这种方式还生效吗，答案是否定的，至于为什么，可以参考之前的一篇文章[aapt2 资源 compile 过程](/2017/10/31/aapt2资源compile过程/)，因为所有merge的资源都已经经过了预编译，产生了flat文件，这时候将public.xml文件拷贝至该目录就会产生编译错误。那么如何解决了。通过查看Android Gradle Plugin 3.0.0的代码发现了一些猫腻，关键代码如下

```
public static ImmutableList<String> makeLink(
            @NonNull AaptPackageConfig config, @NonNull File intermediateDir) throws AaptException {
    ImmutableList.Builder<String> builder = ImmutableList.builder();

    if (config.isVerbose()) {
        builder.add("-v");
    }

    File stableResourceIdsFile = new File(intermediateDir, "stable-resource-ids.txt");
    // TODO: For now, we ignore this file, but as soon as aapt2 supports it, we'll use it.

    //此处省略n行代码
}

```

大概可以猜测可以通过指定稳定的资源id映射文件达到固定资源id的作用，但是代码中这个文件并没有共同参与资源编译的过程，因此这部分代码暂时无效，接下来去aapt2命令中寻找一下。通过aapt2 link --help可以发现有两个参数。如下

```
--stable-ids arg   File containing a list of name to ID mapping.
--emit-ids arg     Emit a file at the given path with a list of name to ID mappings, suitable for use with --stable-ids.
```

大概意思就是说可以通过--emit-ids参数指定一个文件，该文件会输出资源名字到资源id的一个映射，这个文件可以被--stable-ids参数使用。


通过简单的测试，发现这两个参数可以完全满足我们的需求。而且这种方式支持删除现有的资源。编写代码验证之。


```
apply plugin: PublicPlugin

class PublicPlugin implements Plugin<Project> {
    void apply(Project project) {
        project.afterEvaluate {
            if (project.plugins.hasPlugin("com.android.application")) {
                def android = project.extensions.getByName("android")
                android.applicationVariants.all { def variant ->
                    def processResourcesTask = project.tasks.getByName("process${variant.name.capitalize()}Resources")
                    if (processResourcesTask) {
                        def aaptOptions = processResourcesTask.aaptOptions
                        File publicTxtFile = project.rootProject.file('public.txt')
                        //public文件存在，则应用，不存在则生成
                        if (publicTxtFile.exists()) {
                            project.logger.error "${publicTxtFile} exists, apply it."
                            //aapt2添加--stable-ids参数应用
                            aaptOptions.additionalParameters("--stable-ids", "${publicTxtFile}")
                        } else {
                            project.logger.error "${publicTxtFile} not exists, generate it."
                            //aapt2添加--emit-ids参数生成
                            aaptOptions.additionalParameters("--emit-ids", "${publicTxtFile}")
                        }
                    }
                }
            }
        }
    }
}
```

代码很简单，就是当public.txt文件不存在时，添加--emit-ids参数进行生产，如果存在时，则添加--stable-ids进行应用。

简单验证一下，定义3个颜色资源

```
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="colorAccent">#FF4081</color>
    <color name="colorPrimary">#3F51B5</color>
    <color name="colorPrimaryDark">#303F9F</color>
</resources>
```

编译，可以看到项目根目录下产生了public.txt文件，其中这三个资源对应的内容为

```
io.github.lizhangqu.aapt2:color/colorAccent = 0x7f040026
io.github.lizhangqu.aapt2:color/colorPrimary = 0x7f040027
io.github.lizhangqu.aapt2:color/colorPrimaryDark = 0x7f040028
```

在这三个资源中插入一个资源，打乱资源顺序，如下

```
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="colorAccent">#FF4081</color>
    <color name="colorAccentBBBBB">#FF4081</color>
    <color name="colorPrimary">#3F51B5</color>
    <color name="colorPrimaryDark">#303F9F</color>
</resources>

```

将刚才生成的public.txt文件备份至其他目录，删除根目录下的public.txt文件，保证重新生成该文件，重新编译资源，此时生成的public.txt文件中的这四个资源对应的内容为

```
io.github.lizhangqu.aapt2:color/colorAccent = 0x7f040026
io.github.lizhangqu.aapt2:color/colorAccentBBBBB = 0x7f040027
io.github.lizhangqu.aapt2:color/colorPrimary = 0x7f040028
io.github.lizhangqu.aapt2:color/colorPrimaryDark = 0x7f040029
```

app/build/intermediates/res/symbol-table-with-package/debug/package-aware-r.txt文件中对应的资源id为

```
int color colorAccent 0x7f040026
int color colorAccentBBBBB 0x7f040027
int color colorPrimary 0x7f040028
int color colorPrimaryDark 0x7f040029
```

两个文件中的内容完全可以对的上，只要看其中一个就可以了；可以看到由于colorAccentBBBBB的插入，colorPrimary和colorPrimaryDark都向后顺延了一位，也就是说，在没有资源固定的情况下，如果增删改等操作发生，是有可能导致现有资源id发生变化的。

因此我们开始验证--stable-ids参数的有效性，将根目录下的public.txt文件删除，将之前备份好的public.txt文件拷贝到根目录，重新编译资源。这时候编译产生的资源id映射为

```
int color colorAccent 0x7f040026
int color colorAccentBBBBB 0x7f040057
int color colorPrimary 0x7f040027
int color colorPrimaryDark 0x7f040028
```

可以看到colorAccent，colorPrimary和colorPrimaryDark的资源id并没有因为colorAccentBBBBB的插入而发生变化，而是保持了原有的资源id，而新增的资源colorAccentBBBBB则是重新分配了一个新的资源id。

至此，基本可以确定该方案是可行的（但不保证有没有坑）


### 适配aapt和aapt2

因此，需要进行aapt的版本判断，适配不同的情况，这里我已经把代码写好了，基本上就是对上面两段代码的组合，其中aapt版本的获取需要捕获一下异常，该函数在低版本中不存在，具体实现看代码，这里不再过多解释了

```
apply plugin: PublicPlugin

class PublicPlugin implements Plugin<Project> {
    void apply(Project project) {
        project.afterEvaluate {
            if (project.plugins.hasPlugin("com.android.application")) {
                def android = project.extensions.getByName("android")
                android.applicationVariants.all { def variant ->
                    boolean aapt2Enable = false

                    def processResourcesTask = project.tasks.getByName("process${variant.name.capitalize()}Resources")
                    if (processResourcesTask) {
                        try {
                            //判断aapt2是否开启，低版本不存在这个方法，因此需要捕获异常
                            aapt2Enable = processResourcesTask.isAapt2Enabled()
                        } catch (Exception e) {
                            project.logger.error "${e.getMessage()}"
                        }

                        def aaptOptions = processResourcesTask.aaptOptions
                        //aapt2开启走此流程
                        if (aapt2Enable) {
                            project.logger.error "aapt2 is enabled"
                            File publicTxtFile = project.rootProject.file('public.txt')
                            //public文件存在，则应用，不存在则生成
                            if (publicTxtFile.exists()) {
                                project.logger.error "${publicTxtFile} exists, apply it."
                                //aapt2添加--stable-ids参数应用
                                aaptOptions.additionalParameters("--stable-ids", "${publicTxtFile}")
                            } else {
                                project.logger.error "${publicTxtFile} not exists, generate it."
                                //aapt2添加--emit-ids参数生成
                                aaptOptions.additionalParameters("--emit-ids", "${publicTxtFile}")
                            }
                        } else {
                            //aapt2禁用走此流程
                            project.logger.error "aapt2 is disabled"
                            File publicXmlFile = project.rootProject.file('public.xml')
                            //public文件存在则应用，不存在则生成
                            if (publicXmlFile.exists()) {
                                //aapt的应用需要将文件拷贝到对应的目录
                                //aapt public.xml文件的应用并不是只是拷贝public.xml文件那么简单，还要根据生成的public.xml生成ids.xml文件，并将ids.xml中与values.xml中重复定义的id去除
                                String mergeResourcesTaskName = variant.variantData.getScope().getMergeResourcesTask().name
                                def mergeResourcesTask = project.tasks.getByName(mergeResourcesTaskName)
                                if (mergeResourcesTask) {
                                    mergeResourcesTask.doLast {
                                        //拷贝public.xml文件
                                        File toDir = new File(mergeResourcesTask.outputDir, "values")
                                        project.copy {
                                            project.logger.error "${variant.name}:copy from ${publicXmlFile.getAbsolutePath()} to ${toDir}/public.xml"
                                            from(publicXmlFile.getParentFile()) {
                                                include "public.xml"
                                                rename "public.xml", "public.xml"
                                            }
                                            into(toDir)
                                        }
                                        //生成ids.xml文件
                                        File valuesFile = new File(toDir, "values.xml")
                                        File idsFile = new File(toDir, "ids.xml")
                                        if (valuesFile.exists() && publicXmlFile.exists()) {
                                            //记录在values.xml中存在的id定义
                                            def valuesNodes = new XmlParser().parse(valuesFile)
                                            Set<String> existIdItems = new HashSet<String>()
                                            valuesNodes.each {
                                                if ("id".equalsIgnoreCase("${it.@type}")) {
                                                    existIdItems.add("${it.@name}")
                                                }
                                            }
                                            GFileUtils.deleteQuietly(idsFile)
                                            GFileUtils.touch(idsFile)

                                            idsFile.append("<?xml version=\"1.0\" encoding=\"utf-8\"?>")
                                            idsFile.append("\n")
                                            idsFile.append("<resources>")
                                            idsFile.append("\n")

                                            def publicXMLNodes = new XmlParser().parse(publicXmlFile)
                                            publicXMLNodes.each {
                                                //获取public.xml中定义的id类型item
                                                if ("id".equalsIgnoreCase("${it.@type}")) {
                                                    //如果在values.xml中没有定义，则添加到ids.xml中
                                                    //如果已经在values.xml中定义，则忽略它
                                                    if (!existIdItems.contains("${it.@name}")) {
                                                        idsFile.append("\t<item type=\"id\" name=\"${it.@name}\" />\n")
                                                    } else {
                                                        project.logger.error "already exist id item ${it.@name}, ignore it"
                                                    }
                                                }
                                            }
                                            idsFile.append("</resources>")
                                        }
                                    }
                                }
                            } else {
                                //不存在则生成
                                project.logger.error "${publicXmlFile} not exists, generate it"
                                //aapt 添加-P参数生成
                                aaptOptions.additionalParameters("-P", "${publicXmlFile}")
                            }
                        }
                    }
                }
            }
        }
    }
}


```

### 另一种解决方式

如果项目确定使用的是aapt2，并且不想通过编写插件解决，这里提供一种更加简单的方式，就是直接利用aaptOptions参数进行指定，但是这种方式不好做aapt和aapt2之间的无缝适配，只适合aapt2，参考代码如下

```
android {
    aaptOptions {
        File publicTxtFile = project.rootProject.file('public.txt')
        if (publicTxtFile.exists()) {
            additionalParameters "--stable-ids", "${project.rootProject.file('public.txt').absolutePath}"
        } else {
            additionalParameters "--emit-ids", "${project.rootProject.file('public.txt').absolutePath}"
        }
    }
}
```

### public.xml到public.txt的转换

如果之前是用aapt备份下来的public.xml，如果现在使用了aapt2，则需要将文件进行转换，转换方式也很简单，如下

```
task convertPublicXmlToPublicTxt() {
    doLast {
        //源public.xml
        File publicXmlFile = project.rootProject.file('backup/public.xml')
        //目标public.txt
        File publicTxtFile = project.rootProject.file('backup/generate_public.txt')
        //包名
        String applicationId = "io.github.lizhangqu.aapt2"
        GFileUtils.deleteQuietly(publicTxtFile)
        GFileUtils.touch(publicTxtFile)
        def nodes = new XmlParser().parse(publicXmlFile)
        nodes.each {
            project.logger.error "${it}"
            publicTxtFile.append("${applicationId}:${it.@type}/${it.@name} = ${it.@id}\n")
        }
    }
}
```

执行 gradle convertPublicXmlToPublicTxt即可完成转换。

值得注意的是，这种转换方式，由于原先aapt导出的public.xml中没有styleable的定义，所以转换后的public.txt中也没有styleable，即转换后的数据是aapt2导出的数据的子集，而aapt2生成的public.txt是具有styleable类型的id的，但是实际应用过程中并没有发现什么大的问题，因此几乎可以忽略不计。如果你发现有问题，可以及时联系我。


### 意外的收获aapt2资源分区

在寻找解决aapt2资源id固定的过程中，意外发现aapt2自带了资源PP段分区功能。就是通过--package-id参数，指定PP段分区，但是值得注意的是这个值必须大于0x7f，经过测试，大于0x7f的PP段分区在Android7.0以下是无法识别的，可以安装但是启动会崩溃。因此通过这种方式分区生成的apk文件，只能安装在Android7.0以上的系统，比较鸡肋。示例代码如下

```
android {
    aaptOptions {
        additionalParameters "--package-id", "0x80"
    }
}
```

此时生成的apk的资源PP段都是0x80，可以通过app/build/intermediates/res/symbol-table-with-package/debug/package-aware-r.txt文件进行验证。

### 总结

当上帝为你关上一扇门的时候，还会用门夹你的脑袋（开个玩笑），虽然public.xml在aapt2中无法用了，但是google在aapt2中提供给我们的--stable-ids和--emit-ids两个参数不见得那么不好用，甚至比aapt的public.xml还要好用，只需要生成和应用就好了，不需要进行中间的处理过程。简直完美！但是该方案还没有用足够多的case进行验证，不代表没有坑，出了坑，不负责！
