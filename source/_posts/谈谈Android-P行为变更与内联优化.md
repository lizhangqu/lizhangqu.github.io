title: 谈谈Android P行为变更与内联优化
date: 2019-04-03 09:11:21
categories: [Android]
tags: [Android, 内联优化]
---

最近遇到了几个问题，与Android P行为变更与内联优化相关，并且基本都是在OnePlus 5/5T/6/6T H2O 9.0.1上可复现。

<!-- more -->

### Android P行为变更

从Android P开始，Apache HttpClient将被弃用，对于采用非标准ClassLoader的场景下，会产生影响，比如热修复，插件化。

对于Target<9.0的应用来说，org.apache.http.legacy.boot.jar将从bootclasspath中移除，移除后该jar文件将被添加到App的ClassLoader，即PathClassLoader的pathList中去，注意此时插入到的是pathList的dexElements的最前面，如图所示：

![oneplus_less_than_p.png](oneplus_less_than_p.png)

如果采用的是标准ClassLoader加载，那么此项变动对于Target<9.0的应用几乎没有什么影响，但是如果采用非标准ClassLoader加载，如热修复，那么此项修改加上Android 9.0的内联优化变动，将会导致应用有abort的风险。

对于Target>=9.0的应用来说，org.apache.http.legacy.boot.jar从bootclasspath移除后，并且不会再添加到App的ClassLoader中，如图所示：

![pixel_p.png](pixel_p.png)

令人十分惊讶的是，一加的9.0系统，竟然不遵循Android P行为变更，对于Target>=9.0的应用，org.apache.http.legacy.boot.jar虽然从bootclasspath中移除了，但是它还是将其加到了App的ClassLoader中去，但是此时是加到pathList的dexElements的最后面，而不是最前面，如图所示：

![oneplus_bigger_than_p.png](oneplus_bigger_than_p.png)

也就是说对于Target>=9.0的应用来说，如果使用了org.apache.http.legacy.boot.jar中的类，那么在类查找过程中会抛出NoClassDefFoundError的异常，当然了，由于一加还是将其加到了App的ClassLoader中去，所以并不会有问题，但是对于其他非一加手机来说，一旦我们使用了其中的类，就会产生crash，如图所示：

![crash.png](crash.png)

对于Target>=9.0的应用来说，如果想继续使用org.apache.http.legacy.boot.jar中的类，可以在AndroidManifest.xml中加入如下声明

```
<uses-library android:name="org.apache.http.legacy" android:required="false"/>
```

需要注意的是，对于minSdkVersion<=23的应用来说，需要加上 android:required="false"属性，因为在API级别低于24的设备上，org.apache.http.legacy库不可用，该库中的类全部在bootclasspath中提供。如果不设置该属性值为false（默认是true），那么在API级别低于24的设备上安装App时，将会出现如下错误

```
Failure [INSTALL_FAILED_MISSING_SHARED_LIBRARY]
```

对于Android 9.0系统来说，这样添加之后，org.apache.http.legacy.boot.jar中的类和App的类则都是由App的PathClassLoader加载，即表现和Target<=9.0是一致的，org.apache.http.legacy.boot.jar将被添加到PathClassLoader中pathList的dexElements的最前面

有趣的是，你会发现，这样添加了之后，在Android Q上，实际上org.apache.http.legacy.boot.jar中的类是由另一个PathClassLoader加载，而不是App的PathClassLoader，但是他们的parent都是BootClassLoader，如图所示，是同一个上下文中的两个ClassLoader的截图，可以看到其哈希值是不同的。

![appclassloader.png](appclassloader.png)
![apacheclassloader.png](apacheclassloader.png)


Andorid 9.0的此项行为变更也就意味着，我们每次创建PathClassLoader对象时，org.apache.http.legacy.boot.jar都会随之添加到PathClassLoader中pathList的dexElements中去，那么就意味着可能存在多个ClassLoader加载org.apache.http.legacy.boot.jar中的类。

### Android P内联优化新增检测项

Google在Android P中添加了新的检测项，对国内大多数应用造成了严重影响：在调用resolve inline method时，如果检测到caller与callee处于不同的dex file，会主动发起abort（inline不允许跨dex文件），导致应用出现闪退等异常问题。

主要有两个场景
 - 应用原始apk中的dex A和从应用服务端下载的热修复dex B存在重复类，触发热修复且系统后台优化inline编译后，便会出现此问题。
 - 由 classloader A 加载的 class1 调用一个由 classloader B 加载的 class2里的某个 inline 方法，将导致应用闪退。

我们可以用如下命令强制触发内联

```
adb shell cmd package compile –m speed –f 包名
```

如果控制台出现如下日志，基本就是内联新增检测项导致的

```
This must be due to duplicate classes or playing wrongly with class loaders
```

具体代码见 [entrypoint_utils-inl.h#94](https://android.googlesource.com/platform/art/+/android-9.0.0_r16/runtime/entrypoints/entrypoint_utils-inl.h#94)

详情可以参考 [https://mp.weixin.qq.com/s?__biz=MzI0MjgxMjU0Mg==&mid=2247488357&idx=1&sn=d393bd028dfbf87998b80e06ca24bc94&scene=21#wechat_redirect](https://mp.weixin.qq.com/s?__biz=MzI0MjgxMjU0Mg==&mid=2247488357&idx=1&sn=d393bd028dfbf87998b80e06ca24bc94&scene=21#wechat_redirect)


### 内联条件

 - App不是Debug版本的
 - App不是使用vmSafeMode=true启动的
 - 被调用的方法所在的类与调用者所在的类位于同一个Dex；（注意，符合Class N命名规则的多个Dex要看成同一个Dex）
 - 被调用的方法的字节码条数不超过dex2oat通过--inline-max-code-units指定的值，6.x默认为100，7.x默认为32；
 - 被调用的方法不含try块；
 - 被调用的方法不含非法字节码；
 - 对于7.x版本，被调用方法还不能包含对接口方法的调用。（invoke-interface指令）

具体可以参考 [ART下的方法内联策略及其对Android热修复方案的影响分析](https://github.com/WeMobileDev/article/blob/master/ART%E4%B8%8B%E7%9A%84%E6%96%B9%E6%B3%95%E5%86%85%E8%81%94%E7%AD%96%E7%95%A5%E5%8F%8A%E5%85%B6%E5%AF%B9Android%E7%83%AD%E4%BF%AE%E5%A4%8D%E6%96%B9%E6%A1%88%E7%9A%84%E5%BD%B1%E5%93%8D%E5%88%86%E6%9E%90.md)

这里我们只需要知道如下几个概念即可：
 - 如果想要方法不被内联，我们可以强制加上try块，使其不被内联
 - 如果一个问题在debug模式下不会出现，在release情况下出现了，并且排除了混淆的原因，且出现了native异常，可以适当考虑一下内联导致的
 - 如果一个问题在vmSafeMode=true下不会出现，在vmSafeMode=false情况下出现了，且出现了native异常，可以适当考虑一下内联导致的

### 场景再现

很久之前，我们线上报出了一个一加9.0系统的内联问题，该问题只会存在于一加5/5T/6/6T的H2OS系统版本的9.0.1以下版本，并且debug版本不存在该问题，vmSafeMode=true时不存在该问题，并且只有下发patch后才会触发，具体表现是启动就crash，原因大致如下：

 - 由于反射替换application时没有将loader类和非loader隔离干净，错误的将一部分本应属于非loader类配置成loader类，导致原本应该隔离干净的类变成了未隔离干净。
 - 由于未隔离干净，导致loader类中的类A调用了非loader中的类B，强制执行内联编译后，部分方法被内联优化。
 - 下发热修复后，patch包中不会包含loader类，loader中的类由原有classloader从安装的apk中加载，非loader类由patch的classloader加载，出现了内联优化的方法调用分散在不同的classloader中，即由 classloader A 加载的 class1 调用一个由 classloader B 加载的 class2里的某个 inline 方法，将触发上述代码导致应用闪退。

奇怪的是，一加的H2OS在9.0.2之后修复了该问题，从AOSP源码上来看，这个问题应该是9.0必现的，但是后续版本一加可能去掉了这部分代码，才没出现问题。


最近我们又发现了因为apache httpclient内联优化导致的问题，具体表现是启动几次App后，出现内联abort触发native异常导致App ANR无响应。

该问题源自我们的插件化方案的classloader架构，我们使用的是多classloader方式，如图所示：

![classloader.png](classloader.png)

通过修改类的父子关系成功地把DispatchClassLoader插入到类的加载链中，DispatchClassLoader本身并不负责真正类的加载，只是类加载的一个分发器，DispatchClassLoader持有宿主及所有Bundle的ClassLoader。

特别注意，这里DispatchClassLoader和BundleClassLoader都是直接继承自ClassLoader类。

DispatchClassLoader的类查找逻辑如下
 - 先调用super.loadClass进行加载，如果找到则返回，如果没有找到，则执行下一步
 - 再从App的PathClassLoader中查找，如果找到，则返回，如果没找到，则执行下一步
 - 遍历各个插件，从插件BundleClassLoader中查找类，如果找到，则返回，如果没有找到，抛异常

BundleClassLoader的类查找逻辑如下
 - 先调用自身持有的DexFile进行查找，如果找到，则返回，如果找不到，则执行下一步
 - 再调用系统的BootClassLoader进行加载，如果找到则返回，如果没有找到，则执行下一步
 - 再从App的PathClassLoader中查找，如果找到，则返回，如果没有找到，抛异常
 - 遍历各个插件，从插件BundleClassLoader中查找类

从某个版本开始，我们将DispatchClassLoader的继承关系进行了修改，由直接继承ClassLoader修改成了继承PathClassLoader

原来的版本如下
```
public class DispatchClassLoader extends ClassLoader {
    private DispatchClassLoader(Context context) {
    }
}
```

修改后的版本如下

```
public class DispatchClassLoader extends PathClassLoader {
    private DispatchClassLoader(Context context) {
        super("", context.getClassLoader().getParent());
    }
}
```


为什么要做此项修改可以参考头条的技术博客 [Android自定义ClassLoader耗时问题追查
](https://www.jianshu.com/p/422454c1bf40) 

正是因为这项修改，从此埋下了一个坑。

我们来回顾一下Android 9.0的行为变更，一旦继承了PathClassLoader后，那么DispatchClassLoader中就会存在org.apache.http.legacy.boot.jar。

如果我们的app中用了apache httpclient的类，插件中也用了apache httpclient的类，并且一部分类由app的PathClassLoader加载，一部分类由DispatchClassLoader中的org.apache.http.legacy.boot.jar加载，并且内联了，那么就会出现问题。

假设我们现在在宿主中加载org.apache.http.message.AbstractHttpMessage类，根据类查找逻辑，会有如下几步
 - 会先调用DispatchClassLoader的super.loadClass，即PathClassLoader的loadClass
 - PathClassLoader会先从BootClassLoader中加载，此时org.apache.http.legacy.boot.jar已经从bootclasspath中移除，所以找不到
 - 再从PathClassLoader中的pathList查找，此时org.apache.http.legacy.boot.jar存在，找到对应类返回

所以org.apache.http.message.AbstractHttpMessage将会被DispatchClassLoader继承的PathClassLoader加载，而非宿主的PathClassLoader加载


此时，如果插件中加载了org.apache.http.message.BasicHttpResponse类，根据类查找逻辑，会有如下几步
 - 由于插件的BundleClassLoader自身持有的DexFile不存在该类，所以插件中找不到该类
 - 接着再从系统的BootClassLoader中查找，此时org.apache.http.legacy.boot.jar已经从bootclasspath中移除，所以找不到
 - 再从App的ClassLoader中加载，此时org.apache.http.legacy.boot.jar存在，找到对应类返回

所以org.apache.http.message.BasicHttpResponse将会被App的ClassLoader加载，即宿主原来被DispatchClassLoader替换的PathClassLoader加载

值得注意的是，这两个类都是由PathClassLoader加载，但是来自不同的PathClassLoader。

如果此时org.apache.http.message.BasicHttpResponse内联了org.apache.http.message.AbstractHttpMessage类，那么就会出现如上所说的问题。

最终就会出现如下异常，从而触发abort信号量，强制退出应用。

```
Inlined method resolution crossed dex file boundary: 
from void org.apache.http.message.BasicHttpResponse.<init>(org.apache.http.StatusLine, org.apache.http.ReasonPhraseCatalog, java.util.Locale) 
in /system/framework/org.apache.http.legacy.boot.jar/0xe73a3f80 
to void org.apache.http.message.AbstractHttpMessage.<init>() 
in /system/framework/org.apache.http.legacy.boot.jar/0xe73a56b0. 
This must be due to duplicate classes or playing wrongly with class loaders
```

这个问题修复其实也很简单，主要有两种方法
 - 把DispatchClassLoader的继承关系由PathClassLoader改回ClassLoader，但是出于性能考虑，不这么做
 - 对于apache httpclient中的类，统一从App的PathClassLoader中进行加载

方法二只需要在DispatchClassLoader的loadClass方法查找逻辑的最前面加入如下代码即可。

```
if (Build.VERSION.SDK_INT >= 28 && (
            className.startsWith("org.apache.commons.codec.") ||
                    className.startsWith("org.apache.commons.logging.") ||
                    className.startsWith("org.apache.http.")
    )) {
        // Android 9.0行为变更，apache httpclient从bootclasspath移除，放到了App ClassLoader
        // 避免出现各种问题，此处apache httpclient相关类最好从同一个ClassLoader中查找，因此优先从宿主ClassLoader中查找
        // TODO 这里做从App的PathClassLoader加载
    }
```


我们可以看到，在Tinker中针对该问题也做了修复操作，见提交 [[tinker] bugfix: crash leads by conflicts of org.apache.http library.](https://github.com/Tencent/tinker/commit/edddb2564de4d3d616c4d41fb5cc620daf946dcf)，其提交内容如下

```
 else if (name != null && name.startsWith("org.apache.http.")) {
    // Here's the whole story:
    //   Some app use apache wrapper library to access Apache utilities. Classes in apache wrapper
    //   library may be conflict with those preloaded in BootClassLoader.
    //   So with the build option:
    //       useLibrary 'org.apache.http.legacy'
    //   appears, the Android Framework will inject a jar called 'org.apache.http.legacy.boot.jar'
    //   in front of the path of user's apk. After that, PathList in app's PathClassLoader should
    //   look like this:
    //       ["/system/framework/org.apache.http.legacy.boot.jar", "path-to-user-apk", "path-to-other-preload-jar"]
    //   When app runs to the code refer to Apache classes, the referred classes in the first
    //   jar override those in user's app, which avoids any conflicts and crashes.
    //
    //   When it comes to Tinker, to block the cached instances in class table of app's
    //   PathClassLoader we use this AndroidNClassLoader to replace the original PathClassLoader.
    //   At the beginning it's fine to imitate system's behavior and construct the PathList in AndroidNClassLoader
    //   like below:
    //       ["/system/framework/org.apache.http.legacy.boot.jar", "path-to-new-dexes", "path-to-other-preload-jar"]
    //   However, the ART VM of Android P adds a new feature that checks whether the inlined class is loaded by the same
    //   ClassLoader that loads the callsite's class. If any Apache classes is inlined in old dex(oat), after we replacing
    //   the App's ClassLoader we will receive an assert since the Apache classes is loaded by another ClassLoader now.
    return originClassLoader.loadClass(name);
}
```

但是不幸的是org.apache.http.legacy.boot.jar中的包名不仅仅是org.apache.http.，还有org.apache.commons.codec.和org.apache.commons.logging.，因此这个修改并不完整，应该要把else if修改成如下逻辑

```
else if (name != null &&  (name.startsWith("org.apache.commons.codec.") 
                                     || name.startsWith("org.apache.commons.logging.")
                                     || name.startsWith("org.apache.http.")))
```


org.apache.http.legacy.boot.jar的包结构参考如下

![apache_jar.png](apache_jar.png)

Flurry是国外一家专门为移动应用提供数据统计和分析的公司，他们的SDK中也用了apache httpclient中的类，并且该SDK也触发了这个内联条件，即org.apache.http包下的类内联了org.apache.commons.logging下的类，对应的错误如下

![apache_inline.png](apache_inline.png)


腾讯全家桶SDK中也大量的使用了apache httpclient中的类，如X5，微信支付，微信分享等等SDK，支付宝的支付SDK，银联的银联支付SDK都大量的使用了这些API。

### 思考

前面说到，Target>=9.0时，在Android Q上，实际上org.apache.http.legacy.boot.jar中的类是由另一个PathClassLoader加载，而不是App的PathClassLoader，但是他们的parent都是BootClassLoader，所以正常来说，在Android Q上，类查找逻辑还是需要再进行一番变化，具体可以等Android Q release后再看下。


### apache httpclient 类检测

所以杜绝此类问题的根本解决方法是不用热修复，不用插件化，这显然短期内是不可能的，虽然我们支持零成本降级插件化为aar进行集成，但是考虑到动态性，目前还是会继续使用。所以退而求其次的方法就是移除apache httpclient的类调用，所以必须检测出哪些SDK使用了apache httpclient中的类，这里用gradle插件结合javassist写了个插件，有兴趣可以见 [https://github.com/lizhangqu/plugin-apache-httpclient-detect](https://github.com/lizhangqu/plugin-apache-httpclient-detect)

核心代码如下

```
private Map<String, ClassPool> classPoolMap = new HashMap<>()
private ClassPool apacheLegacyClassPool
@Override
void accept(String variantName, String path, InputStream inputStream, OutputStream outputStream) {
    ClassPool classPool = classPoolMap.get(variantName)
    if (classPool == null) {
        classPool = new ClassPool(true)
        TransformHelper.updateClassPath(classPool, project, variantName)
        classPoolMap.put(variantName, classPool)
    }

    if (apacheLegacyClassPool == null) {
        File apacheJarFile = getApacheLegacyJarFile()
        project.logger.info("insertClassPath org.apache.http.legacy.jar ${apacheJarFile}")
        if (apacheJarFile != null) {
            apacheLegacyClassPool = new ClassPool()
            apacheLegacyClassPool.insertClassPath(apacheJarFile.getAbsolutePath())
        }
    }

    if (apacheLegacyClassPool == null) {
        return
    }

    CtClass ctClass = classPool.makeClass(inputStream, false)
    if (ctClass.isFrozen()) {
        ctClass.defrost()
    }

    detect(path, ctClass)

    TransformHelper.copy(new ByteArrayInputStream(ctClass.toBytecode()), outputStream)
}

@SuppressWarnings("GrMethodMayBeStatic")
File getApacheLegacyJarFile() {
    String jarPath = "jar/org.apache.http.legacy.jar"
    try {
        //对应路径如果存在，则直接返回
        URL url = ApacheHttpClientDetectPlugin.class.getClassLoader().getResource(jarPath)
        if (url != null) {
            File apacheJarFile = new File(url.getFile())
            if (apacheJarFile.isFile() && apacheJarFile.exists()) {
                return apacheJarFile
            }
            //取jar包中的文件
            URL jarUrl = ApacheHttpClientDetectPlugin.class.getProtectionDomain().getCodeSource().getLocation()
            if (jarUrl != null) {
                File jarFile = new File(jarUrl.getFile())
                File jarFolder = new File(jarFile.getParentFile(),
                        FilenameUtils.getBaseName(jarFile.getName()))
                GFileUtils.mkdirs(jarFolder)
                apacheJarFile = new File(jarFolder, "org.apache.http.legacy.jar")
                GFileUtils.mkdirs(apacheJarFile.getParentFile())
                if (apacheJarFile.isFile() && apacheJarFile.exists()) {
                    return apacheJarFile
                }
                //否则解压
                ZipUtil.unpackEntry(jarFile, jarPath, apacheJarFile)
                return apacheJarFile
            }
        }
    } catch (Exception e) {
        e.printStackTrace()
    }
    return null
}

@SuppressWarnings("GrMethodMayBeStatic")
boolean isApacheLegacy(String name) {
    if (name == null) {
        return false
    }
    if (name.startsWith('org.apache.http.')) {
        return true
    }
    if (name.startsWith('org.apache.commons.codec')) {
        return true
    }
    if (name.startsWith('org.apache.commons.logging')) {
        return true
    }
    if (name.startsWith('com.android.internal.http.multipart')) {
        return true
    }
    if (name.startsWith('android.net.compatibility')) {
        return true
    }
    if (name.startsWith('android.net.http')) {
        if (name.startsWith('android.net.http.HttpResponseCache')) {
            return false
        }
        if (name.startsWith('android.net.http.SslCertificate')) {
            return false
        }
        if (name.startsWith('android.net.http.SslError')) {
            return false
        }
        if (name.startsWith('android.net.http.X509TrustManagerExtensions')) {
            return false
        }
        return true
    }
    return false
}

void detect(String path, CtClass ctClass) {
	try {
	    ctClass?.getRefClasses()?.each { String name ->
	        if (!isApacheLegacy(name)) {
	            return
	        }
	        if (apacheLegacyClassPool?.getOrNull(name) != null) {
	            project.logger.error("----------------------------------------Class Reference Start----------------------------------------")
	            project.logger.error("Apache HttpClient Class Reference: ")
	            project.logger.error("        └> [Class: ${name}]")
	            project.logger.error("        └> [Referenced By Class: ${path.replaceAll('/', '.')}]")
	            project.logger.error("----------------------------------------Class Reference End------------------------------------------\n\n")
	        }
	    }
	 	ctClass?.getDeclaredFields()?.each { CtField ctField ->
		    CtClass fieldClass = null
		    try {
		        fieldClass = ctField.getType()
		    } catch (NotFoundException e) {

		    }
		    if (fieldClass == null) {
		        return
		    }
		    if (!isApacheLegacy(fieldClass.getName())) {
		        return
		    }
		    if (fieldClass.isPrimitive()) {
		        return
		    }
		    if (fieldClass.isArray() && fieldClass.getComponentType().isPrimitive()) {
		        return
		    }
		    if (apacheLegacyClassPool?.getOrNull(fieldClass.getName()) != null) {
		        project.logger.error("----------------------------------------Field Reference Start----------------------------------------")
		        project.logger.error("Apache HttpClient Field Reference: ")
		        project.logger.error("        └> [Class: ${fieldClass.getName()}]")
		        project.logger.error("        └> [Filed: ${ctField.getName()}]")
		        project.logger.error("        └> [Referenced By Class: ${path.replaceAll('/', '.')}]")
		        project.logger.error("----------------------------------------Field Reference End------------------------------------------\n\n")
		    }
		}
    	ctClass?.getDeclaredMethods()?.each {
	        it.instrument(new ExprEditor() {
	            @Override
	            void edit(MethodCall methodCall) throws CannotCompileException {
	                super.edit(methodCall)
	                if (!isApacheLegacy(methodCall.className)) {
	                    return
	                }
	                CtClass clazz = apacheLegacyClassPool?.getOrNull(methodCall.className)
	                if (clazz == null) {
	                    return
	                }
	                if (clazz.isPrimitive()) {
	                    return
	                }
	                if (clazz.isArray() && clazz.getComponentType().isPrimitive()) {
	                    return
	                }
	                project.logger.error("----------------------------------------Method Reference Start----------------------------------------")
	                project.logger.error("Apache HttpClient Method Reference: ")
	                project.logger.error("        └> [Class: ${methodCall.getClassName()}]")
	                project.logger.error("        └> [Method: ${methodCall.getMethodName()}${methodCall.getSignature()}]")
	                project.logger.error("        └> [Referenced By Class: ${path.replaceAll('/', '.')}, Line: ${methodCall.getLineNumber()}]")
	                project.logger.error("----------------------------------------Method Reference End------------------------------------------\n\n")
	            }
	        })
    	}
	} catch (Exception e) {
    	e.printStackTrace()
	}
}
```


### 总结

珍爱生命，远离插件化，远离热修复。