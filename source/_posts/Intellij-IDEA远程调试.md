title: IntelliJ IDEA远程调试
date: 2017-04-07 22:09:34
categories: [IDEA]
tags: [IDEA, 远程调试]
---

### 前言

快速定位线上问题，所以远程调试服务器是一个比较实用的方式。

<!--more-->

### 新建Remote Configuration

Edit Configurations -> +号 -> Remote -> 填写远程Host和端口号

![configuration_remote.jpeg](configuration_remote.jpeg)


其中Host填写的是远程服务器的IP地址，8082就是远程调试的端口

### 服务器配置

将第一步IntelliJ IDEA配置中的Command line arguments for running remote JVM复制下来，在服务器Tomcat的bin目录下的setenv.sh中增加如下配置:

```
CATALINA_OPTS="${CATALINA_OPTS} -agentlib:jdwp=transport=dt_socket,server=y,address=8082,suspend=n "
```

### 启动调试

![start_debug.jpeg](start_debug.jpeg)

![attach_debug.jpeg](attach_debug.jpeg)

看到Connected to target VM等信息输出就表示连接到了远程服务器，之后就是正常的调试了

### 退出调试

点击上图左侧工具栏倒数第二个红色的叉叉退出调试


弹出确认框时不要选择Terminate the process after disconnect,然后点击disconnect断开连接，重要的事再说一遍，不要选择断开连接后终止程序
![close_confirm.jpeg](close_confirm.jpeg)