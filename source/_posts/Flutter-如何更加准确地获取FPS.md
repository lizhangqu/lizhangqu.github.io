title: Flutter 如何更加准确地获取FPS
date: 2019-12-19 16:01:25
categories: [Flutter]
tags: [Flutter, FPS, 性能]
---

如果我们需要对比Flutter与Native的性能数据，那么我们就需要获取Flutter的一部分性能数据，FPS就是其中的一个衡量标准。

<!-- more -->

至于Flutter的FPS的计算方式，可以参考这篇文章，里面讲的比较细以及为什么这么计算。
 - [如何代码获取 Flutter APP 的 FPS](https://yrom.net/blog/2019/08/01/how-to-get-fps-in-flutter-app-codes/)
 - [完整代码](https://gist.github.com/yrom/ac4f30b26ee02ce3bd3a1d260bb9ffb4)

总体思路就是设置**window.onReportTimings**回调，获取每帧的数据，但这里需要注意一下，v1.9.1可以通过设置**window.onReportTimings**实现，如

```
var orginalCallback = window.onReportTimings;

window.onReportTimings = (timings) {
  if (orginalCallback != null) orginalCallback(timings);
  // ...
}
```

不过在v1.12.13上，你不能再使用这方式，你得改成如下方式

```
import 'package:flutter/scheduler.dart';

SchedulerBinding.instance.addTimingsCallback((List<FrameTiming> timings) {
   //...
});
```

设置完回调后过滤掉无效的帧数据后根据计算公式获得对应的FPS。对应的公式如下：

>FPS / 60 ≈ drawFramesCount / (drawFramesCount + droppedCount)

根据公式推导出:

>FPS ≈ 60 * drawFramesCount / (drawFramesCount + droppedCount)

假设过滤后的有效的帧数据为变量framesSet，那么
 - **drawFramesCount**则是我们绘制的帧数，这个可以直接通过framesSet.length获取
 - **droppedCount** 则是丢帧数，可以通过判断绘制的时间是否大于每帧绘制时间获取
 - 每帧绘制的时间可以用1000ms/刷新频率获取，即1000/60 ≈ 16ms

假如我们将drawFramesCount + droppedCount赋值为costCount，那么 FPS 就可以通过如下代码获取得到：

```
const frameInterval = const Duration(microseconds: Duration.microsecondsPerSecond ~/ 60);

var framesCount = framesSet.length;
var costCount = framesSet.map((t) {
    // 耗时超过 frameInterval 会导致丢帧
    return (t.totalSpan.inMicroseconds ~/ frameInterval.inMicroseconds) + 1;
  }).fold(0, (a, b)=> a + b);
double fps = framesCount * 60 / costCount;
```

这里看起来很完美，其实有个致命的问题，那就是真的每个手机的每秒绘制的最大帧数是60帧吗，也就是16ms绘制一帧，显然不是的。可以参考下如下文章

 - [新的流畅体验，90Hz 漫谈](https://zhuanlan.zhihu.com/p/66900738)
 - [Redmi K30 120Hz 流速屏](https://www.mi.com/redmik30)

可以看到，部分手机肯定不是60Hz的刷新频率，可能存在90Hz，如OnePlus 7 Pro，甚至出现了120Hz，如Redmi K30，而Flutter的目标就是在60Hz的手机上达到每秒60帧的绘制，在120Hz的手机上达到每秒120帧的绘制。如果我们上述公式写死用60进行计算，那么在这些手机上计算出来的FPS就会偏小。

所以为了让上述计算公式更准确，我们需要获取到手机屏幕的刷新频率。

通过查看Flutter Engine的源码，我们会发现Vsync的刷新频率是通过Platform的API获取到的

首先来看下Android是如何获取的

**engine/src/flutter/shell/platform/android/vsync_waiter_android.cc**
```
float VsyncWaiterAndroid::GetDisplayRefreshRate() const {
  JNIEnv* env = fml::jni::AttachCurrentThread();
  if (g_vsync_waiter_class == nullptr) {
    return kUnknownRefreshRateFPS;
  }
  jclass clazz = g_vsync_waiter_class->obj();
  if (clazz == nullptr) {
    return kUnknownRefreshRateFPS;
  }
  jfieldID fid = env->GetStaticFieldID(clazz, "refreshRateFPS", "F");
  return env->GetStaticFloatField(clazz, fid);
}
```

通过JNI调用Java类FlutterJNI的一个静态字段refreshRateFPS获取，而该字段是在VsyncWaiter类中获取到的，其代码路径为
**engine/src/flutter/shell/platform/android/io/flutter/view/VsyncWaiter.java**

```
public class VsyncWaiter {
    private static VsyncWaiter instance;

    @NonNull
    public static VsyncWaiter getInstance(@NonNull WindowManager windowManager) {
        if (instance == null) {
            instance = new VsyncWaiter(windowManager);
        }
        return instance;
    }

    @NonNull
    private final WindowManager windowManager;

    private final FlutterJNI.AsyncWaitForVsyncDelegate asyncWaitForVsyncDelegate = new FlutterJNI.AsyncWaitForVsyncDelegate() {
        @Override
        public void asyncWaitForVsync(long cookie) {
            Choreographer.getInstance().postFrameCallback(new Choreographer.FrameCallback() {
                @Override
                public void doFrame(long frameTimeNanos) {
                    float fps = windowManager.getDefaultDisplay().getRefreshRate();
                    long refreshPeriodNanos = (long) (1000000000.0 / fps);
                    FlutterJNI.nativeOnVsync(frameTimeNanos, frameTimeNanos + refreshPeriodNanos, cookie);
                }
            });
        }
    };

    private VsyncWaiter(@NonNull WindowManager windowManager) {
        this.windowManager = windowManager;
    }

    public void init() {
        FlutterJNI.setAsyncWaitForVsyncDelegate(asyncWaitForVsyncDelegate);

        // TODO(mattcarroll): look into moving FPS reporting to a plugin
        float fps = windowManager.getDefaultDisplay().getRefreshRate();
        FlutterJNI.setRefreshRateFPS(fps);
    }
}

```

从代码看出Android的屏幕刷新频率可以通过WindowManager的API获取到

```
public double getRefreshRate(Context context) {
    try {
        WindowManager windowManager = (WindowManager) context.getSystemService(Context.WINDOW_SERVICE);
        return windowManager.getDefaultDisplay().getRefreshRate();
    } catch (Exception e) {	
    }
    return 60.0;
}
```

我们再来看看iOS如何获取到屏幕刷新频率，其关键代码位于
**engine/src/flutter/shell/platform/darwin/ios/framework/Source/vsync_waiter_ios.mm**

```
- (float)displayRefreshRate {
  if (@available(iOS 10.3, *)) {
    auto preferredFPS = display_link_.get().preferredFramesPerSecond;  // iOS 10.0

    // From Docs:
    // The default value for preferredFramesPerSecond is 0. When this value is 0, the preferred
    // frame rate is equal to the maximum refresh rate of the display, as indicated by the
    // maximumFramesPerSecond property.

    if (preferredFPS != 0) {
      return preferredFPS;
    }

    return [UIScreen mainScreen].maximumFramesPerSecond;  // iOS 10.3
  } else {
    return 60.0;
  }
}
```

也就是说可以通过CADisplayLink的displayLinkWithTarget函数获取到，如下

```
- (double)displayRefreshRate:(CADisplayLink *)link {
    if (@available(iOS 10.3, *)) {
        NSInteger preferredFPS = link.preferredFramesPerSecond;  // iOS 10.0

        // From Docs:
        // The default value for preferredFramesPerSecond is 0. When this value is 0, the preferred
        // frame rate is equal to the maximum refresh rate of the display, as indicated by the
        // maximumFramesPerSecond property.

        if (preferredFPS != 0) {
            return @(preferredFPS).doubleValue;
        }

        return @([UIScreen mainScreen].maximumFramesPerSecond).doubleValue;  // iOS 10.3
    } else {
        return 60.0;
    }
}

- (void)onDisplayLink:(CADisplayLink *)link {
    NSLog(@"preferredFramesPerSecond：%lf", [self displayRefreshRate:link]);
}

- (double)getRefreshRate:(NSDictionary *)arguments {
    CADisplayLink *link = [CADisplayLink displayLinkWithTarget:self selector:@selector(onDisplayLink:)];
    return [self displayRefreshRate:link];
}
```

最后，通过channel让dart层可以调用如上函数获取到对应的屏幕刷新频率即可

**fps.dart**
```
  static const MethodChannel _channel = MethodChannel('fps_plugin');

  static Future<double> getRefreshRate() async {
    return _channel.invokeMethod("getRefreshRate");
  }
```

对应Android和iOS实现channel，调用上面的函数获取refreshRate即可

最终FPS的计算公式就会变成

```
double _refreshRate;
Duration _frameInterval;

if (_refreshRate == null) {
  _refreshRate = (await getRefreshRate()) ?? 60;
}
if (_frameInterval == null) {
  _frameInterval = Duration(
      microseconds:
          Duration.microsecondsPerSecond ~/ _refreshRate); //每帧消耗的时间，单位微秒
}

var framesCount = framesSet.length;
var costCount = framesSet.map((t) {
    // 耗时超过 _frameInterval 会导致丢帧
    return (t.totalSpan.inMicroseconds ~/ _frameInterval.inMicroseconds) + 1;
  }).fold(0, (a, b)=> a + b);
double fps = framesCount * _frameInterval / costCount;
```

改进后的方法将会在屏幕刷新频率为90Hz和120Hz的手机上更加准确。