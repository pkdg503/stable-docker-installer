# MTProxy 批量部署脚本

一个用于 **快速批量部署 Telegram MTProxy**
代理的自动化脚本，支持一键部署多个实例、自动生成密钥、智能端口管理等功能。

## ✨ 功能特点

-   🚀 **一键批量部署多个 MTProxy 容器**
-   🔒 **自动生成安全随机密钥（32 hex）**
-   🌐 **支持多个伪装域名循环使用**
-   🔧 **智能端口管理与冲突检测**
-   📱 **自动生成 Telegram 一键链接**
-   🎨 **彩色终端输出，直观易用**

## 📋 系统要求

-   Linux 服务器（推荐 Ubuntu/Debian）
-   已安装 **Docker**
-   已安装 **curl**
-   防火墙开放对应端口范围

## 🚀 快速开始

### 1. 下载脚本

``` bash
wget -O mtproxy-batch-deploy.sh https://raw.githubusercontent.com/your-repo/mtproxy-batch-deploy/main/mtproxy-batch-deploy.sh
chmod +x mtproxy-batch-deploy.sh
```

### 2. 运行脚本

``` bash
./mtproxy-batch-deploy.sh
```

## 📖 使用流程

### 第一步：环境检查

脚本会自动检测以下内容： - Docker 是否已安装并运行\
- xxd 工具是否存在（若无将自动安装）\
- Telegram MTProxy 镜像是否可用/自动更新

### 第二步：容器管理

脚本会： - 展示现有 MTProxy 容器状态\
- 提供删除选项（保留全部、全部删除、指定删除）

### 第三步：部署配置

-   容器数量（1--20）
-   起始端口或自定义端口列表\
-   多个伪装域名循环使用

## 🔄 批量部署流程

每个容器自动执行： - 生成唯一 32 字符随机 Secret\
- 分配伪装域名\
- 分配端口并检测冲突\
- 输出 Telegram 一键代理链接

## ⚙️ 示例

    容器数量: 3
    起始端口: 49286
    伪装域名: microsoft.com,apple.com,google.com

## 🔧 Docker 管理命令

``` bash
docker ps -a --filter 'name=mtproxy'
docker logs mtproxy0
docker stop mtproxy0
docker start mtproxy0
docker rm -f mtproxy0
```

## 🛡️ 技术特性

-   强随机密钥\
-   TLS 加密\
-   伪装域名增强隐蔽性\
-   自动冲突检测\
-   多域名循环\
-   自带错误处理和回滚

## ⚠️ 注意事项

-   防火墙端口开放\
-   合理选择容器数量\
-   选择可正常访问的伪装域名\
-   备份密钥与链接

## 🔍 故障排查

    systemctl status docker

-   检查端口占用\
-   检查域名解析

## 📝 更新日志

  版本   内容
  ------ ----------------------------
  v1.0   基础批量部署功能
  v1.1   增加端口冲突检测、域名循环
  v1.2   优化错误处理与速度

## 📜 声明

请遵守当地法律法规，仅用于合法用途。
