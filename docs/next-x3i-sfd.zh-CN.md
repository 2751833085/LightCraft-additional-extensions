# 交接：让 LightCraft 支持适马 DP2 Quattro 的 SFD（X3I）照片

给新会话用的完整上下文。本仓库此前的全部工作已经在 `patches/0001–0008`，用 `scripts/build.sh` 就能还原。

## 新会话开场可以直接粘贴这段

> 请先读 `docs/next-x3i-sfd.zh-CN.md`、`README.md` 和 `docs/research-raw-formats-and-extensions.zh-CN.md`，然后按“方案 A”开始。我的 X3I 样张在 `<样张所在的文件夹>`。用中文和我沟通。

## 背景

- SFD（Super Fine Detail）模式：三脚架上连拍 7 张，每张相差 1 EV（±3 EV），存成一个 `.X3I`，本质是 7 个 X3F 拼在一起，单个约 300–400 MB。
- LightCraft v0.20.0 的现状：
  - `.x3i` 不在导入扩展名列表里（`crates/engine/src/import/files.rs` 第 20 行附近只有 `x3f`）；
  - `.x3f` 只能显示内嵌的 8 位 JPEG：`crates/raw/src/lib.rs` 用 `FOVb` 识别出 `RawFormat::X3f`，但解码返回 “X3f files are not decoded yet”；预览来自 `crates/raw/src/preview.rs` 扫描到的最大 JPEG；
  - 读不到相机型号、ISO、拍摄时间（`crates/meta/src/container.rs` 没有 X3F 分支）；
  - 原生支持 LinearRaw（三通道线性）DNG，适合 Foveon；
  - HDR 合并（`crates/engine/src/merge.rs`，帧读取在 `crates/merge/src/frame.rs` 的 `load_frame_with`，走 `lightcraft_raw::decode`）理论上能吃 LinearRaw DNG，未实测；
  - AI 降噪只支持拜耳传感器，对 Foveon 不可用。

## 方案（已和用户讨论过）

### 方案 A（推荐，先做）：外部转换器

- 转换器：[sagwaco/x3fuse-core](https://github.com/sagwaco/x3fuse-core) 的 `x3f_extract`。Rust 写的，Apache-2.0 许可，支持 Quattro 和 X3I（SFD）合并，输出 LinearRaw DNG，内置 NLM/BM3D 降噪（`-denoise 0-10`、`-denoiser nlm|bm3d`）。
- 它含 C shim 和大量 `unsafe`，部分处理阶段来自对 SPP 的反编译记录。所以**只能作为外部进程调用，不能并进 LightCraft 进程**（上游 AGENTS.md 要求纯 Rust、不能有 unsafe、clean room）。
- 它的 GUI（X3Fuse，GPL-3）不支持 X3I，要用命令行。
- 要做的补丁（界面层和导入层，不改解码器和渲染管线）：
  1. 导入扩展名加 `x3i`。导入后的 X3I 和 X3F 一样标为“仅预览”，先扫内嵌 JPEG，需确认 X3I 里有没有。
  2. 设置 ▸ 常规（或导入）加 “X3F/X3I 转换器” 路径，默认找 PATH 里的 `x3f_extract`。参考 Edit In 外部编辑器的写法：`crates/ui-egui/src/menus/files.rs`、`apps/lightcraft/src/editors.rs`、`check_editor`。
  3. 命令 `photo.convertFoveon {ids}`，菜单名“转换为 DNG（Foveon）”：后台任务调用转换器 → 在原文件旁写 `<名称>.dng` → 导入 → 和原片堆叠，DNG 在顶部 → 拷贝评分、旗标、关键词。语义对齐上游的 `photo.convertToDng`（写 DNG 并 relink）。注意别覆盖已有文件。
  4. 可选：导入时自动转换的开关。
  5. 测试：用一个假的转换器脚本，headless 测试命令、堆叠和错误提示。
- 约 3–5 天。

### 方案 A2（可选）：拆成 7 帧，用 LightCraft 自己的 HDR 合并

- 前提：需要实测 `x3f_extract` 能否把 X3I 的每一帧单独导出成 DNG，以及 LightCraft 的 HDR 合并能否接受 LinearRaw DNG。
- 好处：合成用的是 LightCraft 的 HDR 合并（带去鬼影），输出浮点 DNG。

### 方案 B（暂不做）：原生 Foveon 解码

- 不是“重构”，但要在 `lightcraft_raw` 里新写一个大模块：
  - FOVb 容器：有 2004 年的公开规范；
  - TRUE III / Quattro 压缩：没有公开规范；
  - CAMF 校准数据：没有公开文档；
  - 1:1:4 上采样；
  - Foveon 颜色标定；
  - PROP 元数据；
  - 多帧文件的概念：现在的解码接口是一个文件一张图。
- 必须按上游 clean-room 规则实现：不能读 x3fuse、Kalpanika、LibRaw 的源码，只能当黑盒对照。工作量以月计。

### 方案 C（零代码，先在相机上看）

dp Quattro 固件 2.00+ 支持机内 DNG。有资料说 SFD 也能存 DNG，但没有核实。看看相机菜单里 SFD 模式下能否选 DNG。

## 拿到样张后要先核实的

1. `x3f_extract` 对 X3I 的合成效果、颜色（和 SPP 比）、高光（已知可能偏黄绿），以及几个降噪档位的效果。
2. 能否逐帧导出（决定 A2 是否可行）。
3. 转出的 DNG 在 LightCraft 里能否正常显影：PhotometricInterpretation、BaselineExposure、色彩矩阵。
4. X3I 里有没有可用的内嵌 JPEG（决定导入后的缩略图）。
5. 普通 X3F（单张）同样走一遍。

## 开发环境怎么还原

```bash
scripts/build.sh --work ~/lcx          # 取 v0.20.0、打上 patches/*.patch、编译
cd ~/lcx/lightcraft                    # 分支 lcx：每个补丁是一个提交
git checkout -b feat/foveon            # 在这里开发
CRAFT_FONTS_DIR=~/lcx/craft-fonts cargo test -p lightcraft-ui-egui   # 全套界面测试约 15 分钟
# 完成后，把提交整理到 lcx 上，重新生成补丁：
git format-patch v0.20.0..HEAD -o <本仓库>/patches   # 先删掉旧的 patches/*.patch
```

- 无界面截图：`lightcraft-cli snapshot --demo --script x.jsonl --size 1600x1000`，用 `LIGHTCRAFT_LANGUAGE=zh-hans`。
- 新界面文字要加进 `crates/ui-egui/locales/zh-hans.json` 和 `zh-hant.json`，追加在文件末尾。
- 提交和推送到分支 `ccr-45d7b05e-5o74gq`。README 的功能、用法、已验证 / 未验证几节要同步更新。

## 其他待办（用户说暂时不做）

- GT-2 附加镜暗角（补丁 0008）已完成，等用户拍平场照后用真实文件验证。见 `docs/gt2-converter-vignetting.zh-CN.md`。
