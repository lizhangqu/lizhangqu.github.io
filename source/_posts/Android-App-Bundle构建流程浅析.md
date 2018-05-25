title: Android App Bundle构建流程浅析
date: 2018-05-25 15:22:50
categories: [Android]
tags: [gradle, android, aab, bundle]
---

2018 I/O大会上，Google推出了一种名为Android App Bundle的东西，借助Spilt Apk机制来完成动态加载，大家都称Android App Bundle为动态化框架，其实这是错误的，或许可以将其称为一个基于ProtoBuffer格式的序列化和反序列化框架，且它是一个zip包。而且它本身并不支持动态化，只是动态化的一个载体文件，真正实现逻辑并不是它。

<!-- more -->

bundle文件的后缀是aab，bundle文件的spilt分包策略，可以通过android.bundle的dsl定义进行配置，主要有三个维度，abi, density和language，配置如下：

```
android {
    bundle {
        abi {
            enableSplit = true
        }
        density {
            enableSplit = true
        }
        language {
            enableSplit = true
        }

    }
}
```

从bundle文件中可以生成apk文件，这里会有一个apks后缀的文件，用于存储生成各种apk的一个zip压缩包。

参与bundle打包和生成apk的任务主要有三个，PerModuleBundleTask（应该是PreModuleBundleTask，拼写错误导致变成了Per，此任务用于预先生成一个用于生成bundle包的zip文件）, BundleTask（此任务用于生成bundle文件）, BundleToApkTask（此任务用于从bunldle文件中生成apks文件，此文件也是一个zip文件，里面有n个apk文件）。

首先来看下PerModuleBundleTask，该任务将需要的文件压缩成一个base.zip文件，压缩规则如下：

1, 将assets文件压入zip根目录的assets目录下
2, 将资源文件压入zip根目录下res目录，其中AndroidManifest.xml文件，会被压入根目录下的manifest目录下，resources.pb文件会被压入根目录
3, 将dex文件压入zip根目录下的dex目录
4, 将动态库压入zip根目录下的lib目录下
5, 将java resources文件压入zip文件根目录下的root目录中


最终产生一个base.zip文件，该文件位于build/intermediates/module_bundle/\$flavorType/\$buildType/build\$flavorType\$buildTypePreBundle/out/base.zip

如下图所示
![base_zip.png](base_zip.png)

文件内容如图所示
![base_zip_content.png](base_zip_content.png)

再来看看各文件的来源

1, assets文件来自mergeAsstes任务，值得注意的是，从3.2.0开始，此目录从build/intermediates/assets修改为build/intermediates/merged_assets，且大部分的任务的输出命名规则发生了变化，假设build/intermediates/merged_assets是其根目录，则这个目录下跟随着flavorType目录，buildType目录，任务名的目录，接着跟着一个out文件夹，out下就是最终产物，如下图所示

![merge_assets.png](merge_assets.png)

2，dex文件没什么好说的，来自transform产生的dex文件
3，java resources文件和dex一样，来自transform产生的java resources文件
4，动态库也是和dex一样，来自transform产生的动态库文件

2，3，4来源文件如下图所示
![transform.png](transform.png)

5, 资源文件来自bundleResources任务，其实现类为com.android.build.gradle.internal.res.LinkAndroidResForBundleTask，和processResources任务的简单区别就是该任务link产生的resource文件是基于proto buffer格式的，aapt的link参数多了**--proto-format**参数，其产物文件如下图所示

![link_res.png](link_res.png)

可以看出该task输出的产物的命名规则和mergeAssets任务是类似的

该文件中的内容如下图所示

![bundle_ap.png](bundle_ap.png)

值得注意的是，这些文件都不是最终编译产生的Andorid资源文件，其实际内容都是proto buffer格式的，必须进行再次转换才是最终的资源文件。

以上文件，组成了base.zip文件，即buildPreBundle任务的输出文件

接下来看packageBundle任务，其实现类为com.android.build.gradle.internal.tasks.BundleTask，该任务会产生一个bundle.aab文件，其产物目录为
![bundle_out.png](bundle_out.png)

这个任务其实非常简单，将三个spilt维度封装成一个SplitsConfig，将bundle打包的一些配置封装成bundleConfig，也就是最终bundle里的BundleConfig.pb文件，调用bundletool的BuildBundleCommand类进行生成bundle文件，文件生成后，调用JarSigner对bundle文件进行签名，这里需要注意的是必须是JarSigner而不是ApkSigner，具体原因未知，google这么说的。

至于bundletool怎么生成bundle文件的，有兴趣自己去看，https://github.com/google/bundletool/blob/master/src/main/java/com/android/tools/build/bundletool/commands/BuildBundleCommand.java

最终生成的文件内容如下

![aab_content.png](aab_content.png)

可以看到和base.zip文件的区别就是把base.zip文件中的文件都扔到了base目录下，并且多了一个BundleConfig.pb文件，以及多了一个native.pb和assets.pb文件，也就是说其实BuildBundleCommand就是干了zip包文件的拷贝，生成三个pb文件的活，并做了一些文件校验上的活，没有什么技术含量。

最后看下google play怎么根据bundle文件生成apk文件的，这一步是重点。gradle插件里模拟生成apk的任务是makeApkFromBundle，其实现类为com.android.build.gradle.internal.tasks.BundleToApkTask

如果你去看这个类，其实并没有什么东西，它做的工作就是获取工程的签名文件和生成的bundle文件作为参数，将其传入bundletool中的BuildApksCommand类进行生成。具体实现有兴趣的自己去看https://github.com/google/bundletool/blob/master/src/main/java/com/android/tools/build/bundletool/commands/BuildApksCommand.java

该类就是根据分包规则，生成一系列的apk文件，包含完整的apk，也包含base.apk，同时也会包含一些不同维度的spilt包，取决于自己配置的分包策略，具体的生成步骤就是一个反序列化的步骤，需要aapt2的参与，也就是调用aapt2的convert命令，将proto buffer格式的资源文件，生成android可以使用的最终的二进制资源文件。

convert的相关代码如下图所示：
![convert.png](convert.png)

BundleToApkTask任务产生的文件如下图所示:

![apks.png](apks.png)

其实bundletool还有很多command，有兴趣见 https://github.com/google/bundletool/tree/master/src/main/java/com/android/tools/build/bundletool/commands


不知道大家有没有注意到一个问题，就是bundle.aab文件生成后，android gradle plugin会将其进行签名，然后用户要将其上传到google play上，由google play去生成用户安装所需的各种apk文件，那么这些生成的apk文件的签名怎么办，其实这个签名需要开发者主动上传到google play，由google play对apk签名文件进行完全托管，并对生成的apk文件进行签名，详情见 https://support.google.com/googleplay/android-developer/answer/7384423?hl=zh-Hans

也就是说，其实这件事情，google是最大的流氓，掌握了我们的app签名，有什么事情不能做的？甚至我可以将其总结为：把源代码托管到google play，由google play帮你编译代码，进行apk的下发工作，是不是更屌！！！并且整个过程，bundletool干了所有核心的事情，所以如果要深入了解的话，建议看下代码，见 https://github.com/google/bundletool