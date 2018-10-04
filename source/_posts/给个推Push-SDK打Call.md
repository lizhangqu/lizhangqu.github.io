title: 给个推Push SDK打Call
date: 2018-10-04 21:54:55
categories: [Android]
tags: [Android, Javassist, Gradle]
---

个推Push SDK 2.12.5.0初始化函数中会调用boolean com.igexin.push.util.a.b(Context context);函数。

该方法对libgetuiext3.so做了存在性校验，但是插件化后，对应动态库不在原始目录上，校验失败，导致个推不初始化，push功能异常。

之所以会校验失败，是因为插件化后该动态库位于/data/data/packageName/app_plugins/pluginName/pluginVersion/lib/libgetuiext3.so目录下，不在常规目录下

 <!-- more -->

对应校验方法如下：

```
public static boolean b(Context var0) {
    File var1 = new File(var0.getApplicationInfo().nativeLibraryDir, "libgetuiext3.so");
    if (!var1.exists()) {
        String var2 = "libgetuiext3.so not found in path: " + var1.getAbsolutePath();
        if ((var0.getApplicationInfo().flags & 2) != 0) {
            (new Handler(Looper.getMainLooper())).post(new com.igexin.push.util.b(var0, var2));
        }
 
        Log.e(a, var2);
    }
 
    return var1.exists();
}
```

个推初始化函数中调用了该校验方法，并且校验失败后直接return

```
public <T extends Service> void initialize(Context var1, Class<T> var2) {
    try {
        String var3 = var1.getApplicationContext().getPackageName();
        String var4 = com.igexin.push.util.a.a(var1);
        if (var4 != null && (var4.contains("gtsync") || var4.contains("gtdms"))) {
            com.igexin.b.a.c.b.a("PushManager|init by default = " + var4);
            return;
        }
 
        if (!com.igexin.push.util.a.a("PushManager", var1, var2)) {
            com.igexin.b.a.c.b.a("PushManager|init checkServiceSetCorrectly false");
            return;
        }
 
        //文件校验不通过，拒绝初始化
        if (!com.igexin.push.util.a.b(var1)) {
            return;
        }
 
        Class var5;
        if (var2 != null && !com.igexin.push.core.a.n.equals(var2.getName())) {
            var5 = var2;
        } else {
            var5 = PushService.class;
        }
 
        Intent var6 = new Intent(var1.getApplicationContext(), var5);
        var6.putExtra("action", PushConsts.ACTION_SERVICE_INITIALIZE);
        var6.putExtra("op_app", var3);
        var6.putExtra("us", var5.getName());
        if (this.f != null) {
            var6.putExtra("uis", this.f);
        }
 
        if (this.g != null) {
            var6.putExtra("ua", this.g);
        }
 
        var1.getApplicationContext().startService(var6);
        this.e = var5;
    } catch (Throwable var7) {
        com.igexin.b.a.c.b.a("PushManager|initialize|" + var7.toString());
    }
 
}
```

虽然会进行该校验，但是实际加载的so其实还是由我们插件化的框架控制，加载的真正的文件是插件目录下的so，因此，只要绕过上述存在性校验即可。

目前共有几种解决方案，但都不完美：

1、让个推打一个定制版，去掉so路径校验。忽略此方案，依赖个推。
2、在宿主中放一个空的同名so文件，此方案虽然可行，但是会在宿主莫名其妙的多一个空文件存在，并不完美，作为备选方案。
3、编译期利用AOP进行环绕通知切除，修改方法返回值。此方案虽然可行，但是对于买家版来说会额外引入AspectJ依赖，不考虑。


最终采取方法3进行实行，既不依赖个推，又可以解决问题。

接着就是编写一个脚本，使用javassist将该校验方法进行修改，强制返回true即可。

```
project.afterEvaluate {
        project.tasks.create("hackPushSDK") {
            setGroup("push")
            doLast {
                //指向个推aar文件
                File aar = new File("/path/to/sdk-2.12.5.0.aar")
                ClassPool classPool = new ClassPool(true);
 
                File jar = new File(aar.getParentFile(), aar.getName() + ".jar")
                File classFile = new File(aar.getParentFile(), aar.getName() + ".class")
                File destAar = new File(aar.getParentFile(), aar.getName() + ".aar")
 
                GFileUtils.deleteQuietly(jar)
                GFileUtils.mkdirs(jar.getParentFile())
 
                GFileUtils.deleteQuietly(classFile)
                GFileUtils.mkdirs(classFile.getParentFile())
 
                GFileUtils.deleteQuietly(destAar)
                GFileUtils.mkdirs(destAar.getParentFile())
 
                //提取aar中的classes.jar进行预处理
                ZipUtil.unpackEntry(aar, "classes.jar", jar)
                //此目录替换成自己电脑上的目录
                classPool.insertClassPath("/Users/lizhangqu/AndroidSDK/platforms/android-26/android.jar")
                classPool.insertClassPath(jar.getAbsolutePath())
 
                //获取需要修改的类
                def ctClass = classPool.getCtClass("com.igexin.push.util.a")
                def contextCtClass = classPool.getCtClass("android.content.Context")
 
                //获取需要修改的函数
                def ctMethod = ctClass.getDeclaredMethod("b", [contextCtClass] as CtClass[])
                //将该方法的返回值修改为true
                ctMethod.setBody("{return true;}")
 
                //替换classes.jar中该文件
                ZipUtil.replaceEntry(jar, "com/igexin/push/util/a.class", ctClass.toBytecode())
 
                GFileUtils.copyFile(aar, destAar)
 
                //替换aar中的classes.jar为处理后的文件
                ZipUtil.replaceEntry(destAar, "classes.jar", jar)
 
            }
        }
    }
}
```

将修改完成后的aar发布到私服上，引用修改后的aar即可。