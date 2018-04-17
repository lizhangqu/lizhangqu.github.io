title: 一种全局拦截并监控DNS的方式
date: 2018-04-16 17:01:31
categories: [Android]
tags: [Android, DNS]
---


如果网络库使用的是OkHttp，那么OkHttp提供了Dns接口，用于自定义dns的实现，一般HttpDNS就可以通过这个接口去实现，但是这种方式有一个巨大的局限性，就是只能拦截到当前使用的OkHttpClient的DNS，无法拦截其他库中的OkHttpClient的DNS解析行为，而且如果使用的不是OkHttp，则一律拦截不到。那么有没有一种方式，可以拦截到整个App的DNS解析而不依赖OkHttp呢？

<!-- more -->

前几天看了两篇文章

 - [《客厅TV-APP HttpDNS技术接入与实战》](https://mp.weixin.qq.com/s/BVF24W6pyfhtoZo9cTbtpA)
 - [如何为Android应用提供全局的HttpDNS服务](https://juejin.im/entry/5a11c3db51882561a20a11cc)

觉得可行，自己试验了一下，最终得出结论：

>可以拦截整个App的DNS解析并进行监控（如判断是否被劫持了），甚至连WebView中的DNS解析也可以拦截到，使WebView使用HttpDNS成为可能。

那么具体怎么拦截呢？

我们知道，Java层获取域名对应IP是通过InetAddress.getAllByName("your.domain.com")来获取的，而在Android上，其实现大致如下：

```
static final InetAddressImpl impl = new Inet6AddressImpl();

public static InetAddress[] getAllByName(String host)
    throws UnknownHostException {
    return impl.lookupAllHostAddr(host, NETID_UNSET).clone();
}
```

最终调用的是Inet6AddressImpl对象的lookupAllHostAddr方法，而Inet6AddressImpl是InetAddressImpl接口的实现类，可以完成ipv4和ipv6的dns解析。

通过上面的分析，发现InetAddressImpl是一个接口，于是我们完全可以代理掉原来的实现方法，但是不幸的是该接口不是public访问符，于是我们只有一种代理方式可以使用，那就是动态代理。


但是还有一个问题，impl是final的，在android上修改final字段和java平台有点区别，android上是否是final这个字段是记录在Field中的accessFlags中，而不是java平台上的modifiers字段中，因此反射修改的时候要特别注意。

简单的实现代码如下：

```
try {
    //获取InetAddress中的impl
    Field impl = InetAddress.class.getDeclaredField("impl");
    impl.setAccessible(true);
    //获取accessFlags
    Field modifiersField = Field.class.getDeclaredField("accessFlags");
    modifiersField.setAccessible(true);
    //去final
    modifiersField.setInt(impl, impl.getModifiers() & ~java.lang.reflect.Modifier.FINAL);
    //获取原始InetAddressImpl对象
    final Object originalImpl = impl.get(null);
    //构建动态代理InetAddressImpl对象
    Object dynamicImpl = Proxy.newProxyInstance(originalImpl.getClass().getClassLoader(), originalImpl.getClass().getInterfaces(), new InvocationHandler() {
        final Object lock = new Object();
        Constructor<Inet4Address> constructor = null;

        @Override
        public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
            //如果函数名为lookupAllHostAddr，并且参数长度为2，第一个参数是host，第二个参数是netId
            if (method.getName().equals("lookupAllHostAddr") && args != null && args.length == 2) {
                Log.e("TAG", "lookupAllHostAddr：" + Arrays.asList(args));
                //获取Inet4Address的构造函数，可能还需要Inet6Address的构造函数，为了演示，简单处理
                if (constructor == null) {
                    synchronized (lock) {
                        if (constructor == null) {
                            try {
                                constructor = Inet4Address.class.getDeclaredConstructor(String.class, byte[].class);
                                constructor.setAccessible(true);
                            } catch (Exception e) {
                                e.printStackTrace();
                            }
                        }
                    }
                }
                if (constructor != null) {
                    //这里实现自己的逻辑
                    //构造一个mock的dns解析并返回
                    if (args[0] != null && "www.baidu.com".equalsIgnoreCase(args[0].toString())) {
                        try {
                            Inet4Address inetAddress = constructor.newInstance(null, new byte[]{(byte) 61, (byte) 135, (byte) 169, (byte) 121});
                            return new InetAddress[]{inetAddress};
                        } catch (Exception e) {
                            e.printStackTrace();
                        }
                    }
                }
            }
            return method.invoke(originalImpl, args);
        }
    });
    //替换impl为动态代理对象
    impl.set(null, dynamicImpl);
    //还原final
    modifiersField.setInt(impl, impl.getModifiers() & java.lang.reflect.Modifier.FINAL);
} catch (Exception e) {
    e.printStackTrace();
}
```

特别值得注意的是，动态代理对象中，不能再调用InetAddress.getAllByName("your.domain.com")，否则会出现死循环，造成java.lang.StackOverflowError异常，所以只能通过反射构造函数，构造一个InetAddress数组对象返回。


这种方式的优点很明显，可以拦截Java层的所有dns解析，**并且连WebView中的dns解析也能拦截到，为WebView中使用HttpDns提供了可能**。
缺点也很明显，需要反射，在不同系统版本上可能存在兼容性问题，需要进行适配。上面的代码并没有进行过兼容性测试，如果需要使用，自行测试。