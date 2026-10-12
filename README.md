# Droidspaces Kernel Builder — Xiaomi Mi 9 SE (grus) / crDroid 12 UNOFFICIAL

用 GitHub Actions 从 **Rocky7842 的内核源码**出发,自动编出一个**带 Droidspaces 支持、且保留 KernelSU root** 的内核卡刷包。

> 同一位维护者的另外两台设备已经有可用的同类仓库:
> [droidspaces-psyche-kernel](https://github.com/Yang-XianChen/droidspaces-psyche-kernel)(小米 12X)、
> [droidspaces-nabu-kernel](https://github.com/Yang-XianChen/droidspaces-nabu-kernel)(小米平板 5)。

---

## 这台设备的关键事实(已核实)

| 项 | 值 |
|---|---|
| 设备 | Xiaomi Mi 9 SE,代号 **grus**,平台 **sdm710/sdm670** |
| ROM | crDroid 12(Android 16),**非官方**、带 OTA,帖子明确 "Integrated KSU from rsuntk" |
| 内核 | **4.9.337** |
| 内核源码 | `Rocky7842/android_kernel_xiaomi_sdm710` @ **`lineage-23.2-ksu`** |
| Root | KSU 需用 **`-ksu` 分支**(主分支 `lineage-23.2` 不带);`xiaomi/sdm710-common.config` 里已有 `CONFIG_KSU=y` + `CONFIG_KSU_MANUAL_HOOK=y`。该树**没有 susfs** |
| 引导 | header **v2**、镜像名 **`Image`**(raw)、**A-only(无 A/B 槽)**、**有独立 recovery 分区**、boot 分区 64 MB |
| defconfig 拼接 | `sdm670-perf_defconfig` + `xiaomi/sdm710-common.config` + `xiaomi/grus.config` |

> ⚠️ `arch/arm64/configs/vendor/sdm670-perf_defconfig` 只是一个内容为 `../sdm670-perf_defconfig`
> 的**重定向存根**。真正的 defconfig 是 `arch/arm64/configs/sdm670-perf_defconfig`,本工作流用的就是它。

**硬阻断与另两台一致**:真正的 defconfig 里写着 `# CONFIG_PID_NS is not set`,
且 `SYSVIPC` / `POSIX_MQUEUE` / `DEVTMPFS` / `VETH` 等都没开 —— 容器起不来,必须自己编内核。

---

## ⚠️ 一个本机特有的注意点:4 个 loadable module

这台是三个设备里**唯一有 `=m` 模块**的(另两台是 0 个):

```
CONFIG_MSM_RDBG=m            # 远程调试
CONFIG_DVB_MPQ=m             # 移动电视
CONFIG_DVB_MPQ_DEMUX=m
CONFIG_QCOM_LLCC_PERFMON=m   # 性能监控
```

该树 `CONFIG_MODVERSIONS=y`,而我们打开的 `SYSVIPC` / `IPC_NS` 会改变 `struct task_struct`
等核心结构的布局,从而改变导出符号的 CRC —— 这 4 个 `.ko` 可能因此**加载失败**。

它们都是调试/外围驱动,通常不在开机加载路径上,失败一般只会在 dmesg 里留一行
`disagrees about version of symbol`。刷完后可以这样确认:

```sh
adb shell su -c 'dmesg | grep -i "disagrees about version"'
```

如果有,且没有实际功能异常,可以忽略;要彻底干净就得把 ROM 的 `/vendor/lib/modules`
里对应 4 个 `.ko` 一并替换(需要重挂 vendor 或用模块覆盖)。

---

## 与 OTA 的关系

这是**非官方但带 OTA** 的 ROM。刷了自定义内核后,**OTA 更新会把 boot 分区换回官方内核**,
Droidspaces 支持随之消失,每次 OTA 后需要重刷本仓库产出的包。

---

## 一次性搭建

1. GitHub 新建空仓库,例如 `droidspaces-grus-kernel`(**不要**勾模板)。
2. 按下述结构推上去:

```
droidspaces-grus-kernel/
├── .github/workflows/build.yml
├── anykernel/anykernel.sh
├── config/grus-droidspaces.config
└── README.md
```

```bash
git init && git add -A
git commit -m "Droidspaces kernel builder for grus"
git branch -M main
git remote add origin https://github.com/<你的用户名>/droidspaces-grus-kernel.git
git push -u origin main
```

---

## 运行构建

**Actions → Build Droidspaces Kernel (Xiaomi Mi 9 SE / grus) → Run workflow**

| 输入 | 默认 | 说明 |
|---|---|---|
| `kernel_repo` | `Rocky7842/android_kernel_xiaomi_sdm710` | 不用改 |
| `kernel_ref` | **`lineage-23.2-ksu`** | **不要改成 `lineage-23.2`,会丢 root**。也可填具体提交号 |
| `publish_release` | `true` | 构建完发到 Releases |

**对齐版本**:Rocky 的分支会被 rebase,所以设备上跑的那个提交常常已不是任何分支的祖先。
工作流对非分支名会自动走 codeload tarball(即使提交已被 rebase 也能取到)。
从设备读精确提交:

```sh
adb shell uname -r        # 4.9.337-perf-g<提交号前12位>
```

把那个 12 位提交号填进 `kernel_ref` 即可做到与设备完全同源。

---

## 刷入

产出是标准 AnyKernel3 卡刷包(**只替换 boot 里的 kernel**,保留 ramdisk 与 dtb,不动 dtbo 与 recovery)。

三条路按推荐排序:

1. **root 直接 dd**(最直接,和 12X 一样):
   ```sh
   adb shell su -c 'dd if=/dev/block/by-name/boot of=/sdcard/boot_stock.img'   # 先备份!
   adb push Droidspaces-grus-*.zip /sdcard/
   # 用任意 AK3 刷入器刷,或自行重打包后 dd 回 boot
   ```
2. **recovery 卡刷**:grus 有独立 recovery 分区,可以直接在 TWRP 里刷 AK3 zip。
3. **fastboot**:解出 `Image`,用备份的 boot.img 重打包后 `fastboot flash boot`。

---

## 刷完验收

```sh
adb shell cat /proc/version                        # 应是新内核
adb shell su -c id                                 # 应返回 uid=0(root 还在)
adb shell 'ls -l /proc/self/ns/'                   # 必须能看到 pid 和 ipc
adb shell su -c 'zcat /proc/config.gz | grep -E "PID_NS|IPC_NS|SYSVIPC|DEVTMPFS"'
adb shell su -c 'dmesg | grep -i "disagrees about version"'   # 见上文那 4 个模块
```

然后装 **Droidspaces APK** → 授权 root → 装后端 → 重启 →
**Settings → Requirements → Check Requirements** 全绿。

装容器时发行版**只能用 systemd 258 之前的**:Ubuntu 22.04/24.04、Debian 12/13、
Alpine(OpenRC)、Void、OpenWrt —— Arch / Fedora 这类滚动版起不来(内核缺 `openat2`)。
4.9 内核同样受此限制。

---

## 这个方案改动了什么(透明清单)

1. **追加配置**:把 `config/grus-droidspaces.config` 追加到 defconfig 拼接末尾,
   合并成 `grus_ds_defconfig` 使用。核心是打开原本被显式关闭的 `CONFIG_PID_NS`,
   补上 `SYSVIPC` / `POSIX_MQUEUE` / `IPC_NS`(前两者是 `IPC_NS` 的 Kconfig 前置)与 `DEVTMPFS`,
   并按需打开 `USER_NS`、`CGROUP_PIDS`、`MACVLAN`、`TMPFS_XATTR`、`VETH` 等。
2. **打官方 non-GKI 补丁**。实测:
   - `02.fix_restore cgroup file prefix handling` → `kernel/cgroup/cgroup.c` 应可干净应用。
   - `01.fix_kernel_panic_in_xt_qtaguid` → 目标 `net/netfilter/xt_qtaguid.c` **在该树中不存在**,
     自动跳过并告警(与 12X / nabu 相同)。
3. **编译后只取 `Image`** 打进 AnyKernel3,不动 dtb / dtbo / recovery 分区。
