# AI-Env-Ark

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python 3.11](https://img.shields.io/badge/python-3.11-blue.svg)](https://www.python.org/)
[![PyTorch 2.2](https://img.shields.io/badge/PyTorch-2.2.1-EE4C2C.svg)](https://pytorch.org/)
[![CUDA 11.8](https://img.shields.io/badge/CUDA-11.8-76B900.svg)](https://developer.nvidia.com/cuda-toolkit)

本项目主要意在彻底解决国内诸多云服务器无法连接 Github、NVCC 版本/Python 版本/Glibc 版本/CUDA 版本等各类版本冲突、Flash-Attention 编译缓慢/安装困难，甚至没有 conda 等以及其他各种可能发生的问题。

AI-Env-Ark 采用 `Conda (底层 C 库隔离) + uv (极速构建) + 纯离线 Wheel 预编译` 的融合架构。只需在配置良好、网络通畅的母机上构建一次即可。采用 `Python 3.11 + PyTorch 2.2.1 + cu118` 强兼容性组合（可以自行修改），目标机器显卡驱动需最低支持 CUDA 11.8 及以上。

## Quick Start

整个流程分为两步：在**母机**上构建，在**目标机器**上部署。

### Step 1: 方舟构建

找一台预装了 miniconda、网络通畅的 Linux 机器（建议 Ubuntu 20.04/22.04），克隆本仓库：

```bash
git clone https://github.com/starx237/AI-Env-Ark.git
cd AI-Env-Ark.git
```

根据你的项目需求，修改 `ultra_setup.sh` 顶部的配置区（如需打包私有库，请修改 `VEOMNI_SOURCE`，这里以 VeOmni 为例）：

```bash
# ==========================================
# 1. 核心配置区
# ==========================================
ENV_NAME="ark"
PYTHON_VER="3.11"
TORCH_VER="2.2.1"
CUDA_TAG="cu118"

# 私有库/内部库的 Git 链接 (支持国内镜像加速）
VEOMNI_SOURCE="git+https://mirror.ghproxy.com/https://github.com/ByteDance-Seed/VeOmni.git"
```

你还可以修改 requirements_base.txt，若不创建此文件则为默认值。

运行构建脚本：

```bash
bash ultra_setup.sh
```

*(💡 提示：如果中途因网络问题报错，直接再次运行该命令即可，脚本会自动从断点处继续。)*

构建完成后，你将得到一个名为 `DL_Deploy_Bundle.tar.gz` 的母舰包。

### Step 2: 在“目标机器”上部署

将 `DL_Deploy_Bundle.tar.gz` 通过 U盘、SCP 或内网传输到任何一台目标机器上。

**目标机器无需联网，无需安装 Conda，不需要 Root 权限。**

```bash
# 1. 解压
tar -xzf DL_Deploy_Bundle.tar.gz
cd DL_Deploy_Bundle

# 2. 一键执行部署脚本
./install.sh
```

部署脚本会自动修复绝对路径，所有安装均在离线下进行。

```bash
source ~/my_dl_env/bin/activate
python -c "import torch, flash_attn; print('Success!')"
```

## Advanced Usage

### 1. 强制重新构建

如果你修改了配置，想要清除断点记录从头开始构建：

```bash
bash build_deploy_bundle.sh --reset
```

### 2. 更新私有业务代码

如果你只修改了业务代码（如 `VeOmni`），不想重新打包 Conda 环境：
1. 在母机上运行 `uv pip wheel "git+https://..." --wheel-dir ./offline_wheels --no-deps`
2. 将新生成的 `.whl` 文件拷到目标机器的 `DL_Deploy_Bundle/offline_wheels` 目录下。
3. 在目标机器激活环境，运行 `uv pip install --force-reinstall offline_wheels/新包名.whl` 即可更新。
