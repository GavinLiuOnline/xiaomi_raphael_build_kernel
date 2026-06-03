#!/bin/bash
set -e

KERNEL_VERSION="${1:-7.0}"
IMAGE_NAME="kernel-builder"

echo "============================================"
echo "xiaomi raphael 内核 Docker 构建脚本"
echo "内核版本: ${KERNEL_VERSION}"
echo "============================================"

# 构建镜像（仅首次需要，之后除非改依赖否则不用重建）
if ! docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
    echo ""
    echo "[1/2] 首次构建 Docker 镜像..."
    docker build -t "${IMAGE_NAME}" .
else
    echo ""
    echo "[1/2] Docker 镜像已存在，跳过构建"
fi

echo ""
echo "[2/2] 开始编译内核..."
docker run --rm \
    -v "$(pwd):/build" \
    -v "ccache-raphael:/root/.ccache" \
    "${IMAGE_NAME}" \
    bash /build/build-in-docker.sh "${KERNEL_VERSION}"

echo ""
echo "============================================"
echo "构建完成！"
ls -lh *.deb 2>/dev/null || echo "（未找到 deb 包）"
echo "============================================"
