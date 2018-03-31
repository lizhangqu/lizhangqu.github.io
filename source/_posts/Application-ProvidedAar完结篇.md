title: Application ProvidedAar完结篇
date: 2018-03-31 18:28:43
categories: [Android]
tags: [gradle, android, providedAar, maven]
---

之前写过两篇providedAar系列的文章，见：
  
  - [Android application中使用provided aar并没有那么简单](/2017/12/24/Android-application中使用provided-aar并没有那么简单/)
  - [再谈Application ProvidedAar](/2018/03/19/再谈Application-ProvidedAar/)

基本上已经完美的实现了Android Gradle Plugin [1.3.0,3.2.0+)版本com.android.application中使用provided aar的功能，支持代码和资源的引用，同时不将代码和资源编译进去，但是还遗留了最后一个比较头疼的问题，那就是configurate阶段和构建阶段会被警告日志刷屏。

<!-- more -->

具体现象如下：

![warn](warn.png)

依赖少的时候还好，但是依赖一多或者传递依赖一多，整个控制台就被这种日志刷屏了，所以必须解决一下这个问题。具体解决思路就是把这种日志的级别调整为info级别，由于正常构建不会输出info级别的日志，所以这种日志就不会刷屏了。

这个问题只有在Android Gradle Plugin 2.3.3及以下会存在，3.0.0及以上不存在这个问题，因此我们只要解决2.3.3及以下版本即可。

一开始的解决思路是利用groovy的MOP，运行期动态修改函数指向我们自己的调用，具体的伪代码如下

```
project.getLogger().getMetaClass().warn = { String msg ->
    if (msg 满足我们拦截的信息){
        originalLogger.info(msg)
        return 
    }
    调用原来的逻辑
}
```

结果发现试了n多种MOP方式，都无法完成方法替换，结论是groovy的MOP无法修改java中的代码调用，只能对groovy中的代码调用生效，而Android Gradle Plugin的代码和gradle的相关部分代码是由java实现的，因此MOP这种场景下不适用。

于是换一种思路。通过查看gradle的代码发现，我们可以拦截到具体的日志输出逻辑，相关代码如下：

```
private void log(LogLevel logLevel, Throwable throwable, String message) {
    Object buildOperationId = BuildOperationIdentifierRegistry.getCurrentOperationIdentifier();
    LogEvent logEvent = new LogEvent(clock.getCurrentTime(), name, logLevel, message, throwable, buildOperationId);
    OutputEventListener outputEventListener = context.getOutputEventListener();
    try {
        outputEventListener.onOutput(logEvent);
    } catch (Throwable e) {
        // fall back to standard out
        e.printStackTrace(System.out);
    }
}
```

可以发现最终日志输出是调用outputEventListener的onOutput函数，传递一个LogEvent携带日志相关信息进行输出的，而outputEventListener是运行期由Android Gradle Plugin设置进去的，具体的设置相关方法在logger的context中，如下：

```
public void setOutputEventListener(OutputEventListener outputEventListener) {
    this.outputEventListener.set(outputEventListener);
}

public OutputEventListener getOutputEventListener() {
    return (OutputEventListener)this.outputEventListener.get();
}
```

所以我们其实只要设置OutputEventListener对象为我们自己的对象，并且将原始的OutputEventListener对象保存起来，就可以实现日志输出逻辑的自定义，从而达到我们的效果。大致的伪代码如下：

```
org.gradle.internal.logging.slf4j.OutputEventListenerBackedLoggerContext listenerBackedLoggerContext = project.getLogger().getMetaClass().getProperty(project.getLogger(), "context")
org.gradle.internal.logging.events.OutputEventListener originalOutputEventListener = listenerBackedLoggerContext.getOutputEventListener()
org.gradle.api.logging.LogLevel originalOutputEventLevel = listenerBackedLoggerContext.getLevel()
listenerBackedLoggerContext.setOutputEventListener(new org.gradle.internal.logging.events.OutputEventListener() {
    @Override
    void onOutput(org.gradle.internal.logging.events.OutputEvent outputEvent) {
        if (msg 满足我们拦截的信息){
            修改日志级别为info并输出
            return
        }
        调用原来的逻辑
    }
})
```

但是不幸的是OutputEventListenerBackedLoggerContext，OutputEventListener和LogLevel这三个类，在不同的gradle版本中包名都不一样，除了包名，其他逻辑完全一样，这就会带来一个问题，即使进行了兼容，也无法编译成功，编译过程中必然会报类找不到，那么有没有办法解决这个问题呢。

最终的解决方法是使用def关键字和lambda表达式，这样包名相关的信息就可以完全被屏蔽了，具体的实现逻辑如下：

```
//redirect warning log to info log
def listenerBackedLoggerContext = project.getLogger().getMetaClass().getProperty(project.getLogger(), "context")
def originalOutputEventListener = listenerBackedLoggerContext.getOutputEventListener()
def originalOutputEventLevel = listenerBackedLoggerContext.getLevel()
listenerBackedLoggerContext.setOutputEventListener({ def outputEvent ->
    def logLevel = originalOutputEventLevel.name()
    if (!("QUIET".equalsIgnoreCase(logLevel) || "ERROR".equalsIgnoreCase(logLevel))) {
        if ("WARN".equals(outputEvent.getLogLevel().name())) {
            String message = outputEvent.getMessage()
            //Provided dependencies can only be jars.
            //provided dependencies can only be jars.
            if (message != null && (message.contains("Provided dependencies can only be jars.") || message.contains("provided dependencies can only be jars. "))) {
                project.logger.info(message)
                return
            }
        }
        if (originalOutputEventListener != null) {
            originalOutputEventListener.onOutput(outputEvent)
        }
    }
})
```

这就完成了日志逻辑的替换，具体思路就是获取logger context对象，拿到原始的OutputEventListener对象，然后拿到原始的日志输出级别，在日志级别大于WARN时，不会输出WARN的日志，因此只要处理日志级别小于等于WARN的情况（即不等于QUIE和ERROR），才需要进行这个逻辑处理，处理的对应报错的日志的级别是WARN的，然后判断输出的日志里面是否含有关键字Provided dependencies can only be jars，这里特别注意一下，有些版本可能Provided是小写的，即provided，当条件满足后，将日志调整为info进行输出，否则，调用原始日志输出逻辑。

于是乎，10来行代码，将控制台的刷屏日志彻底消除了，整个世界都清净了。
