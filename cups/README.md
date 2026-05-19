# CUPS 容器操作指南

## 进入容器

```bash
docker exec -it cups-web-cups-1 bash
```

## 手动添加打印机

### 通用格式

```bash
lpadmin -p <打印机名称> -E \
  -v <打印机URI> \
  -m everywhere
```

- `-p`：CUPS 中显示的打印机名称（自定义）
- `-E`：启用打印机
- `-v`：打印机 URI（IPP/USB/socket 等协议）
- `-m everywhere`：使用 driverless 自动匹配驱动（推荐）

### 示例：网络打印机（IPP）

```bash
# 小票打印机 XP420B
lpadmin -p XP420B -E \
  -v ipp://192.168.3.116:631/printers/Xprinter_XP_420B \
  -m everywhere

# 小票打印机 HPRT N31
lpadmin -p HPRT_N31 -E \
  -v ipp://192.168.3.116:631/printers/HPRT_N31 \
  -m everywhere

# 爱普生打印机（IPP 直连）
lpadmin -p Epson -E \
  -v ipp://192.168.3.22/ipp/print \
  -m everywhere
```

### 示例：USB 打印机

```bash
# USB 直连（自动检测）
lpadmin -p MyPrinter -E -v usb:// -m everywhere

# 指定 USB 设备路径
lpadmin -p MyPrinter -E \
  -v "usb://EPSON/L380?serial=XXXXXX" \
  -m everywhere
```

### 示例：Socket 协议（HP 等老式打印机）

```bash
lpadmin -p HP1020 -E \
  -v socket://192.168.3.50:9100 \
  -m everywhere
```

## 查看已添加的打印机

```bash
# 列出所有打印机
lpstat -p -d

# 查看打印机详细信息
lpstat -v
lpoptions -p <打印机名称> -l
```

## 删除打印机

```bash
lpadmin -x <打印机名称>
```

## 启用/禁用打印机

```bash
# 启用
cupsenable <打印机名称>

# 禁用
cupsdisable <打印机名称>
```

## 接受/拒绝打印任务

```bash
# 允许接受任务
cupsaccept <打印机名称>

# 拒绝新任务
cupsreject <打印机名称>
```

## 测试打印

```bash
# 打印测试页
lp -d <打印机名称> /usr/share/cups/data/testprint

# 打印文本文件
lp -d <打印机名称> /path/to/file.txt
```

## 查看打印队列

```bash
# 查看所有任务
lpstat -o

# 查看特定打印机任务
lpstat -o <打印机名称>

# 取消所有任务
cancel -a

# 取消特定任务
cancel <任务ID>
```

## 查找网络打印机

```bash
# 使用 avahi 发现局域网中的打印机
avahi-browse -rt _ipp._tcp

# 使用 ipptool 查询打印机属性
ipptool -t ipp://192.168.3.22/ipp/print get-attributes.test
```

## 驱动相关

```bash
# 查看可用的驱动列表
lpinfo -m | grep -i <品牌名>

# 查看支持的设备列表
lpinfo -v | grep -i <品牌名>

# 使用指定 PPD 驱动
lpadmin -p MyPrinter -E \
  -v ipp://192.168.3.22/ipp/print \
  -m <PPD文件名或路径>
```

## CUPS 服务管理

```bash
# 重启 CUPS
/etc/init.d/cups restart

# 查看 CUPS 日志
tail -f /var/log/cups/error_log
```
