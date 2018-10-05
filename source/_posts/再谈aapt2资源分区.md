title: 再谈aapt2资源分区
date: 2018-10-05 12:22:26
categories: [Android]
tags: [Android, aapt2, 资源分区]
---

在buildTools 28.0.0以前，aapt2自带了资源分区，通过--package-id参数指定。但是该分区只支持>0x7f的PP段，而在Android 8.0之前，是不支持>0x7f的PP段资源的，运行时会抛异常。但是当指定了一个<0x7f的PP段资源后，编译资源时却会报错

```
error: invalid package ID 0x15. Must be in the range 0x7f-0xff..
```

<!-- more -->

所以对于Android P之前使用的buildTools版本(<28.0.0)，我们必须通过修改aapt2的源码达到资源分区的目的。当然由于aapt2的源码扩展性极强，修改的代码也很简单。

目前市面上资源分区无外乎两种方式：
   - 一种是直接操作arsc二进制文件（Small，VirtualAPK，Neptune）
   - 另一种就是直接修改aapt源码（微店插件化框架，atlas，ACDD，DynamicAPK，掌阅插件化框架）

这两种方式，论维护成本，二进制修改的方式不会比修改源码的方式要低，出错程度也会相对高一点，个别场景不能完美的天然支持，如资源id固定，资源provided引用等等。所以目前性价比最高的分区方式依旧是修改aapt源码的方式。

而aapt修改方式的成本就是需要检出AOSP的代码，极其占用硬盘资源，因此之前我对其做了cmake跨平台编译的支持，只需占用约10GB的硬盘资源即可。目前已经支持到Android 9.0。详细可以参考

 - [aapt-repo-manifest](https://github.com/lizhangqu/aapt-repo-manifest)
 - [aapt-cmake-buildscript](https://github.com/lizhangqu/aapt-cmake-buildscript)

最近在更新AOSP代码到Android 9.0，发现了一些让人欣喜的修改之处，在buildTools 28.0.0之后，这一切都发生了改变。aapt2支持了<0x7f预留PP段分区的功能，只需要指定一个参数即可，我们来看下这个参数

```
--allow-reserved-package-id
```

```
Allows the use of a reserved package ID. This should on be used for packages with a pre-O min-sdk
```

也就是说，当我们通过--package-id指定PP段的时候，再指定--allow-reserved-package-id为true，即可实现<0x7f的PP段资源分区，经过测试，发现最终达到的效果和修改源码是一致的，并且可以全版本兼容运行。

此外，buildTools 28.0.0开始的aapt2还新增了一个参数

```
--warn-manifest-validation  Treat manifest validation errors as warnings.
```

这个参数有什么用呢？微店的插件化框架在AndroidManifest.xml中增加了三个自定义节点，即dependent-bundle，local-service和bridge-service，这几个节点在aapt编译时是没问题的，但是使用aapt2编译就会出现非法节点的资源编译错误。以至于当时为了适配aapt2，在插件编译期从AndroidManifest.xml中移除了这些节点，转为json文件进行存储。如果什么都不修改，编译时就会报错，对应的错误如下：

```
unexpected element `dependent-bundle` found in manifest
unexpected element `local-service` found in manifest
unexpected element `bridge-service` found in manifest
```

但是有了--warn-manifest-validation参数就不一样了，只要编译时添加该参数，就会将这些错误认为是警告，编译就不会报错。

由此可以得出一个结论，buildTools 28.0.0之前的aapt2还不够成熟，28.0.0开始的aapt2开始考虑了向下兼容性。真是着实让人欣喜。

并且从28.0.0开始的aapt2，其compile产生的flat文件格式也发生了变化，感兴趣的可以检出Android 9.0的源码研究一下。
