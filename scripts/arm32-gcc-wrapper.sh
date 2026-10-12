#!/bin/bash
#
# ARM32 GCC 包装脚本 — 供 arch/arm64/kernel/vdso32 使用
#
# 背景:
#   本内核树在 xiaomi/sdm710-common.config 里显式打开了 CONFIG_COMPAT_VDSO=y,
#   所以必须构建 32 位 vDSO。而 arch/arm64/kernel/vdso32/Makefile 在
#   cc-name=clang 时会组出:
#       clang --target=arm-linux-gnueabi --gcc-toolchain=... --prefix=...
#   但 ZyCromerZ 的 clang 包里自带一个宿主 x86_64 的 ld,clang 会优先在自己
#   所在目录找链接器,于是报:
#       ld: unrecognised emulation mode: armelf_linux_eabi
#
#   该 Makefile 本身也支持非 clang 路径(CC_ARM32 := $(CROSS_COMPILE_ARM32)$(cc-name)),
#   而命令行变量优先于 Makefile 赋值,所以把 CC_ARM32 指到本脚本,用真正的
#   ARM32 GCC 构建这个很小的独立 blob。
#
# 为什么需要包装:
#   内核在 cc-name=clang 时会往 KBUILD_CPPFLAGS / KBUILD_CFLAGS 注入 clang 专有标志
#   (-Qunused-arguments、-mno-global-merge、-fcatch-undefined-behavior 等),
#   GCC 遇到不认识的参数会直接报错。与其把标志名逐个硬编码,这里在失败时解析
#   GCC 的 "unrecognized command-line option 'X'" 报错,剥掉 X 后重试。
#   vdso32 只有两个目标文件加一次链接,重试代价可以忽略。
#
set -u

args=("$@")

while :; do
  # 必须同时保留 stdout!vdso32/Makefile 第 30 行靠
  #   $(shell $(CC_ARM32) -print-file-name=include)
  # 的 stdout 取头文件目录,丢掉它会导致 -isystem 收到空值、
  # 进而报 "asm/linkage.h: No such file or directory"。
  out=$(arm-linux-gnueabi-gcc "${args[@]}" 2>&1)
  rc=$?

  if [ $rc -eq 0 ]; then
    printf '%s' "$out"
    exit 0
  fi

  # GCC 的报错可能带 Unicode 引号 ‘X’,也可能带 ASCII 引号 'X'
  bad=$(printf '%s\n' "$out" \
        | grep -oE "unrecognized command-line option [^ ]+" \
        | head -1 \
        | sed -E "s/.*option [‘'\"]?//; s/[’'\"]?$//")

  if [ -z "$bad" ]; then
    # 不是未知参数导致的失败 —— 原样报告
    printf '%s\n' "$out" >&2
    exit $rc
  fi

  new=()
  for a in "${args[@]}"; do
    [ "$a" = "$bad" ] || new+=("$a")
  done

  if [ ${#new[@]} -eq ${#args[@]} ]; then
    # 找不到可以剥离的参数,避免死循环
    printf '%s\n' "$out" >&2
    exit $rc
  fi

  echo "  [arm32-gcc-wrapper] 剥离 GCC 不认的参数: $bad" >&2
  args=("${new[@]}")
done
