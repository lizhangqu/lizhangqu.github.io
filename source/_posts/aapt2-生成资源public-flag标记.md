title: aapt2 生成资源public flag标记
date: 2018-02-02 11:54:51
categories: [Android]
tags: [Android, aapt2, 资源public flag]
---

 ### 前言


之前写过一篇[aapt2适配之资源id固定](/2017/11/15/aapt2%E9%80%82%E9%85%8D%E4%B9%8B%E8%B5%84%E6%BA%90id%E5%9B%BA%E5%AE%9A/)，该文章介绍了如何使用aapt2固定资源id，其实这篇文章是对该文章的一点补充，主要介绍如何在固定id的同时，将该资源进行导出，打上public标记，供其他资源进行引用。整个问题的解决方案断断续续差不多思考了一个来月，现将解决方法简单介绍一下。

<!-- more -->

 ### 从aapt2资源id固定说起


首先来回顾一下aapt2如何将资源id符号表导出，使用--emit-ids参数指定导出文件即可

```
android {
    aaptOptions {
        additionalParameters "--emit-ids", "${project.file('public.txt')}"
    }
}
```

以及符号表导出后，如何使用导出的符号表进行资源id的固定，使用--stable-ids参数，指定导入文件即可

```
android {
    aaptOptions {
        additionalParameters "--stable-ids", "${project.file('public.txt')}"
    }
}
```

执行./gradlew assembleDebug编译后，看下产出的resources\_debug.ap_文件，看下arsc中对应的资源是否打上了PUBLIC导出标记

```
aapt2 dump ./app/build/intermediates/res/resources-debug.ap_
```

执行命令后输出如下内容

```
Package name=io.github.lizhangqu.aapt2 id=7f

  type layout id=1 entryCount=1
    spec resource 0x7f010090 io.github.lizhangqu.aapt2:layout/activity_main
      () (file) res/layout/activity_main.xml

  type style id=2 entryCount=1
    spec resource 0x7f020080 io.github.lizhangqu.aapt2:style/AppTheme
      () (style)
```

可以看出，arsc中对应的资源并没有打上PUBLIC标记。问题就出在这，我们明明指定了导入资源符号表，为什么没有PUBLIC标记呢？


 ### 从aapt public.xml说起


回顾一下aapt是如何添加PUBLIC标记的，其实这事和android gradle plugin有关，在android gradle plugin 1.3以下的版本，我们可以直接往src/main/res/values目录下添加public.xml文件，该文件会自动参与编译，但是不幸的是在1.3以上版本，所有public类型的资源全都会被android gradle plugin过滤掉，因此正常的途径我们是无法让public.xml参与编译的。

所以在aapt的时候，我们在在mergeResources任务最后，将public.xml文件拷贝到build目录下merge完毕的res目录下，即build/intermediates/res/merged/目录，然后gradle在执行processResources任务时会将我们拷贝进去的文件与其他资源文件一同参与编译，于是就可以为那些资源打上PUBLIC标记，并进行id的固定。

那么在aapt2中，由于aapt2提供了一种固定资源id的方式，最开始，个人以为这种方式和aapt的public.xml作用是一样的，在经过严格的测试后发现其实并不是想象的那么简单，它只是固定资源id的一种方式，但是并不包括添加资源PUBLIC标记，因此aapt2的public.txt不等于aapt的public.xml，在aapt2中如果要添加PUBLIC标记，其实还是得另寻其他途径。

通过查看aapt2的源码发现，资源是否属于public类型，在资源文件compile为flat文件的时候就已经决定了，也就是说必须主动声明public类型的资源，这个资源才会被打上PUBLIC标记，所以问题就变成了和aapt一样，只要在mergeResource任务的最后，将public.xml拷贝到mergeResource任务的输出文件夹即可。但是有一个棘手的问题，就是aapt2的mergeResource任务的输出文件不是原始资源文件，而是经过编译后的flat文件，所以最终的问题变成了如何将public.xml文件编译为flat文件。

由于最开始没有想到这种方式，一直纠结于怎么修改aapt2的源码，来达到添加PUBLIC标记的效果，后来不经意间想到这种方式，发现之前想复杂了。这个问题其实非常简单，只需要获取aapt2可执行文件，自己调用一下compile命令，传递相关参数执行下资源编译步骤，然后将编译后的文件拷贝到mergeResource任务的输出文件夹，参考这篇文章[aapt2资源compile过程](/2017/10/31/aapt2%E8%B5%84%E6%BA%90compile%E8%BF%87%E7%A8%8B/)可以获得aapt2资源编译的命令行参数及使用方式。那么gradle代码怎么实现呢？也很简单

```
project.afterEvaluate {
    def android = project.getExtensions().findByName('android')
    android.getApplicationVariants().all { def variant ->

        def mergeResourceTask = project.tasks.findByName("merge${variant.getName().capitalize()}Resources")
        if (mergeResourceTask) {
            mergeResourceTask.doLast {
                def variantData = variant.getMetaClass().getProperty(variant, 'variantData')
                def mBuildToolInfo = variantData.getScope().getGlobalScope().getAndroidBuilder().getTargetInfo().getBuildTools()
                //buildTools下的所有可执行文件都在这个map里
                Map<BuildToolInfo.PathId, String> mPaths = mBuildToolInfo.getMetaClass().getProperty(mBuildToolInfo, "mPaths") as Map<BuildToolInfo.PathId, String>

                project.exec(new Action<ExecSpec>() {
                    @Override
                    void execute(ExecSpec execSpec) {
                    	//拼接aapt2 compile参数
                        execSpec.executable "${mPaths.get(BuildToolInfo.PathId.AAPT2)}"
                        execSpec.args("compile")
                        execSpec.args("--legacy")
                        execSpec.args("-o")
                        execSpec.args("${mergeResourceTask.outputDir}")
                        execSpec.args("${project.file('src/main/res/values/public.xml')}")
                    }
                })
            }
        }
    }
}
```

然后将public.xml放在app/src/main/res/values/目录下，编译一下，然后用aapt2 dump命令查看一下产出的arsc文件

```
Package name=io.github.lizhangqu.aapt2 id=7f

  type layout id=1 entryCount=1
    spec resource 0x7f010090 io.github.lizhangqu.aapt2:layout/activity_main PUBLIC
      () (file) res/layout/activity_main.xml

  type style id=2 entryCount=1
    spec resource 0x7f020080 io.github.lizhangqu.aapt2:style/AppTheme PUBLIC
      () (style)
```

可以看到，资源名后面多了一个PUBLIC字符，也就是说该资源被打上PUBLIC标记了，对于其他项目中的资源，可以在aapt2链接的时候直接使用-I参数引用该arsc，就和android.jar的引用是一样的，使用@包名:资源类型/资源名进行引用，如

```
@io.github.lizhangqu.aapt2:style/AppTheme
```

到这里为止，其实已经解决了PUBLIC标记的问题，但是还不够完美


 ### 自动转换public.txt文件为public.xml文件


上面虽然解决了PUBLIC标记的问题，但是还得自己维护app/src/main/res/values/public.xml文件，由于aapt2自己会导出一份public.txt文件，因此可以利用这份文件，在编译过程中将其自动转为public.xml文件，就不需要我们自己维护public.xml文件。

这个问题其实说简单也很简单，只是有一些细节需要处理

 - public.txt中存在styleable类型资源，public.xml中不存在，因此转换过程中如果遇到styleable类型，需要忽略
 - vector矢量图资源如果存在内部资源，也需要忽略，在aapt2中，它的名字是以\$开头，然后是主资源名，紧跟着\_\_数字递增索引，这些资源外部是无法引用到的，只需要固定id，不需要添加PUBLIC标记，并且\$符号在public.xml中是非法的，因此忽略它即可
 - 由于aapt2有资源id的固定方式，因此转换过程中可直接丢掉id，简单声明即可
 - aapt2编译的public.xml文件的上级目录必须是values文件夹，否则编译过程会报非法路径


所以整个过程就变成了读取public.txt的每一行，正则匹配资源类型，资源名，资源id，如果是内部资源和styleable类型资源，直接无视，否则写入public.xml文件，写入只需要写入资源类型和资源名即可，资源id按需选择，所以最终的代码抽象为如下函数

```
/**
 * 转换publicTxt为publicXml
 */
@SuppressWarnings("GrMethodMayBeStatic")
void convertPublicTxtToPublicXml(File publicTxtFile, File publicXmlFile, boolean withId) {
    if (publicTxtFile == null || publicXmlFile == null || !publicTxtFile.exists() || !publicTxtFile.isFile()) {
        throw new GradleException("publicTxtFile ${publicTxtFile} is not exist or not a file")
    }

    GFileUtils.deleteQuietly(publicXmlFile)
    GFileUtils.mkdirs(publicXmlFile.getParentFile())
    GFileUtils.touch(publicXmlFile)

    project.logger.info "convert publicTxtFile ${publicTxtFile} to publicXmlFile ${publicXmlFile}"

    publicXmlFile.append("<!-- AUTO-GENERATED FILE.  DO NOT MODIFY -->")
    publicXmlFile.append("\n")
    publicXmlFile.append("<resources>")
    publicXmlFile.append("\n")
    Pattern linePattern = Pattern.compile(".*?:(.*?)/(.*?)\\s+=\\s+(.*?)")

    publicTxtFile.eachLine { def line ->
        Matcher matcher = linePattern.matcher(line)
        if (matcher.matches() && matcher.groupCount() == 3) {
            String resType = matcher.group(1)
            String resName = matcher.group(2)
            if (resName.startsWith('$')) {
                project.logger.info "ignore to public res ${resName} because it's a nested resource"
            } else if (resType.equalsIgnoreCase("styleable")) {
                project.logger.info "ignore to public res ${resName} because it's a styleable resource"
            } else {
                if (withId) {
                    publicXmlFile.append("\t<public type=\"${resType}\" name=\"${resName}\" id=\"${matcher.group(3)}\" />\n")
                } else {
                    publicXmlFile.append("\t<public type=\"${resType}\" name=\"${resName}\" />\n")
                }

            }
        }
    }

    publicXmlFile.append("</resources>")
}
```


最开始的那段代码就可以优化为如下代码

```
project.afterEvaluate {
    def android = project.getExtensions().findByName('android')
    android.getApplicationVariants().all { def variant ->

        def mergeResourceTask = project.tasks.findByName("merge${variant.getName().capitalize()}Resources")
        if (mergeResourceTask) {
            mergeResourceTask.doLast {
            	//目标转换文件，注意public.xml上级目录必须带values目录，否则aapt2执行时会报非法文件路径
                File publicXmlFile = new File(project.buildDir, "intermediates/res/public/${variant.getDirName()}/values/public.xml")
                //转换public.txt文件为publicXml文件
                convertPublicTxtToPublicXml(project.file('public.txt'), publicXmlFile, false)

                def variantData = variant.getMetaClass().getProperty(variant, 'variantData')
                def mBuildToolInfo = variantData.getScope().getGlobalScope().getAndroidBuilder().getTargetInfo().getBuildTools()
                Map<BuildToolInfo.PathId, String> mPaths = mBuildToolInfo.getMetaClass().getProperty(mBuildToolInfo, "mPaths") as Map<BuildToolInfo.PathId, String>

                project.exec(new Action<ExecSpec>() {
                    @Override
                    void execute(ExecSpec execSpec) {
                        execSpec.executable "${mPaths.get(BuildToolInfo.PathId.AAPT2)}"
                        execSpec.args("compile")
                        execSpec.args("--legacy")
                        execSpec.args("-o")
                        execSpec.args("${mergeResourceTask.outputDir}")
                        execSpec.args("${publicXmlFile}")
                    }
                })
            }
        }
    }
}
```

### 总结

  有时候，解决问题一种思路行不通可以换一种方式，说不定就会柳暗花明呢!

