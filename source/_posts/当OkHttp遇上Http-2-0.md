title: 当OkHttp遇上Http 2.0
date: 2018-04-16 12:47:25
categories: [Android]
tags: [Android, Http/2.0, OkHttp, timeout, endless]
---

 最近遇到了一个奇葩的问题，有个别用户反馈App上的菊花一直在转消失不掉，当时产生了几个猜想：

  1、dns解析出问题了
  2、服务端有问题
  3、哪里超时了
  4、哪里死循环了

 一开始以为是偶然，结果短短一天内，有好几个用户反馈有这个问题，所以这绝对不是偶然，一定是有一个条件触发了这个bug。

 <!-- more -->

 由于我们自己调度了dns，所以一开始我们以为是httpdns的问题，但是通过简单的日志分析，发现其实并不是httpdns的问题，因为httpdns返回的解析结果和localdns的结果是完全一致的。所以基本排除了dns解析出问题了这个可能。

 然后开始怀疑服务端有问题，但是通过发布系统查看发布记录，这几天并没有发过，唯一的一个改变就是运维切换了公网出口IP，但是通过httpdns日志已经排除了dns的问题，因此也不是这个问题。

 在毫无头绪的时候，我们打了一个日志充足的包，让有问题的用户安装，结果很让人意外，竟然是网络库中的回调没有回来。于是去查看网络库的错误埋点日志，结果更让人意外，**该APP一天内有150w的timeout**，究竟是什么导致了这么大量的timeout呢？所以一开始直接把锅丢给了timeout，可是后来一想有点不对劲，哪里不对劲呢？

  1、我们有两个App，该App一天有150w的timeout， 但是另一个App只有1w的timeout，这两个App有什么不同呢？不同的地方只有okhttp的版本，150w的timeout的App用的okhttp版本是3.4.1，另一个1w的timeout的App用的okhttp版本是3.9.1
  2、timeout只会超时，超时时间到了还是会回调到error里，最终菊花会消失，但是现在的情况是回调没有进来。

 于是排除了timeout的可能，**但timeout的量过大，这绝对也是个问题**，至于为什么这么大，以及怎么解决，后面再细说。

 由于用户频繁遇到了这个问题，考虑到可能是okhttp的bug，于是将okhttp升到3.9.1重新给用户一个新包，神奇的是用户没有再反馈这个问题了。所以基本断定是okhttp的bug了。

 那么问题到底出在哪呢，通过对okhttp的issue的搜索，基本断定是3.4.1该版本的bug，通过查看changelog发现了猫腻

```
Version 3.4.2
2016-11-03

Fix: Recover gracefully when an HTTP/2 connection is shutdown.
We had a bug where shutdown HTTP/2 connections were considered usable.
This caused infinite loops when calls attempted to recover.

Version 3.4.1
2016-07-10

Fix a major bug in encoding HTTP headers.
In 3.4.0 and 3.4.0-RC1 OkHttp had an off-by-one bug in our HPACK encoder.
This bug could have caused the wrong headers to be emitted after a sequence of HTTP/2 requests! 
Everyone who is using OkHttp 3.4.0 or 3.4.0-RC1 should upgrade for this bug fix.
 ```

 官方发布过一个3.4.2的版本，修复okhttp在http2.0下使用了被关闭的连接，导致出现无限死循环。

 如Changlog所说，这个问题是修复http2.0的，而我们已经全站https了，并且已经很久了，从App的反馈信息上来看，已经有95+%的请求是Http 2.0的了，基本符合这一条件。所以问题基本定位在了哪里出现了死循环了，最终导致回调没有回来。

 问题找到了，那么怎么复现呢？这是个很头疼的问题，在完全抓瞎的情况下，我复现了一个礼拜，结果依旧没有复现出来。在一个偶然的情况下，突然复现出了一个死循环，但是完全是不知道怎么复现出来的，但是可以肯定，肯定是会出现死循环的。

 在毫无头绪的情况下，把okhttp相关的issue都浏览了一遍，突然脑洞大开。既然是修复已关闭连接被错误使用，那么只要制造出一个已经建立连接然后将其意外关闭，但是不让okhttp知道它关闭了不就好了，那么怎么复现这个场景呢，其实很简单，如下：

    1. 使用http2.0协议跟url建立连接，但是不关闭它
    2. 断网
    3. 联网
    4. 再次向url建立连接，这时候会错误复用已关闭连接
    5. 死循环出现

 为了验证我的猜想，简单写了一个demo用于复现，我们先来看一段神奇的网络请求代码

```
 final OkHttpClient httpClient = new OkHttpClient.Builder()
        .followRedirects(false) //为了制造非200状态码，禁止302跳转
        .protocols(Collections.unmodifiableList(Arrays.asList(Protocol.HTTP_1_1, Protocol.HTTP_2)))//启用http2.0协议
        .addNetworkInterceptor(new Interceptor() {
            @Override
            public Response intercept(Chain chain) throws IOException {
                Request request = chain.request();

                try {
                    Connection connection = chain.connection();
                    if (connection != null) {
                        Route route = connection.route();
                        //为了判断死循环，打印路由信息
                        Log.e("TAG", "x-route:" + route.socketAddress().toString() + "");
                    }
                } catch (Throwable e) {
                    e.printStackTrace();
                }
                return chain.proceed(request);
            }
        })
        .build();

 public String getResult(final String url) {
        Request request = new Request.Builder()
                .url(url)
                .method("GET", null)
                .build();
        ResponseBody responseBody = null;
        String result = null;
        try {
            Response response = httpClient.newCall(request).execute();
            if (response.code() == 200) {
                responseBody = response.body();
                result = responseBody.string();
            }
            Log.e("TAG", "Successful-> protocol:" + response.protocol() + " code:" + response.code());
            return result;
        } catch (Exception e) {
            e.printStackTrace();
            Log.e("TAG", "Unsuccessful-> ", e);
        } finally {
            if (responseBody != null) {
                try {
                    responseBody.close();
                } catch (Exception e) {
                    e.printStackTrace();
                }
            }
        }
        return null;
    }
 ```


 简单看上面的getResult函数，其功能是向对应url发送一个get请求，并且禁止了302跳转，启用了Http2.0协议，在拦截器中打印了路由信息，在状态码为200的时候，返回了结果，完全没有毛病。**其实这个函数存在了一个致命的问题，刚好触发了okhttp的这个bug，那就是在http code!=200的时候，responseBody没有关闭**。

让我们一起来复现一下这个问题：

1、 首先开启网络
2、 发送一个http code返回非200的请求，导致流没有被关闭

```
new Thread(new Runnable() {
    @Override
    public void run() {
        //会出现http code 302，导致连接未关闭
        getResult("https://h5.weidian.com/");
    }
}).start();
```
3、 关闭网络，如进入飞行模式
4、 开启网络，如退出飞行模式
5、 发送一个http code 返回200的请求

```
new Thread(new Runnable() {
    @Override
    public void run() {
        //会出现http code 200
        getResult("https://h5.weidian.com/m/weidian-buyer/error/index.html");
    }
}).start();
```
6、 开始上演死循环悲剧，如图所示
![loop.png](loop.png)

很完美的复现出了这个死循环问题，为什么会产生死循环呢？通过查看okhttp的代码发现，okhttp代码有太多的while(true)了，一不小心就break不了陷入死循环。比如在拦截器里随便抛一个IOException，随随便便死循环，3.3.0之后的版本全部中招，包括最新版3.10.0。

```
//仅供演示，请勿模仿
//.addNetworkInterceptor(new Interceptor() {
//    @Override
//    public Response intercept(Chain chain) throws IOException {
//        throw new IOException("mock io exception");
//    }
//})
```

在RetryAndFollowUpInterceptor中有这么一段代码

```

public final class RetryAndFollowUpInterceptor implements Interceptor {
 
  @Override public Response intercept(Chain chain) throws IOException {
    //....省略n行代码
    while (true) {
      
      //....省略n行代码
      Response response = null;
      boolean releaseConnection = true;
      try {
      	//复用已关闭连接，出现IOException("shutdown")
        response = ((RealInterceptorChain) chain).proceed(request, streamAllocation, null, null);
        releaseConnection = false;
      } catch (RouteException e) {
        // The attempt to connect via a route failed. The request will not have been sent.
        if (!recover(e.getLastConnectException(), true, request)) throw e.getLastConnectException();
        releaseConnection = false;
        continue;
      } catch (IOException e) {
      	//异常被捕获，尝试恢复
        // An attempt to communicate with a server failed. The request may have been sent.
        if (!recover(e, false, request)) throw e;
        //如果不能恢复，抛异常，如果能恢复，进行重试
        //很不幸该场景下，这里一直返回了true
        releaseConnection = false;
        continue;
      } finally {
        // We're throwing an unchecked exception. Release any resources.
        if (releaseConnection) {
          streamAllocation.streamFailed(null);
          streamAllocation.release();
        }
      }
      //省略n行代码
    }
  }

  private boolean recover(IOException e, boolean routeException, Request userRequest) {
    streamAllocation.streamFailed(e);

    // The application layer has forbidden retries.
    if (!client.retryOnConnectionFailure()) return false;

    // We can't send the request body again.
    if (!routeException && userRequest.body() instanceof UnrepeatableRequestBody) return false;

    // This exception is fatal.
    if (!isRecoverable(e, routeException)) return false;

    // No more routes to attempt.
    if (!streamAllocation.hasMoreRoutes()) return false;

    // For failure recovery, use the same route selector with a new connection.
    return true;
  }

  private boolean isRecoverable(IOException e, boolean routeException) {
    // If there was a protocol problem, don't recover.
    if (e instanceof ProtocolException) {
      return false;
    }

    // If there was an interruption don't recover, but if there was a timeout connecting to a route
    // we should try the next route (if there is one).
    if (e instanceof InterruptedIOException) {
      return e instanceof SocketTimeoutException && routeException;
    }

    // Look for known client-side or negotiation errors that are unlikely to be fixed by trying
    // again with a different route.
    if (e instanceof SSLHandshakeException) {
      // If the problem was a CertificateException from the X509TrustManager,
      // do not retry.
      if (e.getCause() instanceof CertificateException) {
        return false;
      }
    }
    if (e instanceof SSLPeerUnverifiedException) {
      // e.g. a certificate pinning error.
      return false;
    }

    // An example of one we might want to retry with a different route is a problem connecting to a
    // proxy and would manifest as a standard IOException. Unless it is one we know we should not
    // retry, we return true and try a new route.
    return true;
  }
}

```


妈的最外层一个while(true)，在执行response = ((RealInterceptorChain) chain).proceed(request, streamAllocation, null, null);时发生了IOException("shutdown")，被捕获，然后调用recover函数尝试恢复连接，但是很不幸的是recover返回了true，而此时连接却已经被意外关闭的（断网再联网），也就是后续将复用一个已关闭的连接，悲剧的导致了无限死循环。不看不知道，一看吓一跳，除了这一处while(true)，okhttp其他地方还有很多while(true)，这要是一个不小心，就掉坑里了。

问题找到了吗？确切的说是找到了一个问题，还有很多问题没有找到，这里只是找到了一个复现场景，但是不能保证用户的复现路径是怎么样的，但至少已经验证了猜想。

那么要怎么修复这个问题呢？其实非常简单。

1、这个问题只有在Http 2.0下有问题，因为Http 2.0使用多路复用，一个域名不会建立多个connection，所有请求进行多路复用使用同一个connection，因此解决这个无限死循环的一个方法就是禁用Http 2.0，但显然是无法接受的，所以不予考虑，不过也给出OkHttp禁用http 2.0的方式

```
OkHttpClient httpClient = new OkHttpClient.Builder()
            .protocols(Collections.unmodifiableList(Arrays.asList(Protocol.HTTP_1_1)))//启用http1.1，禁用http 2.0
            .build();
```

2、okhttp在连接失败时会进行重试，从而导致了这个无限重试的悲剧，因此可以关闭失败重试的功能，但是这会降低请求成功率，也是不能接受的，所以也不予考虑，不过也给出对应代码。

```
OkHttpClient httpClient = new OkHttpClient.Builder()
            .retryOnConnectionFailure(false)
            .build()
```

3、经过测试，发现以上的无限死循环问题在okhttp [3.3.0,3.5.0]全部中招，因此可以使用3.2.0版本或者使用最新的3.10.0版本，可以从一定程度上杜绝这个问题，但是也不能保证一定不会再出现死循环，也许还有其他触发条件呢，谁也不能保证。所以升级okhttp是必要的，可以考虑。


4、既然http code!=200时流未关闭的情况下，连接意外中断触发了这个死循环，那么避免问题出现的简单有效的途径就是我管你http code为多少，统统关闭就好了，对应修改后的getResult函数如下:

```
 public String getResult(final String url) {
        Request request = new Request.Builder()
                .url(url)
                .method("GET", null)
                .build();
        Response response = null;
        String result = null;
        try {
            response = httpClient.newCall(request).execute();
            if (response.code() == 200) {
                ResponseBody responseBody = response.body();
                result = responseBody.string();
            }
            Log.e("TAG", "Successful-> protocol:" + response.protocol() + " code:" + response.code());
            return result;
        } catch (Exception e) {
            e.printStackTrace();
            Log.e("TAG", "Unsuccessful-> ", e);
        } finally {
            if (response != null) {
                try {
                    response.close();
                } catch (Exception e) {
                    e.printStackTrace();
                }
            }
        }
        return null;
    }
```

但是这只是避免了流没有关闭触发的死循环，避免不了其他条件触发的死循环，需要特别注意这一点。

bug差不多修完了，还剩下一个问题待解决，150w的timeout是从哪里来的？这个问题我没办法在现有手头上的真机复现，但是我在genymotion模拟器上复现了出来，所有我猜想必然还会存在一个机型复现出这个问题，只是目前手头上的机型没有这个问题，而这个问题的前提条件也必须是Http 2.0，复现方式也是非常简单：

 1、联网
 2、发送一个Http2.0请求建立连接，使用完后关闭连接（Http 2.0下会发送一个帧）
 3、断网
 4、联网
 5、发送Http2.0请求，超时时间到了后，会触发timeout
 6、之后发送n个请求，都不会成功，直到连接复用池中已关闭的连接被清理掉（默认5分钟，5分钟后才会有成功的请求产生）

这个问题的解决方法也比较简单：

 1、升级okhttp到最新3.10.0的版本，高版本对复用池中的连接做了严格的ping pong的验证，一定程度上可以保证被使用的连接是没有被关闭的，即使被关闭，也可以通过重试重新建立一个新的连接。

 2、捕捉SocketTimeoutException异常，清理连接池中无用连接，这个代码中稍微处理一下就好了，对应的代码如下:


```
okhttp3.Response response = null;
try {
    response = call.execute();
    //read response content
} catch (SocketTimeoutException e) {
    e.printStackTrace();
    try {
        okhttpclient.connectionPool().evictAll();
    } catch (Exception e1) {
        e1.printStackTrace();
    }
    throw e;
} catch (IOException e) {
    throw e;
} finally {
    if(response != null){
        try {
            response.close();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
```

除了这个timeout异常之外，还有一个异常也特别多，就是UnknownHostException，这个问题也可以用timeout的复现步骤复现出来，因此这个异常发生时，也最好清理一下连接池中的无用连接。

```
java.net.UnknownHostException: Unable to resolve host "your.domain.com": No address associated with hostname
```

优化后的代码如下：


```
okhttp3.Response response = null;
try {
    response = call.execute();
    //read response content
} catch (SocketTimeoutException e) {
    e.printStackTrace();
    try {
        okhttpclient.connectionPool().evictAll();
    } catch (Exception e1) {
        e1.printStackTrace();
    }
    throw e;
} catch (UnknownHostException e) {
    e.printStackTrace();
    try {
        okhttpclient.connectionPool().evictAll();
    } catch (Exception e1) {
        e1.printStackTrace();
    }
    throw e;
} catch (IOException e) {
    throw e;
} finally {
    if(response != null){
        try {
            response.close();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
```

排查了一个礼拜，最终总算把问题给解决了，也算是一身轻松了。