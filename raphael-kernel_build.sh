#!/bin/bash
set -e  # 遇到错误立即退出

# 克隆指定版本的内核源码
rm -rf ./*.deb
rm -rf ./linux-upstream*

export CCACHE_DIR="$HOME/.ccache"
export PATH="/usr/lib/ccache:$PATH"
export CCACHE_MAXSIZE=10G

git config --global user.name "gavin liu"
git config --global user.email "1824306327@163.com"

if [ -z "$1" ]; then
    echo "错误: 请提供分支后缀参数，例如: $0 v1"
    exit 1
fi

BRANCH="raphael-$1"
REPO_URL="https://github.com/GengWei1997/linux.git"
TARGET_DIR="linux"

if [ -d "$TARGET_DIR" ]; then
    echo "目录 '$TARGET_DIR' 已存在，将强制恢复到远程分支 '$BRANCH' 的最新状态..."
    cd "$TARGET_DIR" || { echo "无法进入目录 $TARGET_DIR"; exit 1; }

    # 确保是 Git 仓库
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "错误: $TARGET_DIR 不是一个 Git 仓库，请手动处理。"
        exit 1
    fi

    # 拉取远程最新信息
    git fetch origin "$BRANCH" --depth 1 || { echo "fetch 失败"; exit 1; }

    # 强制重置到远程分支，丢弃所有本地提交和修改
    git reset --hard "origin/$BRANCH" || { echo "reset 失败"; exit 1; }

    # 可选：删除未跟踪的文件和目录（彻底清理工作区）
    git clean -fd

    echo "已成功同步到远程分支 $BRANCH 的最新代码。"
    cd - > /dev/null
else
    echo "目录 '$TARGET_DIR' 不存在，开始浅克隆分支 '$BRANCH' ..."
    git clone "$REPO_URL" --branch "$BRANCH" --depth 1 "$TARGET_DIR"
    if [ $? -eq 0 ]; then
        echo "克隆完成。"
    else
        echo "克隆失败，请检查网络或分支名是否正确。"
        exit 1
    fi
fi

# 应用补丁
patch linux/scripts/package/builddeb < patchs/builddeb.patch
patch linux/arch/arm64/boot/dts/qcom/sm8150-xiaomi-raphael.dts < patchs/dts.patch
patch linux/arch/arm64/boot/dts/qcom/sm8150.dtsi < patchs/sm8150.dts.patch
patch linux/sound/soc/qcom/sm8150.c < patchs/sm8150-snd.patch
patch linux/sound/soc/qcom/qdsp6/q6dsp-lpass-ports.c < patchs/q6dsp-lpass-ports.c.patch
patch linux/sound/soc/codecs/tfa9872.c < patchs/tfa9872.patch
patch linux/scripts/package/mkdebian < patchs/mkdebian.patch
cd linux
git add .
git commit -m "patches: builddeb dts mkdebian"

# 生成内核配置
cp ../raphael.config arch/arm64/configs/

make -j$(nproc) ARCH=arm64 LLVM=-22 defconfig raphael.config

# 编译内核
make -j$(nproc) ARCH=arm64 LLVM=-22 deb-pkg DPKG_FLAGS="-d"

cd ..

# 重命名生成的 deb 包
IMAGE_DEB=$(ls -1 linux-image-*.deb 2>/dev/null | grep -v '\-dbg_' | head -n1)
HEADERS_DEB=$(ls -1 linux-headers-*.deb 2>/dev/null | head -n1)

if [ -n "$IMAGE_DEB" ]; then
  mv "$IMAGE_DEB" linux-image-xiaomi-raphael.deb
fi
if [ -n "$HEADERS_DEB" ]; then
  mv "$HEADERS_DEB" linux-headers-xiaomi-raphael.deb
fi

# 清理源码目录
# rm -rf linux

# 构建 firmware 和 alsa deb 包
dpkg-deb --build --root-owner-group firmware-xiaomi-raphael
dpkg-deb --build --root-owner-group alsa-xiaomi-raphael

# 创建 output 目录并移动最终 4 个 deb 包
mkdir -p output
mv -f linux-image-xiaomi-raphael.deb output/ 2>/dev/null || true
mv -f linux-headers-xiaomi-raphael.deb output/ 2>/dev/null || true
mv -f firmware-xiaomi-raphael.deb output/ 2>/dev/null || true
mv -f alsa-xiaomi-raphael.deb output/ 2>/dev/null || true

rm -rf ./*.deb
rm -rf ./linux-upstream*

# 降低 deb 包权限
chmod 644 output/*.deb 2>/dev/null
