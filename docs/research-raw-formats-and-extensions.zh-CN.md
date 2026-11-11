# LightCraft：理光 / 飞思 IIQ / 适马 X3F 支持情况与扩展方案调研

- 调研对象：[storytold/lightcraft](https://github.com/storytold/lightcraft) `main` @ `c2e9c45`（2026-11-10，v0.18.0 之后）
- 调研方法：静态阅读源码与仓库文档，查阅外部资料（厂商页面、开源解码器仓库与许可证）。核心结论都经过一轮独立核查。
- **局限**：没有编译或运行 LightCraft，也没有拿真实的 IIQ、X3F、GR IV 样张实测。文中“未验证”的地方都需要用真实文件确认。
- 下文代码位置都相对于上游仓库根目录，行号以 `c2e9c45` 为准。

---

## 0. 结论速览

| 需求 | LightCraft 原生现状 | 结论 |
|---|---|---|
| **理光 GR 系列（DNG）** | ✅ 原生解码，可以完整做 raw 编辑。GR、GR II、GR IIIx 用真实样张验证过并与机内 JPEG 比对；GR III 能解码；GR IV、GR IV Monochrome、GR III/IIIx HDF 走通用 DNG 解码器，但没有验证 | 不需要扩展 |
| **理光时代的宾得（PEF / DNG）** | ✅ 原生解码。K-3 III、K-1、K-70、KF 的 PEF 和 KP、645Z、K-1 II 的 DNG 有真实样张测试。PEF 文件里没有色彩矩阵，颜色靠逐张拟合机内 JPEG；Pixel Shift 多帧不会合成 | 不需要扩展，**建议改拍 DNG** |
| **飞思 Phase One IIQ** | ❌ **只能显示预览（preview_only）**。没有传感器解码器，只能编辑文件里内嵌的 JPEG；没有 JPEG 时只能用 IFD0 小缩略图（代码注释提到一个 150 MP 文件只显示成 296×220） | 需要外部转换，或者等上游写解码器 |
| **适马 DP2 Quattro（X3F）** | ❌ **只能显示预览**。编辑的是内嵌的 8 位机内 JPEG（DP2Q 样张里是 5424×3616 全尺寸）。读不到相机型号、ISO、拍摄时间 | 需要外部转换（X3F → LinearRaw DNG），或者升级固件后在机内直出 DNG |
| **降噪** | 手动 Luminance / Color 降噪对**所有**图片都有效。AI Denoise 默认用内置 BM3D 算法，开箱即用，也可以装自己的 ONNX 模型，但**只支持 Bayer** | 理光、宾得、IIQ 转出的 DNG 能用 AI Denoise；Foveon 不能 |
| **RAW+JPEG 合并显示** | main 上**没有**，只有手动堆叠和按拍摄时间自动堆叠。**上游 PR [#4046](https://github.com/storytold/lightcraft/pull/4046) 正在实现**（未合入） | 等合入，或用外部脚本自动堆叠 |
| **插件 / 运行时模块** | **没有**。上游把它列为缺口 #19（`docs/gaps.md:36`，⬜，“40–80 h + owner decision”） | 只能走“外部进程编排”，或者 fork / 向上游提 PR |

一句话总结：**理光不需要任何扩展；IIQ 和 X3F 目前只是“能看”，不能做 raw 编辑；LightCraft 没有插件系统，所以“主程序照常更新、额外功能以模块载入”最现实的做法，是一个独立的外部助手程序：把 IIQ/X3F 转成 DNG，再通过 LightCraft 官方的控制通道或 MCP 导入、关联和堆叠。**

---

## 1. 三类相机格式的详细情况

### 1.1 理光 Ricoh

- **GR 系列一直输出 DNG**：GR Digital I–IV、GX100/GX200、GXR、GR、GR II、GR III、GR IIIx、HDF 版，以及 2025-08 发布的 GR IV 和 2026 年初的 GR IV Monochrome / GR IV HDF 都是。LightCraft 判断格式只看 DNG 版本标签，不写理光专用逻辑（`crates/raw/src/lib.rs:198-201`）。
- 验证状态见 `docs/raw/coverage.tsv:1081-1099` 和 `crates/raw/tests/it/canon_pentax_corpus.rs`。已验证：GR、GR II、GR IIIx（锁定传感器哈希，并与机内 JPEG 比对）、GX200。GR III 只有“能解码”的语料测试。GR IV 系列、HDF 系列、GR Digital 系列标为 unverified，原因是缺少 CC0 样张，格式上走的是同一条标准 DNG 路径。
- **GR 的 DNG 自带色彩矩阵**，所以白平衡用开尔文刻度。如果 DNG 里没有色调曲线，LightCraft 会拿内嵌 JPEG 拟合色调（`crates/engine/src/camera_preview/colour.rs:88-91`）。
- GR III/IV 的 35mm/50mm 裁切模式写在 DNG 的 `DefaultCrop` 里，LightCraft 会读取（`crates/raw/src/dng.rs:340-358`）。真机样张还没有核对。
- **GR IV Monochrome 是单色 DNG，不是 Bayer**：AI Denoise 和“去除热像素”都不能用，手动降噪可以用。

### 1.2 理光时代的宾得 Pentax（PEF / DNG）

- `Make` 以 `PENTAX` 或 `RICOH` 开头、并带 CFA 的 TIFF 会被识别为 PEF（`crates/raw/src/lib.rs:203-227`）。PEF 支持未压缩、Huffman 和 packed 12-bit 三种编码。
- **PEF 文件里没有色彩矩阵**，内置矩阵表里也没有宾得或理光的条目。所以 PEF 的颜色靠逐张拟合机内 JPEG，白平衡用相对刻度。同一台机身拍 DNG 时会用文件自带的矩阵，白平衡按开尔文（`crates/catalog/src/model.rs:349-364`）。**建议在机身菜单里把 RAW 格式改成 DNG。**
- 如果想继续拍 PEF，可以用 `lightcraft-cli calibrate` 拟合一份机型的 JSON 配色档案，放进 `LIGHTCRAFT_CAMERA_PROFILES`，或者导入 `.dcp` 文件（`crates/engine/src/camera_profiles.rs:1-12`）。这两种方式都不用改代码。
- 已知限制：缺少 area 标签的 PEF 会裁掉边缘的行列（#1271）；**Pixel Shift 的四帧不会合成**（`docs/raw-parity.md:164`）。

### 1.3 飞思 Phase One IIQ

**代码现状**

- 导入扩展名列表里有 `iiq`（`crates/engine/src/import/files.rs:20`），所以文件**能被导入**。
- IIQ 没有专门的格式变体，只能靠通用的 TIFF 结构规则落进 `RawFormat::OtherTiff`（`crates/raw/src/lib.rs:244-249`，规则包括 `has_cfa`、`thumbnail_shell`、`is_preview_container`、`is_leaf_mosaic` 四种之一），然后 `decode_with` 返回 `Unsupported`（`crates/raw/src/lib.rs:435`）。`crates/raw/src/vendor/` 下没有 IIQ 或 Phase One 模块。
- 预览的取法：先在 TIFF 的 IFD 和 maker note 里找 JPEG；找不到就扫描全文件；还是找不到，就直接把 IFD0 的小 RGB 缩略图当图像用（`crates/raw/src/preview.rs:293-324`，`crates/engine/src/files/preview.rs:16-27`）。测试注释里提到“a 150 MP file renders 296x220”（`crates/engine/src/files/tests.rs:1553-1564`）。
- 覆盖表 `docs/raw/coverage.tsv:1053-1080` 的状态：IQ1/IQ2/IQ3/IQ4、P40+、P65+ 标为 preview；P20–P45+ 的 `.TIF` raw 标为 unsupported。**这个 preview 只是 `coverage.py` 按扩展名套规则得出的，仓库语料里没有任何真实 IIQ。** 如果真实 IIQ 一条结构规则都没命中，它会被当成一张小尺寸的普通 TIFF 导入。

**外部情况**

- IIQ 的变体由私有标签 `RawFormat(0x010e)` 区分：IIQ L（L14）、IIQ S、IIQ Sv2（即 S14，包括 “IIQ 14 Smart” 和 Sensor+）、IIQ L16（16 Large / 16 Extended）。L 系列无损，S 系列有损或近无损。
- IIQ 里内嵌了逐机的传感器标定数据：坏点表、多组平场、线性化系数、黑电平数据。这些数据直接影响画质，非原厂解码器如果不用它们，可能出现 CCD 多放大器分块等问题。镜头偏色校正 LCC 不在 IIQ 里，是 Capture One 另外生成的文件。
- **没有公开规范**，也**没有任何 MIT/Apache/BSD/CC0 许可的 IIQ 解码器**。LibRaw 是 LGPL-2.1/CDDL，rawspeed、dnglab/rawler、rawloader 是 LGPL-2.1，RawTherapee 是 GPL-3。这些都不在 LightCraft 的许可白名单里，而且上游的 clean-room 规则明确禁止参考它们的代码（AGENTS.md 中的 Clean room 一节）。
- **Adobe DNG Converter**（免费但专有，有 Windows/macOS 版和命令行模式）支持 P40+ 到 IQ4 150MP / Achromatic，**但不支持 S14 / S14+（即 IIQ 14 Smart 和 Sensor+）**。据 Capture Integration 的资料，S14 是 IQ4 的出厂默认档。
- dnglab（LGPL，Rust 命令行工具，原生支持 Linux）的支持列表包括 IQ4 150MP 和 IQ3 100MP，可以作为用户自己运行的外部工具。

### 1.4 适马 Sigma DP2 Quattro（X3F）

**代码现状**

- 靠 `FOVb` 魔数识别为 `RawFormat::X3f`（`crates/raw/src/lib.rs:124-125`），但它不在 `is_supported` 里，解码返回 “X3f files are not decoded yet”（`crates/raw/src/lib.rs:436`）。
- 预览不是通过解析 X3F 目录取得的，而是扫描整个文件，取其中最大的完整三通道 JPEG（`crates/raw/src/preview.rs:289-291, 452-516`）。用 Kalpanika 测试样张（DP2 Quattro，X3F 4.1）静态分析，文件里有一张 **5424×3616 的全尺寸机内 JPEG**，所以导入后很可能显示和编辑的就是这张 JPEG。LightCraft 本身没有实际跑过。
- **读不到元数据**：元数据容器嗅探里没有 X3F 分支（`crates/meta/src/container.rs:33-81`），所以相机型号、ISO、拍摄时间都为空，拍摄时间退回到文件修改时间。
- 覆盖表里**根本没有 DP2 Quattro 这一行**（Adobe 的官方支持列表里本来就没有任何 Merrill 或 Quattro 机型）。

**外部情况**

- DP2 Quattro 的传感器是 1:1:4 结构：顶层 5424×3616，中层和底层各约 2712×1808。raw 采用 TRUE III 预测加 Huffman 编码，有 14-bit 无损压缩。CAMF 段里存放黑电平、白平衡、色彩矩阵和空间增益等数据。**唯一公开的规范是 2004 年 Foveon 的 FOVb v1.2**，其中明确删掉了 raw 编码部分。TRUE、CAMF 和 Quattro 编码都没有公开规范。
- 主流软件的支持情况：Adobe（ACR、Lightroom、DNG Converter）**从未支持** Merrill 和 Quattro；darktable 明确不解码 Foveon；RawTherapee 的 camconst 里没有 dp Quattro；LibRaw 从 0.20 起把 X3F 改成默认不编译（`USE_X3FTOOLS`），原因是安全策略；Sigma Photo Pro 6.9.0 只能导出 JPEG 或 TIFF，**不能导出 DNG**；SILKYPIX Pro8 支持 dp Quattro，但有功能限制，后续版本是否仍支持没有核实。
- **可用的开源转换器**
  - [Kalpanika/x3f](https://github.com/Kalpanika/x3f)：BSD-3 风格许可，最后一次提交在 2017-06。支持 Quattro raw 类型 `0x00010023`，默认输出“已降噪、未做色彩转换”的 LinearRaw DNG。0.54 版的说明里写着 Quattro 支持仍不完整，并关闭了 Quattro 的空间增益补偿。
  - [sagwaco/x3fuse-core](https://github.com/sagwaco/x3fuse-core)：**还在活跃维护的 Rust 移植**，Apache-2.0，v0.4.1 发布于 2026-10。`x3f_extract` 输出 LinearRaw DNG，内置 NLM/BM3D 降噪（`-denoise 0-10`，默认 10），可以用 GPU，支持 Quattro 和 X3I。2026-06 已经去掉 OpenCV 依赖。它的 `x3f-sys` 里有 C shim 和大量 `unsafe`，部分处理阶段来自对 SPP 的反编译记录，所以**只能作为外部进程使用，不能并入 LightCraft**。macOS 有基于它的 GPL-3 图形界面 X3Fuse。
  - 画质上的注意点：中层和底层半分辨率平面要上采样；Quattro 的空间增益表没有完整实现；高光可能偏黄绿；转换不可逆，应保留 X3F 原片。
- **机内直出 DNG**：dp Quattro 固件 2.00 以上可以在机内记录 12-bit 未压缩 DNG（DP2Q 为 5424×3616 和 2704×1808 两档），**但 DNG 不能和 JPEG 同时记录**。这类 DNG 普遍被认为是三通道 LinearRaw；LightCraft 的 DNG 解码器接受 LinearRaw（`crates/raw/src/dng.rs:13-18, 264-269`），理论上可以原生编辑，**但没有用样张验证过**。

### 1.5 “仅预览（preview_only）”到底能做什么

- 照片入库时带 `preview_only` 标记，`develops_raw()` 为假（`crates/catalog/src/model.rs:313-318, 447-449`），按已渲染的 JPEG 处理。
- **可以用**：编辑面板的全部滑块（白平衡是相对刻度）、6 个手动降噪滑块、导出。导出分辨率不会超过内嵌预览的尺寸。
- **不能用**：AI Denoise（显示 NotApplicable）、去除热像素（隐藏）、Convert to DNG（报错）。
- 网格缩略图、放大视图、信息面板上都有 “Preview only” 提示。上游以后支持某个格式时，`library.recheckPreviewOnly` 会自动把这类照片升级成 raw 编辑。

---

## 2. 降噪

| 能力 | 适用的数据 | 说明 |
|---|---|---|
| **AI Denoise，内置 `builtin`** | 只支持 Bayer CFA | BM3D/CBM3D（NLM 作后备），从照片自身估计噪声，不需要下载模型，开箱即用，滤波这一步可以用 GPU（`crates/denoise-core/src/builtin.rs`）。中文 README 里标的 ⬜ 已过时，以代码为准 |
| **AI Denoise，用户自装 ONNX** | 只支持 Bayer CFA | 入口是 Settings ▸ AI Denoise ▸ *Install from file…*，需要 `.onnx` 加 `denoise-model.json`。约束：float32；算子只有 Conv、ConvTranspose、MaxPool、Concat、DepthToSpace 和可融合的 LeakyRelu；输入 4 通道 RGGB，输出 3 通道、分辨率翻倍。**这是 LightCraft 现在唯一真正能在运行时装入的“模块”** |
| **手动 Luminance / Color NR** | 所有图片 | 作用在线性 Rec.2020 RGB 上，raw、LinearRaw DNG、JPEG/TIFF、preview-only 的内嵌 JPEG 都有效 |
| 去除热像素 | 单平面 CFA（Bayer 或 X-Trans） | LinearRaw 和 preview-only 不可用 |
| 局部蒙版的 Noise 滑块 | 所有图片 | |

- **只支持 Bayer 的硬性检查**在 `crates/engine/src/denoise/products.rs:181-184`：`cpp != 1` 或非 Bayer 时报 “only Bayer raw files can be denoised”。`docs/denoise.md:299-300` 也写明 X-Trans、Foveon、已去马赛克的 DNG 和非 raw 图像都不支持。
- **单张图像上限 110 MP**（`crates/denoise-core/src/run.rs:17` 的 `MAX_PIXELS`）。即使 **IQ4 150MP** 转成了 DNG，AI Denoise 也会失败，只能用手动降噪。IQ3 100MP 和 IQ1/IQ2 不受这个限制。
- AI Denoise 的结果不会写出新的 DNG，而是存成缓存文件 `<library>/denoise/<key>.lcdn`，在调色前按 Amount 混合，属于实时、非破坏的步骤。
- 按你的器材归纳：

| 来源 | AI Denoise | 手动降噪 |
|---|---|---|
| GR 彩色 DNG、宾得 PEF/DNG | ✅ | ✅ |
| GR IV Monochrome、K-3 III Monochrome、IQ4 Achromatic | ❌（不是 Bayer） | ✅ |
| IIQ → Adobe DNG Converter 或 dnglab 转出的 CFA DNG（≤110 MP） | ✅ | ✅ |
| IQ4 150MP 转出的 DNG | ❌（超出 110 MP） | ✅ |
| X3F → LinearRaw DNG（x3fuse 或 Kalpanika 转换） | ❌（3 通道） | ✅；也可以在转换时用 x3fuse 的 `-denoiser bm3d` 先降噪 |
| X3F / IIQ 直接导入（preview_only） | ❌ | ✅（作用在 8 位内嵌 JPEG 上） |

---

## 3. RAW+JPEG 合并显示

**main（c2e9c45）现状**

- **没有** Lightroom 那种“把 RAW 旁边的 JPEG 当作附属文件”的导入选项。同名的 RAW 和 JPEG 导入后是两张独立的照片（`crates/engine/src/import/commit.rs:257-313`）。
- 已有的相关能力：
  - 导入对话框可以按文件类型整体取消勾选 JPEG（#344）。
  - XMP sidecar：RAW 占用 `IMG_0001.xmp`，JPEG 用 `IMG_0001.JPG.xmp`（#1905，`crates/engine/src/sidecar.rs:44-52, 931-1068`）。两者元数据各自独立，不会合并。
  - **堆叠（Stack）**：可撤销、写入日志；折叠后网格只显示顶部一张，带数量徽章（`crates/catalog/src/stacks.rs`）。
  - **按拍摄时间自动堆叠**（`stack.auto`，gap 可以设为 0）：会把同一秒内的连拍也并进来；X3F 没有 EXIF 拍摄时间，这个办法对它不可靠。

**上游正在进行的工作**

- Issue [#3439](https://github.com/storytold/lightcraft/issues/3439)（标记为 in progress）就是这个需求。
- **PR [#4046](https://github.com/storytold/lightcraft/pull/4046)（open，head `90cf6d0a`，2026-11-10）** 的内容：
  - 新增 `crates/catalog/src/raw_jpeg.rs`；
  - 导入选项 `pairRawJpeg` 和库偏好 `import.pairRawJpeg`（默认关闭）；
  - 命令 `stack.rawJpegPairs`，可以给已有的库补配；
  - 配对规则：同一文件夹、去掉扩展名后的文件名相同（忽略大小写）、恰好 1 个 RAW 加 1 个 JPEG/HEIF；
  - 用**折叠堆叠**实现，**不改目录格式**；
  - **RAW 只能预览时（X3F/IIQ），把相机 JPEG 放在堆叠顶部**，正好适合你的用法。
- 局限：堆叠里仍然是两张照片，评分、旗标、删除互不联动（那是 PR #1231 的范围）；界面字符串目前没有简体中文翻译。

**合并显示的几条路线**

1. **等待 #4046 合入**：零成本，推荐。可以在 PR 下提供 GR、X3F、IIQ 的测试反馈，推动合入。
2. **零代码近似**：`stack.auto {gap: 0}`。适合 GR/IIQ，不适合 X3F。
3. **外部脚本**：通过控制通道调用 `catalog.query`、`photo.inspect`、`library.select`、`stack.group`，按“同目录同名”自动堆叠。注意 `stack.group` 必须先有选中照片才可用，执行后会改变当前选择（`crates/engine/src/cmd/organize.rs:168-192`）。
4. 更进一步，“preview-only 的 RAW 直接用同目录的全尺寸相机 JPEG 显示”需要改上游的媒体缓存和快速预览路径，外部扩展做不到。

> ⚠️ 不要在 fork 里给 `Photo` 加 companion 字段：那样必须提升目录 `VERSION`（当前为 12，`crates/catalog/src/journal.rs:89-91`），会和上游版本号冲突，库也会被旧版拒绝打开。

---

## 4. LightCraft 能否“主程序照常更新、额外功能按模块载入”？

### 4.1 结论：**没有运行时插件机制**

- 依赖里没有 `libloading`、`dlopen`、WASM 宿主或脚本引擎（`Cargo.lock` 里的 `libloading` 只是图形库间接带进来的）。工作区设置了 `unsafe_code = "deny"`。命令注册表在编译期固定（`crates/engine/src/cmd.rs:133-175`）。
- 解码器分派是写死的 `match`（`crates/raw/src/lib.rs:417-437`），没有注册接口。
- 上游自己把插件生态列为缺口 #19，状态 ⬜，**需要维护者决定**（`docs/gaps.md:36`）。

### 4.2 现有可以利用的“外部扩展面”（都是官方功能，不改主程序）

| 扩展面 | 能做什么 | 不能做什么 |
|---|---|---|
| **控制通道** `lightcraft --control 7980`（loopback JSON-lines，无认证）、**MCP** `lightcraft-cli mcp [--connect]`、**CLI** `lightcraft-cli run` | 调用几乎所有引擎命令：导入、查询、`photo.relink`、`photo.reload`、`stack.*`、调色、导出、`denoise.*`、`library.recheckPreviewOnly` 等 | 不能增加新的解码格式或新命令 |
| **监视文件夹自动导入** `library.autoImport`（约每 3 秒扫描一次） | 外部转换器把 DNG 写进监视文件夹，LightCraft 会自动导入 | |
| **AI 降噪模型安装**（ONNX + 清单） | 运行时装入新的降噪模型 | 只支持 Bayer，算子集合很窄 |
| **数据扩展**：`.dcp` 相机配置文件、`.cube` LUT、相机配色档案 JSON、lensfun 数据库、预设导入 | 补充颜色和镜头数据 | 不能增加解码器 |
| **Edit In / Open Original in Other Editor** | 把渲染后的 TIFF/PSD 交给外部编辑器并自动回载；或把原始文件交给其他软件（例如 SPP、Capture One） | Edit In 交出去的是渲染副本，不是 X3F/IIQ 原片；Open Original 的结果不会自动回到图库 |

### 4.3 编译期钩子（需要改 app 入口，相当于 fork）

- `MediaCache` 上有 `file_loader`、`reduced_loader`、`file_probe`、`preview_loader`、`file_bytes`，都是 `pub Arc<dyn Fn>`，由 `Session::with_fs` 装入（`crates/engine/src/media.rs:69-75`，`crates/engine/src/files/fs.rs:128-144`，`apps/lightcraft/src/session.rs:259, 282, 284`）。
- 可以把 `.x3f`/`.iiq` 拦截下来，转换成 DNG 字节后再交给原实现。但 **AI Denoise、Convert to DNG、DNG 导出、HDR/全景合并、相机配置文件校准、sidecar 方向重读**这些路径会直接调用 `lightcraft_raw`，绕过钩子（`crates/engine/src/denoise/products.rs:166-177`，`crates/engine/src/export/prepare.rs:267-270`，`crates/engine/src/merge.rs:116` 等）。

### 4.4 fork 的现实成本

- **应用内更新只从 `storytold/lightcraft` 下载**（`crates/ui-egui/src/lib.rs:9-16` 中的 `UPDATE_APP`，来自 craft-update 的 `suite::LIGHTCRAFT`）。fork 构建如果不改这里，用户点了更新就会被换回官方版本。更新是可以点 Later 的提示，不是静默替换。
- 上游变化极快：30 天约 3,172 个提交，v0.13 到 v0.18 平均每 2–3 天发一版，`crates/raw/src/lib.rs` 30 天改了 49 次。长期维护补丁集的 rebase 成本很高。
- 上游的 `release.yml` 拒绝 `storytold` 组织以外的 git 依赖和 `.cargo/config` 里的 patch/replace。fork 自建发布需要改写流水线，并自行签名（否则会触发 macOS Gatekeeper 和 Windows SmartScreen 警告）。

---

## 5. 方案对比

评分：“照常更新”指 LightCraft 主程序能否继续直接使用官方版本和应用内更新。

| 方案 | 做法 | 照常更新 | 工作量（估计） | 质量 | 备注 |
|---|---|---|---|---|---|
| **A. 外部转换助手（推荐）** | 独立程序：X3F 用 x3fuse-core 转成 LinearRaw DNG；IIQ 用 Adobe DNG Converter 或 dnglab 转成 CFA DNG。再通过控制通道或 MCP 导入，用 `photo.relink` 指向 DNG 或与原片堆叠，同时做 RAW+JPEG 配对 | ★★★★★ | 约 40–80 h（调用现成转换器；含文件监视、配对规则和测试） | 取决于转换器：IIQ 接近原生；Quattro 的颜色与 SPP 不同 | GPL/LGPL 工具只作为外部进程运行，不污染上游；方向与上游 `photo.convertToDng`（在原文件旁写 DNG 并 relink）的语义一致 |
| A'. 零代码手工流程 | 同 A，但手工转换后导入，或放进监视文件夹 | ★★★★★ | ≈0 | 同 A | 可以马上开始 |
| B. Fork / 补丁集 | 把解码器编进 LightCraft（仿照 craft-crw 的外部 crate 加约 10 行接线），或者包装 `with_fs` 钩子 | ★–★★ | 高：解码器本身加长期 rebase、签名和发布 | 最高（导入即可编辑） | 违背“照常更新”的初衷 |
| C. 向上游贡献 clean-room 解码器 | 按 CRW/ARW6 先例：只用公开规范和黑盒观察，把 LibRaw、dnglab、x3fuse 当 oracle 运行对比，**不读它们的源码**；样张必须是 CC0 | ★★★★★（合入后） | 每种格式约 25–60 h 以上；X3F Quattro 可能远超上游对长尾格式合计 45–85 h 的估计 | 高 | 来源（provenance）门槛高：压缩 ORF 解码器就因来源问题被撤回；上游把这些格式列为最低优先级 |
| C2. 向上游提议通用“外部解码器钩子” | 在设置里给扩展名配置外部转换命令，引擎透明地使用缓存的 DNG | ★★★★★（合入后） | 约 20–40 h，另加讨论时间 | 取决于外部工具 | 触及缺口 #19，需要维护者决定；执行外部程序有安全顾虑 |

---

## 6. 推荐路线

### 第 0 步：马上可以做（零代码）

1. **理光 GR**：直接导入 DNG 即可完整编辑，降噪用 AI Denoise（内置 BM3D）加手动降噪。
2. **理光时代的宾得**：机身 RAW 格式改成 **DNG**，以获得文件自带矩阵和开尔文白平衡。
3. **飞思 IIQ**：
   - 用 Adobe DNG Converter 批量转成 DNG 后导入（**注意它不支持 IIQ 14 Smart / Sensor+，即 S14**；如果是 IQ4，拍摄时尽量用 IIQ L / L16）；
   - 或者用 dnglab（Linux 原生）；
   - 或者在 Capture One 里显影，再把 16-bit TIFF 交给 LightCraft 管理。
4. **DP2 Quattro**：
   - 已有的 X3F：用 x3fuse-core 的 `x3f_extract` 转成 LinearRaw DNG，或者在 SPP 里导出 16-bit TIFF。降噪可以在转换时用中等强度的 `-denoiser bm3d`（因为 LightCraft 的 AI Denoise 对 LinearRaw 不可用），之后在 LightCraft 里用手动降噪微调。
   - 新拍摄的照片：可以考虑把固件升到 2.0x，在机内直出 DNG（代价是没有 RAW+JPEG）。需要先用一张样张确认 LightCraft 能正确显影。
5. **RAW+JPEG**：关注并测试 PR #4046；在它合入之前，可以先用“按拍摄时间自动堆叠，gap = 0”做近似（X3F 不适用）。

### 第 1 步：本仓库要做的事（方案 A，外部助手）

建议在本仓库实现一个独立的命令行或守护进程工具（暂名 `lcx`），只依赖 LightCraft **官方公开的接口**：

```
相机卡 / 文件夹 ──► lcx 扫描
                      ├─ *.X3F ──► x3f_extract（外部进程）──► 原文件旁写 *.dng
                      ├─ *.IIQ ──► Adobe DNG Converter / dnglab（外部进程）──► *.dng
                      └─ 其他 RAW / JPEG：不处理
                 ──► 连接 LightCraft 控制通道（lightcraft --control 7980）
                      ├─ library.import 或 photo.relink（把 preview_only 记录指向 DNG）
                      ├─ RAW(DNG)+JPEG 同目录同名 → library.select + stack.group（RAW 置顶，折叠）
                      └─ （可选）对 Bayer DNG 预先触发 denoise.*
```

- 本仓库自身使用 MIT 或 Apache-2.0 许可；外部转换器由用户自行安装，作为独立进程调用。
- LightCraft 关闭时用 `lightcraft-cli run --library <路径>`；运行时用控制通道或 `lightcraft-cli mcp --connect`。库文件有 `catalog.lock`，同一时间只能被一个进程打开。
- 等 #4046 合入后，配对改为直接调用上游的 `stack.rawJpegPairs`，删掉自己的配对逻辑。
- 将来上游原生支持 IIQ/X3F 时，用 `library.recheckPreviewOnly` 平滑迁移。

### 第 2 步：中长期向上游贡献（可选）

- 在 #4046 下提供 GR、X3F、IIQ 样张的测试反馈。
- 开 issue 提议“通用外部解码器钩子”（C2），或“线性 RGB 降噪契约”（让 LinearRaw 和 Foveon 也能用 AI Denoise，`docs/denoise.md:299-302` 已经列为未来工作）。
- 如果有能力并愿意捐赠 CC0 样张，可以按 clean-room 流程认领缺口 #20 中的 IIQ 或 X3F（先在 issue 里评论认领）。

---

## 7. 尚待实测确认的问题

1. 真实的 DP2 Quattro X3F 导入 LightCraft 后，能否扫到 5424×3616 的内嵌 JPEG？拍摄时间是否退回到文件修改时间？
2. 你的 IIQ 文件（哪款后背？L、L16 还是 S14？）导入后是被识别为 preview_only，还是被当成小尺寸 TIFF？预览分辨率多大？
3. x3fuse-core 转出的 Quattro LinearRaw DNG 在 LightCraft 中的颜色和高光表现如何？和 SPP 的差距多大？
4. dp Quattro 固件 2.0x 机内直出的 DNG 在 LightCraft 中能否正确显影（PhotometricInterpretation 是否为 LinearRaw）？
5. Adobe DNG Converter 或 dnglab 转出的 IIQ DNG 是否用上了 Phase One 的传感器标定数据（坏点、平场）？和 Capture One 对比画质如何？
6. GR IV、GR IV Monochrome、HDF 机型，以及 GR III/IV 裁切模式的真机样张验证。
7. `photo.relink` 把 X3F 记录指向 DNG 时，评分、关键词和 preview_only 状态的迁移行为，需要实测。
8. PR #4046 什么时候合入、以什么形式合入。

---

## 8. 关键代码位置索引（上游 c2e9c45）

| 主题 | 位置 |
|---|---|
| 导入扩展名列表（含 iiq/x3f） | `crates/engine/src/import/files.rs:12-21` |
| 格式枚举 / 是否支持 / 探测 / 解码分派 | `crates/raw/src/lib.rs:108-138`、`142-163`、`166-251`、`417-437` |
| X3F、IIQ 预览提取 | `crates/raw/src/preview.rs:289-324, 452-516` |
| preview_only 回退 | `crates/engine/src/files/probe.rs:130-157`、`crates/engine/src/files/load.rs:95-103` |
| LinearRaw DNG 读取 | `crates/raw/src/dng.rs:13-18, 264-269`、`crates/raw/src/demosaic.rs:74-90` |
| DNG 写出（CFA 与 LinearRaw） | `crates/raw/src/dngwrite.rs:179-196` |
| AI 降噪只支持 Bayer / 110 MP 上限 | `crates/engine/src/denoise/products.rs:181-184`、`crates/denoise-core/src/run.rs:17` |
| 降噪模型清单与 ONNX 算子集 | `crates/denoise-core/src/manifest.rs`、`crates/denoise/src/onnx.rs` |
| 堆叠 / 自动堆叠 | `crates/catalog/src/stacks.rs`、`crates/engine/src/cmd/organize.rs:168-192, 259-283` |
| 引擎可替换钩子 | `crates/engine/src/media.rs:69-75`、`crates/engine/src/files/fs.rs:128-144` |
| 应用内更新源 | `crates/ui-egui/src/lib.rs:9-16` |
| 插件生态缺口 / 长尾格式缺口 | `docs/gaps.md:36`、`docs/gaps.md:37`、`docs/raw-parity.md:282` |
| 控制通道 / MCP 文档 | `docs/control-protocol.md`、`docs/mcp.md` |
| RAW+JPEG 配对（PR #4046） | `crates/catalog/src/raw_jpeg.rs`（PR 分支） |
