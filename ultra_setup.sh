#!/bin/bash
# 遇到错误立即停止
set -e
# ==========================================
# 1. 核心配置区
# ==========================================

ENV_NAME="ark"
PYTHON_VER="3.11"
TORCH_VER="2.4.0"
CUDA_TAG="cu118"
FLASH_ATTN_VER="2.6.3"   # 匹配 2.4.0 的 Flash-Attention
VEOMNI_SOURCE="git+https://mirror.ghproxy.com/https://github.com/ByteDance-Seed/VeOmni.git@9b91e164bea9e17f17ed490aab5e076c2335ca25"

BUNDLE_DIR="./DL_Deploy_Bundle"
WHEEL_DIR="$BUNDLE_DIR/offline_wheels"
STATE_FILE="$BUNDLE_DIR/.build_state.log"
REQ_FILE="requirements_base.txt"

# ==========================================
# 2. 断点重续
# ==========================================

mkdir -p "$WHEEL_DIR"

if [ "$1" == "--reset" ]; then
echo "⚠️ 收到 --reset 指令，清除历史构建状态..."
rm -f "$STATE_FILE"
rm -rf "$BUNDLE_DIR/env_offline.tar.gz"
rm -rf "$BUNDLE_DIR/DL_Deploy_Bundle.tar.gz"
fi

touch "$STATE_FILE"

is_done() { grep -q "^$1$" "$STATE_FILE" 2>/dev/null; }
mark_done() {
echo "$1" >> "$STATE_FILE"
echo "✅ 步骤 [$1] 已完成并保存断点。"
echo "--------------------------------------------------"
}

echo "🚀 启动构建协议..."
echo "--------------------------------------------------"

# ==========================================
# 步骤 1: 创建 Conda 隔离环境
# ==========================================

STEP="step1_conda_env"
if ! is_done "$STEP"; then
echo "🛠️ [1/8] 创建 Conda 隔离环境 (强制南京大学镜像源单源加速)..."
if ! command -v conda &> /dev/null; then echo "❌ 未检测到 Conda!"; exit 1; fi
CONDA_BASE=$(conda info --base)
source "$CONDA_BASE/etc/profile.d/conda.sh"

conda env remove -n $ENV_NAME -y 2>/dev/null || true
conda create -n $ENV_NAME python=$PYTHON_VER aria2 sysroot_linux-64=2.17 gcc_linux-64 gxx_linux-64 \
    --override-channels \
    -c https://mirror.nju.edu.cn/anaconda/cloud/conda-forge/ \
    -c https://mirror.nju.edu.cn/anaconda/pkgs/main/ \
    -y
mark_done "$STEP"

else
CONDA_BASE=$(conda info --base)
source "$CONDA_BASE/etc/profile.d/conda.sh"
echo "⏭️ [1/8] Conda 环境已创建，跳过。"
fi

conda activate $ENV_NAME

# ==========================================
# 步骤 2: 安装 uv
# ==========================================

STEP="step2_install_uv"
if ! is_done "$STEP"; then
echo "📦 [2/8] 安装极速包管理器 uv..."
pip install uv -i https://mirror.nju.edu.cn/pypi/web/simple
mark_done "$STEP"
else
echo "⏭️ [2/8] uv 已安装，跳过。"
fi

# ==========================================
# 步骤 3: 安装 PyTorch
# ==========================================

STEP="step3_install_pytorch"
if ! is_done "$STEP"; then
echo "🔥 [3/8] 安装 PyTorch $TORCH_VER ($CUDA_TAG)..."
uv pip install torch==$TORCH_VER torchvision torchaudio \
--index-url "https://mirror.nju.edu.cn/pytorch/whl/$CUDA_TAG" \
--extra-index-url "https://mirrors.aliyun.com/pypi/simple/"
mark_done "$STEP"
else
echo "⏭️ [3/8] PyTorch 已安装，跳过。"
fi

# ==========================================
# 步骤 4: 安装深度学习全家桶 (基于 requirements_base.txt)
# ==========================================

STEP="step4_install_dl_ecosystem"
if ! is_done "$STEP"; then
echo "📚 [4/8] 基于 $REQ_FILE 安装深度学习全家桶..."

# 防御机制
if [ ! -f "$REQ_FILE" ]; then
    echo "⚠️ 未找到 $REQ_FILE，自动生成默认依赖清单..."
    cat << 'EOF' > "$REQ_FILE"
numpy
pandas
scipy
scikit-learn
opencv-python-headless
Pillow
albumentations
timm
diffusers
transformers>=5.9.0
accelerate
datasets
huggingface_hub
modelscope
peft
bitsandbytes
sentencepiece
protobuf
safetensors
tiktoken
einops
opt_einsum
flash-linear-attention
liger-kernel
tensorboard
wandb
matplotlib
tqdm
pyyaml
evaluate
torchdata
blobfile
ninja
packaging
psutil
pydantic
ipython
EOF
fi

# 核心：使用 uv 极速读取并解析 requirements_base.txt
uv pip install -r "$REQ_FILE" --index-url "https://mirrors.aliyun.com/pypi/simple/"
mark_done "$STEP"

else
echo "⏭️ [4/8] 深度学习全家桶已安装，跳过。"
fi

# ==========================================
# 步骤 5: 安装 Flash-Attention
# ==========================================

STEP="step5_install_flash_attn"
if ! is_done "$STEP"; then
echo "⚡ [5/8] 安装 Flash-Attention (预编译包)..."

# 提取 Python 和 Torch 的版本标签
PY_TAG="cp${PYTHON_VER//./}" # 3.11 -> cp311

TORCH_TAG=$(echo $TORCH_VER | cut -d'.' -f1,2) # 2.4.0 -> 2.4
FA_CUDA_TAG=$([ "$CUDA_TAG" == "cu118" ] && echo "cu118" || echo "cu122")

WHL_NAME="flash_attn-${FLASH_ATTN_VER}+${FA_CUDA_TAG}torch${TORCH_TAG}cxx11abiFALSE-${PY_TAG}-${PY_TAG}-linux_x86_64.whl"
WHL_URL="https://ghproxy.net/https://github.com/Dao-AILab/flash-attention/releases/download/v${FLASH_ATTN_VER}/${WHL_NAME}"

echo "🔗 正在拉取: $WHL_NAME"
uv pip install "$WHL_URL"
mark_done "$STEP"

else
echo "⏭️ [5/8] Flash-Attention 已安装，跳过。"
fi

# ==========================================
# 步骤 6: 编译 VeOmni 为离线包
# ==========================================

STEP="step6_build_veomni"
if ! is_done "$STEP"; then
echo "📦 [6/8] 将 VeOmni 编译为纯离线安装包..."
if [ -e "$VEOMNI_SOURCE" ] || [[ "$VEOMNI_SOURCE" == http* ]] || [[ "$VEOMNI_SOURCE" == git+* ]]; then
echo "🔗 正在从源码构建 Wheel 包: $VEOMNI_SOURCE"

    pip wheel "$VEOMNI_SOURCE" --wheel-dir "$WHEEL_DIR" --no-deps
    
    echo "✅ VeOmni 离线包已生成至: $WHEEL_DIR"
else
    echo "⚠️ 未找到 VeOmni 源码 ($VEOMNI_SOURCE)，跳过编译。"
fi
mark_done "$STEP"

else
echo "⏭️ [6/8] VeOmni 离线包已处理，跳过。"
fi

# ==========================================
# 步骤 7: 打包 Conda 环境
# ==========================================

STEP="step7_conda_pack"
if ! is_done "$STEP"; then
echo "🧳 [7/8] 正在打包核心环境..."
conda install conda-pack -c conda-forge -y
conda pack -n $ENV_NAME -o "$BUNDLE_DIR/env_offline.tar.gz" --force
mark_done "$STEP"
else
echo "⏭️ [7/8] Conda 环境打包已完成，跳过。"
fi

# ==========================================
# 步骤 8: 生成部署脚本与最终环境包
# ==========================================

STEP="step8_final_bundle"
if ! is_done "$STEP"; then
echo "🚢 [8/8] 生成部署脚本与最终环境包..."

cat << 'EOF' > "$BUNDLE_DIR/install.sh"
#!/bin/bash
set -e
echo "🚀 开始在目标机器部署环境..."

ENV_DIR="$HOME/my_dl_env"
mkdir -p "$ENV_DIR"

echo "1️⃣ 解压核心环境..."
tar -xzf env_offline.tar.gz -C "$ENV_DIR"

echo "2️⃣ 修复环境路径..."
source "$ENV_DIR/bin/activate"
"$ENV_DIR/bin/conda-unpack"

echo "3️⃣ 安装离线本地包 (VeOmni)..."
if [ "$(ls -A offline_wheels 2>/dev/null)" ]; then
uv pip install offline_wheels/*.whl
echo "✅ 本地包安装完成！"
fi

echo "🎉 部署完毕！"
echo "👉 请运行: source $ENV_DIR/bin/activate"
EOF
chmod +x "$BUNDLE_DIR/install.sh"

tar -czf DL_Deploy_Bundle.tar.gz -C ./ DL_Deploy_Bundle
mark_done "$STEP"

else
echo "⏭️ [8/8] 最终环境包已存在，跳过。"
fi

echo "========================================================"
echo "🎉 构建全部完成！"
echo "📦 请将 DL_Deploy_Bundle.tar.gz 拷贝到任何新机器上。"
echo "========================================================"
