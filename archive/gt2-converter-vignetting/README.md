# 已封存：GR IIIx + GT-2 附加镜暗角校正

这个功能已经做完并测试过，但目前用不到，所以**封存在这里，不参与构建**：`scripts/build.sh` 和 `scripts/build.ps1` 只打 `patches/` 里的补丁。

## 内容

| 文件 | 说明 |
|---|---|
| `0008-Converter-vignetting-*.patch` | 补丁本体：显影设置的两个字段、渲染管线（CPU 和 GPU）的增益、平场测量命令 `optics.fitConverterVignette`、镜头校正面板的“附加镜暗角”、配置管理对话框、测试 |
| `gt2-converter-vignetting.zh-CN.md` | 使用说明：为什么会有暗角、怎么拍平场照、生成和应用配置、导入时自动校正 |
| `08-converter-vignetting.png` | 镜头校正面板选上配置后的截图 |

## 功能概要

- 用一张自己拍的平场照测出增距镜的暗角，存成配置（例如“GR IIIx + GT-2 · f/2.8”），之后在“修改照片 ▸ 镜头校正 ▸ 附加镜暗角”里一键校正；
- 叠加在原有的镜头校正之上，带“数量”滑块，最多提亮 4 档；
- 可以同步、存进预设，或设成导入时自动应用。

## 封存时的验证结果

基于 v0.20.0 + 补丁 0001–0007，补丁 0008 排在最后：

- 测试：界面层完整套件 1978 + 32 + 1 个，引擎库内 1656 个，develop 53 个，pipeline 316 个，全部通过；clippy 无警告；
- 在软件 Vulkan（lavapipe）上实测 GPU 和 CPU 渲染一致，最大差 1 级（8 位）；
- 构建脚本端到端编译通过；
- **没有**用真实的 GR IIIx + GT-2 平场照验证过。

## 怎么恢复

1. 把补丁拷回 `patches/`，编号排在现有补丁之后，例如现有补丁到 0009，就改名为 `0010-Converter-vignetting-….patch`。
2. 运行 `scripts/build.sh`。
   - 如果 0008 之后又加过补丁，并且改到了同样的文件（常见的是 `crates/ui-egui/locales/*.json` 的结尾、`crates/ui-egui/src/tests.rs`），`git am` 可能失败；
   - 这时在 `build/lightcraft` 里先手动 `git am -3` 这个补丁，解决冲突，再用 `git format-patch -1` 重新生成；
   - 换了上游版本也一样处理。
3. 把说明文档放回 `docs/`，截图放回 `docs/screenshots/`，在 README 里加回功能介绍。
4. 恢复后跑一次完整测试：`cargo test -p lightcraft-ui-egui`、`-p lightcraft-engine`、`-p lightcraft-pipeline`、`-p lightcraft-develop`。

## 关于已经编辑过的照片

- 封存后，构建出来的程序不再认识这项设置，读到时会忽略：其他调整都正常，只是四角不再提亮。
- 再次保存这张照片时，这项设置会被丢掉。如果以后要恢复功能，最好在那之前先恢复，否则这些照片要重新选一次配置。
- 保存过的配置列表（ui.json 里的 `converterProfiles`）也会被忽略，下次保存界面设置时可能被丢掉。恢复功能后，用原来的平场照重新创建即可。
