title: Android代理系统级HttpUrlConnection请求到第三方网络库-支持Http/2.0及HttpDNS
date: 2017-07-13 16:47:12
categories: [Android]
tags: [Android, HttpUrlConnection, URLStreamHandlerFactory]
---

### 前言

看到这个标题，好长哇（恩，好长）！分解一下：

 1. 使用原生的HttpUrlConnection请求代码.
 2. 在不改变现有代码的前提下将请求代理到第三方网络库，如OkHttp, Chromium网络栈, CURL等.
 3. 代理到第三方网络库后可以支持Http/2.0, HttpDNS等特性.

要达到怎么样的一个目的呢，无代码无fuck

```
try {
    URL url = new URL("https://www.weidian.com");
    HttpURLConnection connection = (HttpURLConnection) url.openConnection();
    connection.setRequestMethod("GET");
    connection.connect();
} catch (Exception e) {
    e.printStackTrace();
}
```

最终的目的就是使用以上代码，但是真正的请求是第三方网络库代理发出去的。

<!-- more -->

### 坑爹的Google爸爸

在Android 4.4之后，Google爸爸将Android上的HttpUrlConnection实现修改成了OkHttp，但是这个支持显得有点坑爹，它就是一个黑盒子，没有将任何控制OkHttp的属性暴露出来，其实这才是合理的，毕竟不能让开发者感知到底层的实现嘛。但是翻看AOSP的实现 [HttpsHandler.java](https://android.googlesource.com/platform/external/okhttp/+/master/android/main/java/com/squareup/okhttp/HttpsHandler.java)，会看到一段坑爹的代码

```
private static final List<Protocol> HTTP_1_1_ONLY =
            Collections.singletonList(Protocol.HTTP_1_1);
            /**
 * Creates an OkHttpClient suitable for creating {@link HttpsURLConnection} instances on
 * Android.
 */
// Visible for android.net.Network.
public static OkUrlFactory createHttpsOkUrlFactory(Proxy proxy) {
    // The HTTPS OkHttpClient is an HTTP OkHttpClient with extra configuration.
    OkUrlFactory okUrlFactory = HttpHandler.createHttpOkUrlFactory(proxy);
    // All HTTPS requests are allowed.
    okUrlFactory.setUrlFilter(null);
    OkHttpClient okHttpClient = okUrlFactory.client();
    // Only enable HTTP/1.1 (implies HTTP/1.0). Disable SPDY / HTTP/2.0.
    okHttpClient.setProtocols(HTTP_1_1_ONLY);
    okHttpClient.setConnectionSpecs(Collections.singletonList(TLS_CONNECTION_SPEC));
    // Android support certificate pinning via NetworkSecurityConfig so there is no need to
    // also expose OkHttp's mechanism. The OkHttpClient underlying https HttpsURLConnections
    // in Android should therefore always use the default certificate pinner, whose set of
    // {@code hostNamesToPin} is empty.
    okHttpClient.setCertificatePinner(CertificatePinner.DEFAULT);
    // OkHttp does not automatically honor the system-wide HostnameVerifier set with
    // HttpsURLConnection.setDefaultHostnameVerifier().
    okUrlFactory.client().setHostnameVerifier(HttpsURLConnection.getDefaultHostnameVerifier());
    // OkHttp does not automatically honor the system-wide SSLSocketFactory set with
    // HttpsURLConnection.setDefaultSSLSocketFactory().
    // See https://github.com/square/okhttp/issues/184 for details.
    okHttpClient.setSslSocketFactory(HttpsURLConnection.getDefaultSSLSocketFactory());
    return okUrlFactory;
}
```

看到**okHttpClient.setProtocols(HTTP_1_1_ONLY);**这一行，没错，对OkHttp设置了只支持Http/1.1协议，即使OkHttp支持了SPDY和Http/2.0，但是也被Google爸爸禁用了。恩，所以别以为底层替换成了OkHttp的实现，就以为OkHttp的所有特性都被继承过来了，这是大错特错的。

### 细读java.net.URL类

于是我们再去看看java.net.URL类的实现，找一找有没有其他方式，将系统级请求代理到第三方网络库上。

AOSP上的代码在[URL.java](https://android.googlesource.com/platform/libcore/+/master/ojluni/src/main/java/java/net/URL.java)

#### URL.openConnection()

首先看到openConnection方法的实现

```
public URLConnection openConnection() throws java.io.IOException {
    return handler.openConnection(this);
}
```

可以看到转交给了handler对象的openConnection，入参是this，也就是URL对象。

那么这个handler是什么东西呢，继续往下看

#### URLStreamHandler

handler其实就是URLStreamHandler对象

在URL中查找一下代码，可以看到它的构造函数中有这么一段获取handler的代码

```
if (handler == null &&
    (handler = getURLStreamHandler(protocol)) == null) {
    throw new MalformedURLException("unknown protocol: " + protocol);
}
this.handler = handler;
```

从代码中可以看到，handler就是处理某个协议的真正幕后操纵者，接着到了getURLStreamHandler方法，方法的入参就是协议，如http, http, ftp等，如果返回值是空，则当前请求会抛出一个未知协议的异常。

#### getURLStreamHandler

来看看getURLStreamHandler的真正实现部分

```
/**
 * A table of protocol handlers.
 */
static Hashtable<String,URLStreamHandler> handlers = new Hashtable<>();
private static Object streamHandlerLock = new Object();
/**
 * Returns the Stream Handler.
 * @param protocol the protocol to use
 */
static URLStreamHandler getURLStreamHandler(String protocol) {
    URLStreamHandler handler = handlers.get(protocol);
    if (handler == null) {
        boolean checkedWithFactory = false;
        // Use the factory (if any)
        if (factory != null) {
            handler = factory.createURLStreamHandler(protocol);
            checkedWithFactory = true;
        }
        // Try java protocol handler
        if (handler == null) {
            final String packagePrefixList = System.getProperty(protocolPathProp,"");
            StringTokenizer packagePrefixIter = new StringTokenizer(packagePrefixList, "|");
            while (handler == null &&
                   packagePrefixIter.hasMoreTokens()) {
                String packagePrefix = packagePrefixIter.nextToken().trim();
                try {
                    String clsName = packagePrefix + "." + protocol +
                      ".Handler";
                    Class<?> cls = null;
                    try {
                        ClassLoader cl = ClassLoader.getSystemClassLoader();
                        cls = Class.forName(clsName, true, cl);
                    } catch (ClassNotFoundException e) {
                        ClassLoader contextLoader = Thread.currentThread().getContextClassLoader();
                        if (contextLoader != null) {
                            cls = Class.forName(clsName, true, contextLoader);
                        }
                    }
                    if (cls != null) {
                        handler  =
                          (URLStreamHandler)cls.newInstance();
                    }
                } catch (ReflectiveOperationException ignored) {
                }
            }
        }
        // Fallback to built-in stream handler.
        // Makes okhttp the default http/https handler
        if (handler == null) {
            try {
                // BEGIN Android-changed
                // Use of okhttp for http and https
                // Removed unnecessary use of reflection for sun classes
                if (protocol.equals("file")) {
                    handler = new sun.net.www.protocol.file.Handler();
                } else if (protocol.equals("ftp")) {
                    handler = new sun.net.www.protocol.ftp.Handler();
                } else if (protocol.equals("jar")) {
                    handler = new sun.net.www.protocol.jar.Handler();
                } else if (protocol.equals("http")) {
                    handler = (URLStreamHandler)Class.
                        forName("com.android.okhttp.HttpHandler").newInstance();
                } else if (protocol.equals("https")) {
                    handler = (URLStreamHandler)Class.
                        forName("com.android.okhttp.HttpsHandler").newInstance();
                }
                // END Android-changed
            } catch (Exception e) {
                throw new AssertionError(e);
            }
        }
        synchronized (streamHandlerLock) {
            URLStreamHandler handler2 = null;
            // Check again with hashtable just in case another
            // thread created a handler since we last checked
            handler2 = handlers.get(protocol);
            if (handler2 != null) {
                return handler2;
            }
            // Check with factory if another thread set a
            // factory since our last check
            if (!checkedWithFactory && factory != null) {
                handler2 = factory.createURLStreamHandler(protocol);
            }
            if (handler2 != null) {
                // The handler from the factory must be given more
                // importance. Discard the default handler that
                // this thread created.
                handler = handler2;
            }
            // Insert this handler into the hashtable
            if (handler != null) {
                handlers.put(protocol, handler);
            }
        }
    }
    return handler;
}
```

 1. 首先从handlers中根据协议返回一个URLStreamHandler对象，handlers是一个静态的Hashtable<String,URLStreamHandler>，主要起到一个缓存的作用，如果获取不到，则继续下一步操作。
 2. 判断factory对象是否为空，如果不为空，则调用factory.createURLStreamHandler方法获取一个URLStreamHandler对象，如果URLStreamHandler对象不为空，则标记checkedWithFactory变量为true，用于后面检查时使用，如果返回空，则继续下一步操作
 3. 获取系统java.protocol.handler.pkgs属性，该值是JVM的启动参数，通过-D java.protocol.handler.pkgs来设置URLStreamHandler实现类的包路径，例如-D java.protocol.handler.pkgs=com.sample.protocol，代表处理实现类皆在这个包下。如果需要多个包的话，那么使用“|” 分割。比如-D java.protocol.handler.pkgs=com.sample.protocol1|com.sample.protocol2；而JDK内部默认实现类均是在sun.net.www.protocol包下。设置进去的包下的类的命名模式必须为[package_path].[protocol].Handler，比如我实现了http协议，则对应的实现类为com.sample.protocol.http.Handler，再比如我实现了https协议，则对应的实现类为com.sample.protocol.https.Handler，因为是需要用到反射，所以这些实现类必须有一个默认的构造函数。了解了这个原理之后，之后就是遍历满足条件的所有URLStreamHandler，直到找到一个对应协议的URLStreamHandler，反射构造它；如果找不到，则继续下一步操作。
 4. 如果协议是file协议，则使用默认包下的package_path.file.Handler对象，即sun.net.www.protocol.file.Handler对象
 5. 如果协议是ftp协议，则使用默认包下的package_path.ftp.Handler对象，即sun.net.www.protocol.ftp.Handler对象
 6. 如果协议是jar协议，则使用默认包下的package_path.jar.Handler对象，即sun.net.www.protocol.jar.Handler对象
 7. 如果协议是http协议，则使用com.android.okhttp.HttpHandler，注意此时OkHttp登场了，调用的方式是反射调用。对应的实现类在[HttpsHandler.java](https://android.googlesource.com/platform/external/okhttp/+/master/android/main/java/com/squareup/okhttp/HttpsHandler.java)
 8. 如果协议是https协议，则使用com.android.okhttp.HttpsHandler，也是反射调用，对应的实现类在[HttpsHandler.java](https://android.googlesource.com/platform/external/okhttp/+/master/android/main/java/com/squareup/okhttp/HttpsHandler.java)
 9. 细心的你会发现，代码中反射的是com.android.okhttp.HttpHandler和com.android.okhttp.HttpsHandler，但是AOSP上的源码却是com.squareup.okhttp.HttpHandler和com.android.okhttp.HttpsHandler，这是为什么呢，因为项目目录下存在一个叫[jarjar-rules.txt](https://android.googlesource.com/platform/external/okhttp/+/master/jarjar-rules.txt)的文件，它会将com.squareup重命名为com.android，以及将okio重命名为com.android.okhttp.okio
 10. 最后就是一个检查的过程，检查其他线程是不是创建了相关的类，首先从handlers缓存中查找，如果找到了，则直接返回，无论当前的hander是否已经创建，都直接丢弃当前的handler对象，如果找不到，则检查其他线程是不是创建了factory对象，这个前提条件是最开始时factory并没有被创建，从而避免重复创建handler。如果这时候检查的handler2不为空，则将其赋值给handler，并且将handler对象存入handlers缓存中，将hanler对象返回。

从以上代码可以很快的找到我们有两个切入点

 - 我们是否可以从构造函数中传入URLStreamHandler对象，代理所有请求
 - 我们是否可以全局代理掉URLStreamHandler的创建

对于第一个问题，查找URL构造函数可以发现，确实存在这么一个构造函数，而且还不止一个

```
public URL(String protocol, String host, int port, String file,
               URLStreamHandler handler) throws MalformedURLException {

}
public URL(URL context, String spec, URLStreamHandler handler)
        throws MalformedURLException {

}
```

但是这已经违背了我们不修改现有代码的原则了，因为我们需要修改构造URL对象的代码了，所以我们放弃它。

那么问题就到了第二个上，是否可以全局代理掉URLStreamHandler的创建，经过刚才的一番分析，不难发现，确实是有那么一个角色，负责全局代理URLStreamHandler的创建，并且其优先级是相当的高的。没错，就是factory对象及其createURLStreamHandler方法

#### URLStreamHandlerFactory

那么factory对象是怎么来的呢，它其实是一个静态变量

```
static URLStreamHandlerFactory factory;
```

默认为空，也就是说如果我们不设置，它就会一直为空，这不就是专门用于自定义用的吗！看下它的设置方法

```
public static void setURLStreamHandlerFactory(URLStreamHandlerFactory fac) {
    synchronized (streamHandlerLock) {
        if (factory != null) {
            throw new Error("factory already defined");
        }
        SecurityManager security = System.getSecurityManager();
        if (security != null) {
            security.checkSetFactory();
        }
        handlers.clear();
        factory = fac;
    }
}
```

 1. 首先会判断factory是不是null，如果不为null，则会抛出一个Error，从这里看出，factory最多仅且可以设置一次
 2. 调用handlers的clear方法，清空之前缓存的所有handler对象，这个目的是啥呢？当然是为了让设置的factory生效啦，毕竟它是高优先级的，因为可能在设置它之前，已经有一些handler被创建了，让那些已经创建的handler失效。

### 全局代理请求到OkHttp

okhttp有对httpurlconnection的支持模块，不过其已经被square废弃了，也就是将来不再维护了。不过我们还是可以使用的

引入okhttp及okhttp-httpurlconnection的模块

```
compile 'com.squareup.okhttp3:okhttp:3.8.1'
compile 'com.squareup.okhttp3:okhttp-urlconnection:3.8.1'
```

设置URLStreamHandlerFactory对象为OkUrlFactory

```
try {
    OkUrlFactory okUrlFactory = new OkUrlFactory(client);
    URL.setURLStreamHandlerFactory(okUrlFactory);
} catch(Exception e) {
    //ignore
}

```

这时候你的请求就被代理到okhttp上了。

#### 如何让OkHttp支持Http/2.0

不用设置，默认5.0以上支持，只要后端服务器支持alpn选择协议，它就能支持。

#### 如何让OkHttp支持HttpDNS

使用OkHttp的Dns接口即可

```
OkHttpClient client = new OkHttpClient.Builder()
    .dns(new Dns() {
        @Override
        public List<InetAddress> lookup(String hostname) throws UnknownHostException {
            if (httpdns) {
                return getHttpdnsByHost(hostname);
            }
            return Dns.SYSTEM.lookup(hostname);
        }
    })
    .build();
OkUrlFactory okUrlFactory = new OkUrlFactory(client);
URL.setURLStreamHandlerFactory(okUrlFactory);
```

#### 坑点

这种方式的OkHttp代理，切记不要使用任何拦截器，因为设置了也没有用，在[OkHttpURLConnection.java](https://github.com/square/okhttp/blob/master/okhttp-urlconnection/src/main/java/okhttp3/internal/huc/OkHttpURLConnection.java)中有个buildCall()方法，负责创建OkHttp的Call对象，在该方法中，会将我们设置进去的client的拦截器全部清空，如下代码

```
private Call buildCall() throws IOException {
    if (call != null) {
      return call;
    }

    //此处省略n行代码
    OkHttpClient.Builder clientBuilder = client.newBuilder();
    clientBuilder.interceptors().clear();
    clientBuilder.interceptors().add(UnexpectedException.INTERCEPTOR);
    clientBuilder.networkInterceptors().clear();
    clientBuilder.networkInterceptors().add(networkInterceptor);

    // Use a separate dispatcher so that limits aren't impacted. But use the same executor service!
    clientBuilder.dispatcher(new Dispatcher(client.dispatcher().executorService()));

    // If we're currently not using caches, make sure the engine's client doesn't have one.
    if (!getUseCaches()) {
      clientBuilder.cache(null);
    }

    return call = clientBuilder.build().newCall(request);
  }
```

所以将OkHttp的OkUrlFactory设置为URLStreamHandlerFactory时，设置的OkHttpClient不要添加任何拦截器即可，添加了也会失效，或许这就是Square比较坑的地方，和Google爸爸一样坑。



### chromium网络栈的代理

如果你的项目引用了chromium的网络栈，那么也是支持全局代理HttpUrlConnection的请求的，因为chromium也是有URLStreamHandlerFactory模块的支持，参考 [Chromium 网络栈的编译与使用](http://fucknmb.com/2017/06/12/Chromium-%E7%BD%91%E7%BB%9C%E6%A0%88%E7%9A%84%E7%BC%96%E8%AF%91%E4%B8%8E%E4%BD%BF%E7%94%A8/)

引入cronet依赖

```
compile 'io.github.lizhangqu:cronet:0.0.1'
```

设置URLStreamHandlerFactory对象为CronetURLStreamHandlerFactory

```
CronetEngine.Builder builder = new CronetEngine.Builder(context);
builder.
        enableHttpCache(CronetEngine.Builder.HTTP_CACHE_IN_MEMORY,
                100 * 1024) // cache
        .enableHttp2(true)  // Http/2.0 Supprot
        .enableQuic(true)   // Quic Supprot
        .setHostResolver(new HostResolver() {
            @Override
            public List<InetAddress> resolve(String hostname) throws UnknownHostException {
                if (hostname == null)
                    throw new UnknownHostException("hostname == null");
                if (httpdns) {
                	return getHttpdnsByHost(hostname);
            	}
                return Arrays.asList(InetAddress.getAllByName(hostname));
            }
        })                  // custom dns, you can use httpdns here
        .enableSDCH(true)   // SDCH Supprot
        .setLibraryName("cronet");  // lib so name
CronetEngine cronetEngine = builder.build();
CronetURLStreamHandlerFactory cronetURLStreamHandlerFactory = new CronetURLStreamHandlerFactory(cronetEngine);
URL.setURLStreamHandlerFactory(cronetURLStreamHandlerFactory);
```

如上代码，已经开起了http/2.0及httpdns的支持

### 总结

 此处没有总结！坑已挖，少年快去填坑吧！