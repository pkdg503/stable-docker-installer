# Stable Docker Installer

Debian/Ubuntu 系统最稳定 Docker 一键安装脚本

## 🚀 特性

- ✅ 安装经过验证的稳定版本
- 🔒 禁用自动更新
- ⚙️ 优化 Docker 守护进程配置
- 🛡️ 生产环境就绪

## 📥 一键安装

```bash
# 方法一：直接下载执行
curl -fsSL https://raw.githubusercontent.com/你的用户名/stable-docker-installer/main/install-stable-docker.sh -o install-docker.sh
chmod +x install-docker.sh
sudo ./install-docker.sh

# 方法二：直接运行（不保存文件）
curl -fsSL https://raw.githubusercontent.com/你的用户名/stable-docker-installer/main/install-stable-docker.sh | sudo bash
```

## 🔧 手动安装步骤

如果一键安装失败，可以分步执行：

```bash
# 1. 下载脚本
wget https://raw.githubusercontent.com/你的用户名/stable-docker-installer/main/install-stable-docker.sh

# 2. 添加执行权限
chmod +x install-stable-docker.sh

# 3. 运行安装
sudo ./install-stable-docker.sh
```

## 📋 系统要求

- Debian 9+ 或 Ubuntu 16.04+
- 需要 root 权限
- 稳定的网络连接

## 🛠️ 故障排除

如果遇到问题：

1. 检查网络连接
2. 确保有 root 权限
3. 查看系统日志：`journalctl -u docker`

## 📄 许可证

MIT License
