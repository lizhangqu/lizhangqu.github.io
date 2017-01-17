title: Https与HttpDNS的那些事
date: 2017-01-17 15:34:58
categories: [Android]
tags: [Android, Http/2.0, HttpDNS, OkHttp]

---

>仅以本文备忘2016年网络优化过程中留下的坑，本文所讨论的范围全部基于OkHttp此开源库，版本号为3.2.0


 ### 关于Https

发送HTTPS请求首先要进行SSL/TLS握手，握手过程大致如下：

 - 客户端发起握手请求，携带随机数、支持算法列表等参数。
 - 服务端收到请求，选择合适的算法，下发公钥证书和随机数。
 - 客户端对服务端证书进行校验，并发送随机数信息，该信息使用公钥加密。
 - 服务端通过私钥获取随机数信息。
 - 双方根据以上交互的信息生成session ticket，用作该连接后续数据传输的加密密钥。

上述过程中，第3步客户端需要验证服务端下发的证书，验证过程有以下两个要点：

 - 客户端用本地保存的根证书解开证书链，确认服务端下发的证书是由可信任的机构颁发的。
 - 客户端需要检查证书的domain域和扩展域，看是否包含本次请求的host。

如果上述两点都校验通过，就证明当前的服务端是可信任的，否则就是不可信任，应当中断当前连接。

 ### 关于Http/2.0

  - [HTTP/2 资料汇总](https://imququ.com/post/http2-resource.html)


 ### OkHttp对Http/2.0的支持

OkHttp天然支持Http/2.0，但是在较新的版本中，OkHttp移除了对NPN选择协议的支持，转而只支持ALPN选择协议。见提交记录 [Remove NPN support from OkHttp](https://github.com/square/okhttp/commit/4d068212aa1d0bcf0afc45b41a272c772a5b955c)
  
>NPN（Next Protocol Negotiation，下一代协议协商），是一个 TLS 扩展，由 Google 在开发 SPDY 协议时提出。随着 SPDY 被 HTTP/2 取代，NPN 也被修订为 ALPN（Application Layer Protocol Negotiation，应用层协议协商）。二者目标一致，但实现细节不一样，相互不兼容。以下是它们主要差别：
NPN 是服务端发送所支持的 HTTP 协议列表，由客户端选择；而 ALPN 是客户端发送所支持的 HTTP 协议列表，由服务端选择；
NPN 的协商结果是在 Change Cipher Spec 之后加密发送给服务端；而 ALPN 的协商结果是通过 Server Hello 明文发给客户端；

但是有以下几种场景，我们可能还需要使用NPN：

 - ALPN只支持Android 5.0以上，如果要在Android 5.0以下支持Http/2.0，必须使用NPN
 - 理论上nginx可以对ALPN和NPN同时支持，但是部分服务器上的配置可能只支持NPN，并且短时间内不会支持ALPN，必须使用NPN


>如果要检测服务器是否支持ALPN或者NPN，可以使用此网站进行检测 [https://www.ssllabs.com/ssltest/analyze.html](https://www.ssllabs.com/ssltest/analyze.html)

检测效果如下:
![alpn_npn_detect.jpeg](alpn_npn_detect.jpeg)

也可以直接使用 [https://tools.keycdn.com/http2-test](https://tools.keycdn.com/http2-test) 检测是否支持Http2.0，但是这个检测只会当ALPN支持的情况下才会认为支持Http2.0

此时的检测效果如下:
![http2_detect.jpeg](http2_detect.jpeg)

出于以上两个原因，这时候Http/2.0就无法发挥作用了，因此，我们有必要将OkHttp这部分代码还原，于是对OkHttp进行了定制，定制方式很简单，根据对应的提交记录，把移除的代码进行还原即可。

改造的代码全部位于okhttp3.internal.Platform这个类中，为了避免改造影响原有逻辑，我们在这个类中加入一个enableNPN的开关，当开关关闭时，逻辑不发生变化，当开关打开时，NPN选择协议会在ALPN选择协议不支持的情况下生效，优先使用ALPN选择协议。默认开关开启。

```
public class Platform {
  //......
  //加入的代码start
  public static boolean enableNPN = true;
  //加入的代码end
  //......
}
```

接着在内部类okhttp3.internal.Platform$Android中加入两个成员变量，参考getAlpnSelectedProtocol和setAlpnProtocols，加入getNpnSelectedProtocol和setNpnProtocols变量

```
/** Android 2.3 or better. */
private static class Android extends Platform {
  // Non-null on Android 5.0+.
  private final OptionalMethod<Socket> getAlpnSelectedProtocol;
  private final OptionalMethod<Socket> setAlpnProtocols;

  // 加入的代码start
  // Non-null on Android 4.1+.
  private final OptionalMethod<Socket> getNpnSelectedProtocol;
  private final OptionalMethod<Socket> setNpnProtocols;
  // 加入的代码end
}
```

同时构造函数中增加这两个入参，并进行赋值

```
public Android(Class<?> sslParametersClass, OptionalMethod<Socket> setUseSessionTickets,
        OptionalMethod<Socket> setHostname, OptionalMethod<Socket> getAlpnSelectedProtocol,
        OptionalMethod<Socket> setAlpnProtocols, OptionalMethod<Socket> getNpnSelectedProtocol,
                   OptionalMethod<Socket> setNpnProtocols) {
  this.sslParametersClass = sslParametersClass;
  this.setUseSessionTickets = setUseSessionTickets;
  this.setHostname = setHostname;
  this.getAlpnSelectedProtocol = getAlpnSelectedProtocol;
  this.setAlpnProtocols = setAlpnProtocols;
  //加入的代码start
  this.getNpnSelectedProtocol = getNpnSelectedProtocol;
  this.setNpnProtocols = setNpnProtocols;
  //加入的代码end
}
```


修改内部类okhttp3.internal.Platform$Android中configureTlsExtensions的方法，配置SSLSocket对象，开启其NPN相关的功能，注意NPN的情况下，enableNPN开关的条件

```
public void configureTlsExtensions(
    SSLSocket sslSocket, String hostname, List<Protocol> protocols) {
  // Enable SNI and session tickets.
  if (hostname != null) {
    setUseSessionTickets.invokeOptionalWithoutCheckedException(sslSocket, true);
    setHostname.invokeOptionalWithoutCheckedException(sslSocket, hostname);
  }

  // Enable ALPN.
  if (setAlpnProtocols != null && setAlpnProtocols.isSupported(sslSocket)) {
    Object[] parameters = {concatLengthPrefixed(protocols)};
    setAlpnProtocols.invokeWithoutCheckedException(sslSocket, parameters);
  }


  //加入的代码start
  // Enbale NPN.
  if (enableNPN && setNpnProtocols != null && setNpnProtocols.isSupported(sslSocket)) {
    Object[] parameters = {concatLengthPrefixed(protocols)};
    setNpnProtocols.invokeWithoutCheckedException(sslSocket, parameters);
  }
  //加入的代码end
}
```

修改内部类okhttp3.internal.Platform$Android中getSelectedProtocol的方法，返回选择的协议，注意NPN的情况下，enableNPN开关的条件

```
@Override public String getSelectedProtocol(SSLSocket socket) {
  boolean alpnSupported = ((getAlpnSelectedProtocol != null)
          && (getAlpnSelectedProtocol.isSupported(socket)));
  boolean npnSupported = ((getNpnSelectedProtocol != null)
          && (getNpnSelectedProtocol.isSupported(socket)));
  if (!(alpnSupported || npnSupported)) {
    return null;
  }

  // if support alpn ,returen it.
  if (alpnSupported) {
    byte[] alpnResult =
            (byte[]) getAlpnSelectedProtocol.invokeWithoutCheckedException(socket);
    if (alpnResult != null) {
      return new String(alpnResult, Util.UTF_8);
    }
  }

  //加入的代码start
  // don't support alpn,try npn.
  if (enableNPN && npnSupported) {
    byte[] npnResult =
            (byte[]) getNpnSelectedProtocol.invokeWithoutCheckedException(socket);
    if (npnResult != null) {
      return new String(npnResult, Util.UTF_8);
    }
  }
  //加入的代码end
  return null;
}
```

而内部类okhttp3.internal.Platform$Android构造函数中传入的入参则是由Platform.findPlatform函数中反射得到的，

```
/** Attempt to match the host runtime to a capable Platform implementation. */
  private static Platform findPlatform() {
    // Attempt to find Android 2.3+ APIs.
    try {
      //.......some codes

      //alpn support
      OptionalMethod<Socket> getAlpnSelectedProtocol = null;
      OptionalMethod<Socket> setAlpnProtocols = null;

      //加入的代码start
      //npn support
      OptionalMethod<Socket> getNpnSelectedProtocol = null;
      OptionalMethod<Socket> setNpnProtocols = null ;
      //加入的代码end

      // Attempt to find Android 5.0+ APIs.
      try {
        Class.forName("android.net.Network"); // Arbitrary class added in Android 5.0.
        getAlpnSelectedProtocol = new OptionalMethod<>(byte[].class, "getAlpnSelectedProtocol");
        setAlpnProtocols = new OptionalMethod<>(null, "setAlpnProtocols", byte[].class);
      } catch (ClassNotFoundException ignored) {
      }

      //加入的代码start
      //to make NPN Support
      try {
        getNpnSelectedProtocol = new OptionalMethod<Socket>(byte[].class,
                "getNpnSelectedProtocol");
        setNpnProtocols = new OptionalMethod<Socket>(null, "setNpnProtocols",
                byte[].class);
      } catch (Exception e) {
        //ignore
      }
      //加入的代码end

      //传入getNpnSelectedProtocol和setNpnProtocols
      return new Android(sslParametersClass, setUseSessionTickets, setHostname,
          getAlpnSelectedProtocol, setAlpnProtocols, getNpnSelectedProtocol, setNpnProtocols);
    } catch (ClassNotFoundException ignored) {
      // This isn't an Android runtime.
    }
    //......
    // Probably an Oracle JDK like OpenJDK.
    return new Platform();
}

```

 ### 检测客户端使用的Http协议

如果通过肉眼查看，基本上不可能知道当前的请求是Http/2.0还是Http/1.1或者说是SPDY/3.1，当然，可以通过nginx的日志可以看到是什么协议，如下:
![http2.jpeg](http2.jpeg)

但是我们的目的不是通过nginx日志来看，而是通过logcat日志来看，那么OkHttp中有没有什么方法来获得当前请求的协议呢，其实是有的，在拦截器中就可以，可以在官方的logging-interceptor模块基础上，加入协议的日志。其实在HttpLoggingInterceptor中，已经有协议相关的日志了，但是该日志并不准确，即使在Http/2.0的情况下，返回的也是Http/1.1,因此我们使用更加准确的方式打印这个协议，在HttpLoggingInterceptor合适的地方(返回response的地方)，加入下面两行代码即可：

```
Protocol responseProtocol = response.protocol();
logger.log("<-- " +"responseProtocol:"+responseProtocol);
```

此时会在reponse返回的时候打印对应的协议日志，如下：
![http2_logcat.jpeg](http2_logcat.jpeg)


### OkHttp使用HttpDNS的两种方式
 
  - [Android使用OkHttp支持HttpDNS](http://blog.csdn.net/sbsujjbcy/article/details/50532797)
  - [Android OkHttp实现HttpDns的最佳实践（非拦截器）](http://blog.csdn.net/sbsujjbcy/article/details/51612832)


这两种方式各有优缺点，使用Dns接口方式过于底层，异常不容易控制，如果要十分精确的控制异常，建议使用拦截器方式，而使用拦截器方式主要需要进行两步操作
 
 - 对url中的host进行替换，将域名替换为ip
 - 添加header请求头，值为替换前的域名

在Http的情况下，这种方式不存在任何问题，但是在Https的情况下，这种方式需要修改OkHttp的相关代码，解决相关问题，具体问题下文细说。


### Https下使用HttpDNS证书校验问题

在okhttp3.internal.io.RealConnection类中有个方法叫connectTls，里面的代码如下

```
private void connectTls(int readTimeout, int writeTimeout,
      ConnectionSpecSelector connectionSpecSelector) throws IOException {
    if (route.requiresTunnel()) {
      createTunnel(readTimeout, writeTimeout);
    }

    Address address = route.address();
    SSLSocketFactory sslSocketFactory = address.sslSocketFactory();
    boolean success = false;
    SSLSocket sslSocket = null;
    try {
      // Create the wrapper over the connected socket.
      sslSocket = (SSLSocket) sslSocketFactory.createSocket(
          rawSocket, address.url().host(), address.url().port(), true /* autoClose */);

      // Configure the socket's ciphers, TLS versions, and extensions.
      ConnectionSpec connectionSpec = connectionSpecSelector.configureSecureSocket(sslSocket);
      if (connectionSpec.supportsTlsExtensions()) {
        Platform.get().configureTlsExtensions(
            sslSocket, address.url().host(), address.protocols());
      }

      // Force handshake. This can throw!
      sslSocket.startHandshake();
      Handshake unverifiedHandshake = Handshake.get(sslSocket.getSession());

      // Verify that the socket's certificates are acceptable for the target host.
      if (!address.hostnameVerifier().verify(address.url().host(), sslSocket.getSession())) {
        X509Certificate cert = (X509Certificate) unverifiedHandshake.peerCertificates().get(0);
        throw new SSLPeerUnverifiedException("Hostname " + address.url().host() + " not verified:"
            + "\n    certificate: " + CertificatePinner.pin(cert)
            + "\n    DN: " + cert.getSubjectDN().getName()
            + "\n    subjectAltNames: " + OkHostnameVerifier.allSubjectAltNames(cert));
      }

      // Check that the certificate pinner is satisfied by the certificates presented.
      address.certificatePinner().check(address.url().host(),
          unverifiedHandshake.peerCertificates());

      // Success! Save the handshake and the ALPN protocol.
      String maybeProtocol = connectionSpec.supportsTlsExtensions()
          ? Platform.get().getSelectedProtocol(sslSocket)
          : null;
      socket = sslSocket;
      source = Okio.buffer(Okio.source(socket));
      sink = Okio.buffer(Okio.sink(socket));
      handshake = unverifiedHandshake;
      protocol = maybeProtocol != null
          ? Protocol.get(maybeProtocol)
          : Protocol.HTTP_1_1;
      success = true;
    } catch (AssertionError e) {
      if (Util.isAndroidGetsocknameError(e)) throw new IOException(e);
      throw e;
    } finally {
      if (sslSocket != null) {
        Platform.get().afterHandshake(sslSocket);
      }
      if (!success) {
        closeQuietly(sslSocket);
      }
    }
  }
```

可以看到，无论是调用Platform.get().configureTlsExtensions()配置SSLSocket对象，还是address.hostnameVerifier().verify()进行证书校验，以及address.certificatePinner().check()中，传入的host都是address.url().host()，而这个值却恰恰是我们替换了url中的域名为ip的host，所以此时拿到的值为ip，这时候，带来了两个问题：

 - 当客户端使用HttpDNS时，请求URL中的host会被替换成HttpDNS解析出来的ip，所以在证书验证的时候，会出现domain不匹配的情况，导致SSL/TLS握手不成功。
 - 在服务器上存在多张证书的情况下，会存在问题



而对于服务器上存在多张证书的情况下，为什么会存在问题呢，这里存在一个概念，叫SNI

>SNI（Server Name Indication）是为了解决一个服务器使用多个域名和证书的SSL/TLS扩展。它的工作原理如下：

 - 在连接到服务器建立SSL链接之前先发送要访问站点的域名（Hostname）。
 - 服务器根据这个域名返回一个合适的证书。

目前，大多数操作系统和浏览器都已经很好地支持SNI扩展，OpenSSL 0.9.8也已经内置这一功能。

上述过程中，当客户端使用HttpDNS时，请求URL中的Host会被替换成HttpPDNS解析出来的IP，导致服务器获取到的域名为解析后的IP，无法找到匹配的证书，只能返回默认的证书或者不返回，所以会出现SSL/TLS握手不成功的错误。

最常见的一个场景就是：
>比如当你需要通过https访问CDN资源时，CDN的站点往往服务了很多的域名，所以需要通过SNI指定具体的域名证书进行通信。


其实OkHttp是支持SNI的，在Platform.configureTlsExtensions方法中，设置了SNI，只是传入的Host变成了ip，所以导致了这个问题

```
public void configureTlsExtensions(
        SSLSocket sslSocket, String hostname, List<Protocol> protocols) {
  // Enable SNI and session tickets.
  if (hostname != null) {
  setUseSessionTickets.invokeOptionalWithoutCheckedException(sslSocket, true);
  setHostname.invokeOptionalWithoutCheckedException(sslSocket, hostname);
  }
  //......
}
```

这两个问题归根到底都是替换了Host所造成的，因此还是需要对OkHttp开刀，修改源码。

在okhttp3.internal.http.HttpEngine中找到createAddress方法，增加一个入参，传入request.url().host()的同时，传入request.header("host")

```
private static Address createAddress(OkHttpClient client, Request request) {
    //......some codes

    return new Address(request.url().host(), request.header("host"), request.url().port(),
        client.dns(),
        client.socketFactory(), sslSocketFactory, hostnameVerifier, certificatePinner,
        client.proxyAuthenticator(), client.proxy(), client.protocols(),
        client.connectionSpecs(), client.proxySelector());
  }
```


在Address中增加成员变量和成员方法

```
public final class Address {
  final String headerHost;
  public String host() {
      return headerHost;
    }
}
```

其中headerHost的值通过构造函数中增加的变量得到

```
 public Address(String uriHost, String headerHost, int uriPort, Dns dns,
      SocketFactory socketFactory,
      SSLSocketFactory sslSocketFactory, HostnameVerifier hostnameVerifier,
      CertificatePinner certificatePinner, Authenticator proxyAuthenticator, Proxy proxy,
      List<Protocol> protocols, List<ConnectionSpec> connectionSpecs, ProxySelector proxySelector) {
    //.......some codes
    this.headerHost = headerHost;

    //.......some codes
  }
```

回到okhttp3.internal.io.RealConnection中的connectTls方法中，将证书验证，设置SNI的传入的参数进行修改，修改原则为：当请求头中的host存在时，使用请求头中的host，当请求头中的host不存在时，使用url中的host。

```
 private void connectTls(int readTimeout, int writeTimeout,
      ConnectionSpecSelector connectionSpecSelector) throws IOException {
    if (route.requiresTunnel()) {
      createTunnel(readTimeout, writeTimeout);
    }

    Address address = route.address();
    SSLSocketFactory sslSocketFactory = address.sslSocketFactory();
    boolean success = false;
    SSLSocket sslSocket = null;
    try {
      // Create the wrapper over the connected socket.
      sslSocket = (SSLSocket) sslSocketFactory.createSocket(
          rawSocket, address.url().host(), address.url().port(), true /* autoClose */);
      //加入的代码start
      //获取请求头中的host
      String host = address.host();
      if (host == null || host.length() == 0) {
        //如果请求中的host为空，则使用url中的host
        host = address.url().host();
      }
      //加入的代码end
      // Configure the socket's ciphers, TLS versions, and extensions.
      ConnectionSpec connectionSpec = connectionSpecSelector.configureSecureSocket(sslSocket);
      if (connectionSpec.supportsTlsExtensions()) {
        //设置SNI时传入的host此时不再是ip
        Platform.get().configureTlsExtensions(
            sslSocket, host, address.protocols());
      }

      // Force handshake. This can throw!
      sslSocket.startHandshake();
      Handshake unverifiedHandshake = Handshake.get(sslSocket.getSession());

      // 校验时传入的host此时不再是ip
      // Verify that the socket's certificates are acceptable for the target host.
      if (!address.hostnameVerifier().verify(host, sslSocket.getSession())) {
        X509Certificate cert = (X509Certificate) unverifiedHandshake.peerCertificates().get(0);
        throw new SSLPeerUnverifiedException("Hostname " + host + " not verified:"
            + "\n    certificate: " + CertificatePinner.pin(cert)
            + "\n    DN: " + cert.getSubjectDN().getName()
            + "\n    subjectAltNames: " + OkHostnameVerifier.allSubjectAltNames(cert));
      }

      // Check that the certificate pinner is satisfied by the certificates presented.
      address.certificatePinner().check(host,
          unverifiedHandshake.peerCertificates());

      // Success! Save the handshake and the ALPN protocol.
      String maybeProtocol = connectionSpec.supportsTlsExtensions()
          ? Platform.get().getSelectedProtocol(sslSocket)
          : null;
      socket = sslSocket;
      source = Okio.buffer(Okio.source(socket));
      sink = Okio.buffer(Okio.sink(socket));
      handshake = unverifiedHandshake;
      protocol = maybeProtocol != null
          ? Protocol.get(maybeProtocol)
          : Protocol.HTTP_1_1;
      success = true;
    } catch (AssertionError e) {
      if (Util.isAndroidGetsocknameError(e)) throw new IOException(e);
      throw e;
    } finally {
      if (sslSocket != null) {
        Platform.get().afterHandshake(sslSocket);
      }
      if (!success) {
        closeQuietly(sslSocket);
      }
    }
  }
```

当然，这个问题还有另一个解决方式，就是通过OkHttp的Dns接口实现HttpDns，于是整个世界平静了，为什么这么说呢，见下文。

### Http/2.0 && SPDY/3.1 与HttpDNS

当你天真的以为这样解决了问题之后，那你就打错特错了，这就是上面说的，直接通过OkHttp的Dns接口实现HttpDns一了百了的原因了。在SPDY和Http2.0中，请求头中的host已不再是Http1.1时代的host了，通过查看协议文档 [https://tools.ietf.org/html/draft-ietf-httpbis-http2-09#section-8.1.3](https://tools.ietf.org/html/draft-ietf-httpbis-http2-09#section-8.1.3)可以看到在Http2.0中使用:authority请求头代替Http1.1中的host

![http2_docs.png](http2_docs.png)

**题外话，在Http2.0中，所有请求头全部变成小写，大小的请求头是不符合规范的。**

这个问题导致的直接结果就是服务器端拿到的host是ip，而不是域名，如果服务器对host进行校验，那么可能就会出问题。

那么这个问题该怎么解决呢？同样需要对OkHttp开刀。修改okhttp3.internal.http.Http2xStream中的spdy3HeadersList以及http2HeadersList方法，将对应请求头的值设为域名即可。

```
public static List<Header> spdy3HeadersList(Request request) {
    Headers headers = request.headers();
    //加入的代码start
    //先取header中的host
    String host = request.header("host");
    if (host == null || host.length() == 0) {
      //没有则使用原始的request.url()
      host = Util.hostHeader(request.url(), false);
    }
    //加入的代码end
    List<Header> result = new ArrayList<>(headers.size() + 5);
    result.add(new Header(TARGET_METHOD, request.method()));
    result.add(new Header(TARGET_PATH, RequestLine.requestPath(request.url())));
    result.add(new Header(VERSION, "HTTP/1.1"));
    //修改为host变量
    result.add(new Header(TARGET_HOST, host));
    result.add(new Header(TARGET_SCHEME, request.url().scheme()));

    Set<ByteString> names = new LinkedHashSet<>();
    for (int i = 0, size = headers.size(); i < size; i++) {
      // header names must be lowercase.
      ByteString name = ByteString.encodeUtf8(headers.name(i).toLowerCase(Locale.US));

      // Drop headers that are forbidden when layering HTTP over SPDY.
      if (SPDY_3_SKIPPED_REQUEST_HEADERS.contains(name)) continue;

      // If we haven't seen this name before, add the pair to the end of the list...
      String value = headers.value(i);
      if (names.add(name)) {
        result.add(new Header(name, value));
        continue;
      }

      // ...otherwise concatenate the existing values and this value.
      for (int j = 0; j < result.size(); j++) {
        if (result.get(j).name.equals(name)) {
          String concatenated = joinOnNull(result.get(j).value.utf8(), value);
          result.set(j, new Header(name, concatenated));
          break;
        }
      }
    }
    return result;
  }
```


```
public static List<Header> http2HeadersList(Request request) {
    Headers headers = request.headers();
    //加入的代码start
    //先取header中的host
    String host = request.header("host");
    if (host == null || host.length() == 0) {
      //没有则使用原始的request.url()
      host = Util.hostHeader(request.url(), false);
    }
    //加入的代码end
    List<Header> result = new ArrayList<>(headers.size() + 4);
    result.add(new Header(TARGET_METHOD, request.method()));
    result.add(new Header(TARGET_PATH, RequestLine.requestPath(request.url())));
    //修改为host变量
    result.add(new Header(TARGET_AUTHORITY, host)); // Optional.
    result.add(new Header(TARGET_SCHEME, request.url().scheme()));

    for (int i = 0, size = headers.size(); i < size; i++) {
      // header names must be lowercase.
      ByteString name = ByteString.encodeUtf8(headers.name(i).toLowerCase(Locale.US));
      if (!HTTP_2_SKIPPED_REQUEST_HEADERS.contains(name)) {
        result.add(new Header(name, headers.value(i)));
      }
    }
    return result;
  }
```

 ### Content-Length在Http2.0下的坑

 如果使用OkHttp的时候使用了自定义的RequestBody，并且使用了application/octet-stream这种类型，那么在Http2.0下就需要特别注意了，如下：

 ```
 class ByteRequestBody extends RequestBody {
        final MediaType MEDIA_TYPE = MediaType.parse("application/octet-stream; charset=utf-8");
        byte[] bytes;

        public ByteRequestBody(byte[] bytes) {
            this.bytes = bytes;
        }

        @Override
        public MediaType contentType() {
            return MEDIA_TYPE;
        }

        @Override
        public void writeTo(BufferedSink sink) throws IOException {
            sink.write(bytes);
        }
    }

 ```

 初步看上面的代码，你会发现这段代码没有任何问题，但是实际上这段代码是有问题的，将直接导致网络请求响应变慢，加快服务器I/O设备耗损。

 这个问题会导致服务器将所有请求进行硬盘buffer处理，nginx会报以下警告

 ```
 2016/12/02 16:42:58 [warn] 20479#0: *77176 a client request body is buffered to a temporary file /home/www/tengine/data/client_body/0033902790, client: *.*.*.*, server: fucknmb.com, request: "POST /apiName/apiVersion HTTP/2.0", host: "fucknmb.com", referrer: "https://fucknmb.com"
 ```

 这个问题，我并没有找到最终的原因，就是这么神奇，但是我找到了解决方式。

 当使用application/octet-stream类型时，OkHttp会追加请求头Transfer-Encoding: chunked请求头，而此时如果请求头里有Content-Length，则问题不会存在，错就错在上面的自定义RequestBody，没有重写contentLength()方法，如果没有重写，OkHttp会默认返回-1,在返回-1的时候，是不会追加Content-Length这个请求头的，因此这个问题的原因在与使用了application/octet-stream类型，但没有Content-Length，而且这个问题只有Http2.0下会有。Http/1.1和SPDY/3.1都不会有，初步怀疑和Http/2.0的帧传输有关，那么解决方法也很简单，重写contentLength()方法即可。如下

 ```
 class ByteRequestBody extends RequestBody {
        final MediaType MEDIA_TYPE = MediaType.parse("application/octet-stream; charset=utf-8");
        byte[] bytes;

        public ByteRequestBody(byte[] bytes) {
            this.bytes = bytes;
        }
        //返回字节长度
        @Override
        public long contentLength() throws IOException {
            return bytes.length;
        }

        @Override
        public MediaType contentType() {
            return MEDIA_TYPE;
        }

        @Override
        public void writeTo(BufferedSink sink) throws IOException {
            sink.write(bytes);
        }
    }
 ```

 当然，如果没有必要重写的情况下，建议用以下方式创建RequestBody，避免漏掉需要重写的方法

 ```
 RequestBody.create( MediaType.parse("application/octet-stream; charset=utf-8"), bytes);
 ```


