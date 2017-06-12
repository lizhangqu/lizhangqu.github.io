title: Chromium 网络栈的编译与使用
date: 2017-06-12 11:15:21
categories: [Android]
tags: [Chromium, Android，Network]
---


### 前言

很久很久之前，就看到某某公司说提取了Chromium的网络栈做App的网络库，当时自己还年少不懂事，一直觉得不明觉厉，最近一周利用下班时间，学习了下GN构建工具和ninja构建工具，参考：

 - [Chromium GN构建工具的使用](http://hanpfei.github.io/2016/11/16/ChromiumGN%E6%9E%84%E5%BB%BA%E5%B7%A5%E5%85%B7%E7%9A%84%E4%BD%BF%E7%94%A8/)

感觉是时候自己编译一个Chromium的网络栈出来了。

<!-- more -->

### 编译

编译过程极其复杂，这篇文章不打算详细描述，目前，Chromium还不支持Mac上编译，因此为了编译它，特定用了沉睡了1年之久的Windows机，装了个Windows+Ubuntu双系统，就这样开始尝试编译。

编译过程中遇到了很多问题，总之，需要感谢以下几篇文章：

 - [chromium net到android平台的移植](http://hanpfei.github.io/2016/10/18/chromium-net-android-porting/)
 - [Chromium Android编译指南](http://hanpfei.github.io/2016/10/16/Chromium_Android%E7%BC%96%E8%AF%91%E6%8C%87%E5%8D%97/)
 - [懒人chromium net android移植指南](http://hanpfei.github.io/2016/11/11/lazy-chromium-net-android-porting-guide/)
 - [Chromium GN构建工具的使用](http://hanpfei.github.io/2016/11/16/ChromiumGN%E6%9E%84%E5%BB%BA%E5%B7%A5%E5%85%B7%E7%9A%84%E4%BD%BF%E7%94%A8/)

编译过程中的其他细节问题，请自行Google，也欢迎与我交流。

### 项目地址

目前我编译的Chromium网络栈已经发布成了aar，项目地址见
 - [chromium-net-for-android](https://github.com/lizhangqu/chromium-net-for-android)

### 例子

我提供了一个示例代码的工程，你可以从 [sample on Github](https://github.com/lizhangqu/chromium-net-for-android/tree/master/sample) 看到代码。

你只需要将其clone到本地，然后使用最新版本的andorid studio去编译，将其安装到你的设备上即可。


### Chromium Net 源码

我从[chromium/src/net](https://chromium.googlesource.com/chromium/src/net/+/master)上复制了一份和本库相关的Java源码，你可以从[源码 on Github](https://github.com/lizhangqu/chromium-net-for-android/tree/master/cronet-source)看到 。

当然，这份源码只是为了更方便的阅读一些Java层相关的代码，它并不能被直接编译。

### 特性

- 全平台支持最新版TLS。不像OkHttp这样依赖系统提供SSL/TLS加解密功能的网络库，chromium网络栈自身包含SSL库，因而可以全平台支持安全性更高的最新版TLS。

- 全平台支持HTTP/2及QUIC等最新的网络协议。HTTP/2本身对TLS的版本有要求，同样由于内含SSL库，而可以全平台支持HTTP/2。

- 为了尽可能的缩减so的大小，当前编译的版本并不支持FTP，WebSocket等协议，如果你需要使用它们，请自行编译它们。


### 使用

#### Maven

```
<dependency>
  <groupId>io.github.lizhangqu</groupId>
  <artifactId>cronet</artifactId>
  <version>0.0.1</version>
</dependency>
```

#### Gradle

```
compile 'io.github.lizhangqu:cronet:0.0.1'
```

#### Proguard

如果你进行了混淆，请在混淆文件中加入以下配置

```
-keep class org.chromium.** { *;}
-dontwarn org.chromium.**
```

#### NDK abi过滤

默认，此库包含了所有CPU结构的so，当然这带来的后果就是大小特别大，如果你只需要添加其中一个cpu结构的so，你可以使用abiFilters进行过滤，当然我建议只添加armeabi-v7a，毕竟它可以兼容目前市面上大多数的cpu，而armeabi的cpu目前市面上已基本看不见。

```
android {
    defaultConfig {
        ndk {
            abiFilters "armeabi-v7a"
            
//          default is no filters       
//          abiFilters "armeabi"
//          abiFilters "armeabi-v7a"
//          abiFilters "arm64-v8a"
//          abiFilters "x86"
//          abiFilters "x86_64"
//          abiFilters "mips"
//          abiFilters "mips64"
        }
    }
}
```

#### 创建Chromium 网络引擎

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
                return Arrays.asList(InetAddress.getAllByName(hostname));
            }
        })                  // custom dns, you can use httpdns here
        .enableSDCH(true)   // SDCH Supprot
        .setLibraryName("cronet");  // lib so name
CronetEngine cronetEngine = builder.build();
//see more config in the code
```

此时，你可以进行各种配置，比如自定义dns解析，在这里，你可以使用httpdns，以及可以设置支持http/2.0等特性，更多配置信息，请详见代码。


#### HttpUrlConnection的无缝使用

在OkHttp中，我们可以设置URL的URLStreamHandlerFactory为OkUrlFactory，这样，就可以在HttpUrlConnection中使用OkHttp的所有特性，就像这样：

```
URL.setURLStreamHandlerFactory(new OkUrlFactory(new OkHttpClient()));
```

Chromium的网络栈当然也支持这个：

```
CronetURLStreamHandlerFactory cronetURLStreamHandlerFactory = new CronetURLStreamHandlerFactory(cronetEngine);
URL.setURLStreamHandlerFactory(cronetURLStreamHandlerFactory);
```

然后，我们并不需要修改任何我们现有的代码，只需要像这样发送一个网络请求即可。

```
try {
     URL url = new URL(mEditTextUrl.getText().toString());
     HttpURLConnection connection = (HttpURLConnection) url.openConnection();
     Log.e("TAG", "connection:" + connection);
     connection.setDoInput(true);
     connection.setConnectTimeout(10000);
     connection.setReadTimeout(10000);
     connection.setRequestMethod("GET");
     connection.connect();
     int responseCode = connection.getResponseCode();
     InputStream inputStream = connection.getInputStream();
     ByteArrayOutputStream output = new ByteArrayOutputStream();
     copy(inputStream, output);
     output.close();
     inputStream.close();
     byte[] bytes = output.toByteArray();
     String response = new String(bytes);
     Log.e("TAG", "responseCode:" + responseCode);
     Log.e("TAG", "response body:" + response);
 } catch (IOException e) {
     e.printStackTrace();
 }
 
 public static long copy(InputStream input, OutputStream output) throws IOException {
    return copyLarge(input, output, new byte[2048]);
 }
 
 public static long copyLarge(InputStream input, OutputStream output, byte[] buffer)
        throws IOException {
    long count = 0;
    int n = 0;
    while (-1 != (n = input.read(buffer))) {
        output.write(buffer, 0, n);
        count += n;
    }
    return count;
 }

```


#### 发送一个GET请求

通过UrlRequest.Builder构建一个UrlRequest对象，然后调用start方法开始请求。

UrlRequest对象的构建需要若干个参数，其中必不可少的是前文创建的CronetEngine引擎对象，以及当前网络请求执行的线程池，当然请求的url和请求回调就更不用说了。示例代码如下：

```
UrlRequest.Builder builder = new UrlRequest.Builder(mEditTextUrl.getText().toString(), new UrlRequest.Callback() {
     private ByteArrayOutputStream mBytesReceived = new ByteArrayOutputStream();
     private WritableByteChannel mReceiveChannel = Channels.newChannel(mBytesReceived);

     @Override
     public void onRedirectReceived(UrlRequest urlRequest, UrlResponseInfo urlResponseInfo, String s) throws Exception {
         Log.i("TAG", "onRedirectReceived");
         urlRequest.followRedirect();
     }

     @Override
     public void onResponseStarted(UrlRequest urlRequest, UrlResponseInfo urlResponseInfo) throws Exception {
         Log.i("TAG", "onResponseStarted");
         urlRequest.read(ByteBuffer.allocateDirect(32 * 1024));
     }

     @Override
     public void onReadCompleted(UrlRequest urlRequest, UrlResponseInfo urlResponseInfo, ByteBuffer byteBuffer) throws Exception {
         Log.i("TAG", "onReadCompleted");
         byteBuffer.flip();

         try {
             mReceiveChannel.write(byteBuffer);
         } catch (IOException e) {
             e.printStackTrace();
         }
         byteBuffer.clear();
         urlRequest.read(byteBuffer);
     }

     @Override
     public void onSucceeded(UrlRequest urlRequest, UrlResponseInfo urlResponseInfo) {
         Log.i("TAG", "onSucceeded");
         Log.i("TAG", String.format("Request Completed, status code is %d, total received bytes is %d",
                 urlResponseInfo.getHttpStatusCode(), urlResponseInfo.getReceivedBytesCount()));

         final String receivedData = mBytesReceived.toString();
         final String url = urlResponseInfo.getUrl();
         final String text = "Completed " + url + " (" + urlResponseInfo.getHttpStatusCode() + ")";

         Log.i("TAG", "text:" + text);
         Log.i("TAG", "receivedData:" + receivedData);
         Handler handler = new Handler(Looper.getMainLooper());
         handler.post(new Runnable() {
             @Override
             public void run() {
                 Toast.makeText(getApplicationContext(), "onSucceeded", Toast.LENGTH_SHORT).show();
             }
         });
     }

     @Override
     public void onFailed(UrlRequest urlRequest, UrlResponseInfo urlResponseInfo, UrlRequestException e) {
         Log.i("TAG", "onFailed");
         Log.i("TAG", "error is: %s" + e.getMessage());

         Handler handler = new Handler(Looper.getMainLooper());
         handler.post(new Runnable() {
             @Override
             public void run() {
                 Toast.makeText(getApplicationContext(), "onFailed", Toast.LENGTH_SHORT).show();
             }
         });
     }
 }, executor, cronetEngine);
 builder.build().start();
```

#### 发送一个POST请求


POST请求和上面的GET请求相比，就是多了一个request body，这里将上面的方法简单封装一下，以同时支持GET请求和POST请求。

```
public void startWithURL(String url, UrlRequest.Callback callback, Executor executor, String postData) {
    UrlRequest.Builder builder = new UrlRequest.Builder(url, callback, executor, mCronetEngine);
    applyPostDataToUrlRequestBuilder(builder, executor, postData);
    builder.build().start();
}

private void applyPostDataToUrlRequestBuilder(
        UrlRequest.Builder builder, Executor executor, String postData) {
    if (postData != null && postData.length() > 0) {
        builder.setHttpMethod("POST");
        builder.addHeader("Content-Type", "application/x-www-form-urlencoded");
        builder.setUploadDataProvider(
                UploadDataProviders.create(postData.getBytes()), executor);
    }
}
```

之后，我们复用前文发送GET请求的回调即可。

值得注意的是post请求需要提供一个UploadDataProvider，该对象用于提供发送的数据包，这么做的好处是一定程度上对body的数据格式进行扩展，默认Chromium的网络栈中并没有表单和Multipart的实现，因此我们可以通过UploadDataProvider对象，自行实现。

### 参考链接

 - [chromium net到android平台的移植](http://hanpfei.github.io/2016/10/18/chromium-net-android-porting/)
 - [Chromium Android编译指南](http://hanpfei.github.io/2016/10/16/Chromium_Android%E7%BC%96%E8%AF%91%E6%8C%87%E5%8D%97/)
 - [懒人chromium net android移植指南](http://hanpfei.github.io/2016/11/11/lazy-chromium-net-android-porting-guide/)
 - [Chromium GN构建工具的使用](http://hanpfei.github.io/2016/11/16/ChromiumGN%E6%9E%84%E5%BB%BA%E5%B7%A5%E5%85%B7%E7%9A%84%E4%BD%BF%E7%94%A8/)

