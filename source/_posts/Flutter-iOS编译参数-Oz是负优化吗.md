title: Flutter iOS编译参数-Oz是负优化吗
date: 2019-12-09 14:38:20
categories: [Flutter]
tags: [Flutter, Engine, Clang, iOS，瘦身]
---

2019年11月23日，字节跳动团队在其Flutter沙龙上有一个专题，[**如何缩减接近 50% 的 Flutter 包体积**](https://mp.weixin.qq.com/s/Ls3cDcqjlyOX80PXUO0wRw)，具体内容可以[**点击链接**](https://mp.weixin.qq.com/s/Ls3cDcqjlyOX80PXUO0wRw)进行查看，其中有一点提到了**优化 Engine 编译产物**，通过修改编译参数**-Os**为**-Oz**达到缩减包大小的目的。
<!-- more -->

其原文内容为：

>在 Flutter 引擎编译时，安卓和 iOS 的编译参数不同，安卓是-Oz，iOS 是-Os。如果想追求极致包体积是需要用 -Oz 的，不能用 -Os，-Oz 只是性能稍微差一点，但是基本可以忍受。为什么 iOS 性能普遍都比安卓好一点，但是为什么它反而在这个性能好的平台上反而用 -Os 呢？它其实是之前的 build tools 不统一，考虑到链接时优化的顺序问题，-Oz 反而增加了包大小。只需要升级最新的 build tools，改 -Os 为 -Oz，收益为 723.17KB，这是头条自己的数据，大家的情况可能不一样，但是这个收益是肯定有的。

关于Clang Optimization Level编译参数-Os和-Oz，可以参考：
 - [Optimization Level](https://clang.llvm.org/docs/ClangCommandLineReference.html#optimization-level)
 - [Clang optimization levels](https://stackoverflow.com/questions/15548023/clang-optimization-levels)

关于链接时优化，即LTO，全称Link Time Optimization，可以参考：
  - [LLVM Link Time Optimization](https://llvm.org/docs/LinkTimeOptimization.html)

关于Optimization Level和LTO，本篇文章不做展开，有兴趣自行查看资料。

从技术沙龙现场模糊得掉渣的视频回放可以找到对应PPT中的issue
 - [Enable LTO for Android](https://github.com/flutter/buildroot/pull/165)

如图所示
![issue.png](issue.png)

issue中提到，在iOS构建中使用-Oz编译参数实际上会增大包大小，即使Clang的文档中说到-Oz能够在-Os基础上进一步减小包大小，但是LTO链接时优化发生的内联和它并没有将-Oz考虑进去，往往会导致包大小的增大。Flutter团队过去是讨论过这一点的，但是最终没有明确的结论，因为-Oz和LTO在某种程度上是相互冲突的。

从官方的观点中可以看出，iOS中用-Oz可能还会比-Os增大包大小，那么字节跳动团队却说-Oz会比-Os减小约723.17KB的大小，到底谁才是对的呢？用实际数据说话，我们来做个实验。

首先基于**v1.9.1**版本**-Os**编译参数编译出ios_release arm64的产物

编译参数如图所示：
![os_flag.png](os_flag.png)

执行gn生成Ninja文件，使用ninja完成构建
```
./flutter/tools/gn --runtime-mode=release --ios
ninja -C out/ios_release -t clean
ninja -C out/ios_release -j 8
```
构建完成后查看Flutter产物大小
![os.png](os.png)

可以看出framework中的Flutter文件大小为**11114176字节**，约**10.60MB**

然后修改编译参数**-Os**为**-Oz**

编译参数如图所示：
![oz_flag.png](oz_flag.png)

执行gn重新生成Ninja文件，使用ninja完成构建
```
./flutter/tools/gn --runtime-mode=release --ios
ninja -C out/ios_release -t clean
ninja -C out/ios_release -j 8
```
构建完成后再查看Flutter产物大小

![oz.png](oz.png)

可以看出此时framework中的Flutter文件大小为**12613992字节**，约**12.03MB**

**12613992字节-11114176字节=1499816字节=1.43MB**

**足足增大了1.43MB**

是不是就说明Google Flutter团队的观点是对的，字节跳动的团队是错的呢？也是就-Oz带来了负优化。先不要着急下结论，一开始我也是这么认为的。

既然字节跳动团队这么说，肯定是有客观事实存在的，不然牛逼怎么能乱吹。

带着疑问，思考哪一步出错了。其实这个问题不好发现。

问题就在与我们ninja编译出来的产物，真的是我们最终使用的产物吗？

其实并不是，我们最终使用的产物是三合一架构的framework文件，即arm64, armv7, x86_64三架构的文件，该文件由src/flutter/sky/tools/create_ios_framework.py脚本完成，编译完三个架构的产物后，调用该脚本用lipo进行合成，如

```
./sky/tools/create_ios_framework.py 
--arm64-out-dir /Users/lizhangqu/software/flutter_dev/engine/src/out/ios_release \
--armv7-out-dir /Users/lizhangqu/software/flutter_dev/engine/src/out/ios_release_arm  \
--simulator-out-dir /Users/lizhangqu/software/flutter_dev/engine/src/out/ios_debug_sim \
--dst /Users/lizhangqu/software/flutter_dev/engine/src/out/universal
```

之后就会产生实际我们使用的文件，但你会发现，大小还是-Oz的比-Os的要大。

其实不然，create_ios_framework.py脚本中，还有两个参数\-\-strip和\-\-dsym

```
if args.dsym:
dsym_out = os.path.splitext(fat_framework)[0] + '.dSYM'
subprocess.check_call(['dsymutil', '-o', dsym_out, linker_out])

if args.strip:
# copy unstripped
unstripped_out = os.path.join(args.dst, 'Flutter.unstripped')
shutil.copyfile(linker_out, unstripped_out)
subprocess.check_call(["strip", "-x", "-S", linker_out])
```

\-\-dsym用于产生dSYM符号表文件
\-\-strip用于去除一些符号信息和调试信息

这两个参数的支持可以见提交 [Prepare for stripping and dsyming Flutter.framework](https://github.com/flutter/engine/pull/6247/files)，从时间节点上可以看出，要晚于 [Enable LTO for Android](https://github.com/flutter/buildroot/pull/165)

这两个参数他们的默认值都是false，也就是说我们刚才比较的大小，是未经过strip的大小。从脚本中看出strip的命令为：

```
strip -x -S /path/to/Flutter.framework/Flutter
```

我们尝试着对arm64的产物单独执行strip，再看看包大小变化。

首先是-Os编译参数下unstripped的大小和stripped的大小
![os_strip.png](os_strip.png)

此时执行strip后的Flutter文件大小为 7060528 字节，约6.73MB

再对-Oz编译参数下产生的文件执行strip
![oz_strip.png](oz_strip.png)

此时执行strip后的Flutter文件大小为 6353376 字节，约6.06MB

奇迹发生了，-Oz strip后的文件大小比-Os strip后的文件大小减少了约 7060528字节-6353376字节 = 707152字节，约等于690.58KB，和字节跳动团队说的723.17KB相近，加上其他客观因素（如版本差异），可以基本认为字节跳动团队的结论是正确的。

最终的结论：也就是说-Oz并没有带来负优化，看问题不能只看表面，如果你没有将产物strip，那么你就被表面现象欺骗了。当然是否使用-Oz进行编译取决于你对包大小和性能方面的衡量，这个需要具体场景具体分析。当然关于包大小这块，Google Flutter团队也一直在不断的努力，有兴趣可以参考 [Reduce \-\-release apk and ipa sizes](https://github.com/flutter/flutter/issues/16833)