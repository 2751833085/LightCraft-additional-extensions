# 续做说明（模块栏 + 打印模块，进行中）

本文件给下一次会话用：在新容器里也能从这里接着做。

## 目标（用户需求）

在 LightCraft 顶栏右上角加四个模块按钮：**图库｜修改照片｜打印｜导出**，操作逻辑沿用 Lightroom。

- **图库**：网格视图 + 左侧面板。
- **修改照片**：详细视图 + Edit 面板。
- **打印**：整窗显示打印设置和页面预览。可以按长边设定照片打印尺寸（默认 10 英寸，用户习惯），不改变照片本身；可以选横向/纵向；有色彩管理。
- **导出**：打开导出对话框。

交付要求：一个可以实际使用的成品，包括补丁集和构建脚本。

## 基线

- 上游 `storytold/lightcraft`，固定在发布标签 **v0.20.0**（`192ff729`）。必须跟 release tag，不能跟 main：用 main 构建打开过的图库，官方发布版会拒绝打开。
- 本地工作副本：`/home/user/storytold/lightcraft`，分支 `lcx-modules`，从 v0.20.0 切出。
- 新容器里恢复：`GIT_LFS_SKIP_SMUDGE=1 git clone https://github.com/storytold/lightcraft`，`git checkout -b lcx-modules v0.20.0`，再 `git apply wip/lcx-modules-wip.patch`。
- 编译：`cargo test -p lightcraft-ui-egui --no-run` 在 v0.20.0 基线上已通过（4 核约 40 分钟，`target` 目录会长到数 GB）。

## 已完成（见 `lcx-modules-wip.patch`）

- `crates/ui-egui/src/panels/modules.rs`：
  - `Module` 枚举（Library/Develop/Print/Export）；
  - `current()`、`switch()`、`before_frame()`（打印模块中切换了视图或右侧面板就退出打印模块）；
  - `ModuleState` 结构体；
  - 顶栏分段按钮 `show(app, ui, right, cy) -> left`、`bar_width()`；
  - 控件 id 为 `button:module-<id>`，命令为 `module.<id>`；
  - 模块名通过 `i18n::tr_ctx("module", …)` 翻译。
- `crates/ui-egui/src/panels.rs`：注册 `pub mod modules; pub mod print_module;`（`print_module.rs` 尚未创建）。

## 剩余步骤

1. `state.rs`：`UiState` 加字段 `#[serde(skip)] pub modules: crate::panels::modules::ModuleState`，并在 `Default` 实现里加 `modules: Default::default(),`（约第 533 行，`print:` 之后）。
2. `state/settings.rs`：`AppSettings` 加 `pub print_by_long_edge: bool`（默认 true）和 `pub print_long_edge_in: f64`（默认 10.0），在 `Default` 实现的 `lens_database` 之后补上默认值。
3. `i18n.rs`：加 `pub fn tr_ctx(context: &str, source: &str) -> &str { tr_ctx_in(language(), context, source) }`。
4. `locales/zh-hans.json` 和 `zh-hant.json` 加以下条目：
   - `"module|Library": "图库"`、`"module|Develop": "修改照片"`、`"module|Print": "打印"`、`"module|Export": "导出"`（繁体：圖庫 / 修改相片 / 列印 / 轉存）；
   - `"print orientation|Portrait": "纵向"`（现有翻译把 Portrait 统一译成“人像”，打印方向因此显示错误）、`"print orientation|Landscape": "横向"`；
   - 新增的界面文字。
5. `menus/ui_commands.rs`：加 `("module.library","Library",Some("Cmd+Alt+1"),"Window")`、`("module.develop","Develop",Some("Cmd+Alt+2"),"Window")`、`("module.print","Print",Some("Cmd+Alt+6"),"Window")`、`("module.export","Export",None,"Window")`。快捷键对齐 LrC，已确认没有冲突，`shortcuts/tests.rs` 的 `no_conflicting_bindings` 会检查。
6. `menus/run.rs` 的 `run_ui_command` 开头加：`if let Some(m) = crate::panels::modules::Module::from_command(id) { return Some(crate::panels::modules::switch(app, m)); }`。
7. `panels/topbar.rs`：
   - `right_icons` 跳过 `share`（Export）图标，它和“导出”按钮重复；
   - 在 `appearance_button` 左边画模块栏（`modules::show(app, ui, x - 22.0, full.center().y)`）；
   - 计算搜索框宽度 `sw` 时，给模块栏预留 `modules::bar_width(ui) + 约 30` 的位置，再加回去掉 share 图标省下的 40。
8. `app/frame.rs` 的 `draw_window`：
   - `topbar::show` 之前调用 `panels::modules::before_frame(self)`；
   - `if modules::print_active(self) { CentralPanel → panels::print_module::show(self, ui) } else { strip::show; CentralPanel → docking::show }`。
9. `dialogs/print_view.rs`：
   - `settings` 和 `preview` 改为 `pub(crate)`；
   - 把 “Page Setup”（纸张、方向、边距）和 “Print Job”（分辨率加色彩）拆成 `pub(crate) fn page_setup_section` 和 `pub(crate) fn print_job_section`；
   - 方向标签改用 `tr_ctx("print orientation", …)`。
10. 新建 `panels/print_module.rs`：
    - 右侧设置列（`egui::Panel::right`，宽约 320），依次为：
      - “照片尺寸”：勾选“按长边设定尺寸”，长边输入框（默认 10 in），显示结果尺寸 W×H；放不下时提示已缩小；
      - 长边模式下只显示页面设置和打印作业，关闭长边模式则显示完整的 `print_view::settings`；
      - “打印到 PDF…”按钮，执行 `app.run("app.print")`；
    - 中央区域：`print_view::preview`；
    - 长边排版逻辑 `sync_long_edge`：
      - 签名包含选中照片 id、裁剪后尺寸（`lightcraft_pipeline::native_output_size(p.width, p.height, &p.develop)`）、长边、可打印区域和样式；签名变化才重建；
      - 重建步骤：`print.set {layout:{style:"customPackage"}, image:{zoomToFill:false, rotateToFit:false}}` → `print.layout.clear` → 对每张照片 i（最多 50 张，`MAX_PAGES`）：i>0 时先 `print.layout.newPage`，然后 `print.cell.add {width,height}`、`print.cell.page {id, page:i}`，用 `print.cell.move` 居中，再 `print.cell.photo {id, photo}`；
      - 尺寸计算写成纯函数 `cell_size(pw, ph, long, area_w, area_h) -> (w, h, scaled)`，便于单元测试。
11. 测试，用 headless（`crate::headless::Headless`，`h.request("ui.clickWidget", {"id": "button:module-print"})`）：
    - 模块切换；
    - 打印模块能渲染（`print:page` 控件存在）；
    - 长边排版（10 in 长边、3:2 照片 → 10×6.667；纵向 Letter 放不下时缩小）；
    - 按 G 键退出打印模块；
    - 跑相关测试：`cargo test -p lightcraft-ui-egui modules print shortcuts::tests i18n`。
12. 打包到本仓库：
    - `patches/*.patch`（`git format-patch v0.20.0..lcx-modules`）；
    - `scripts/build.sh`：克隆固定 tag，`git am`，拉取 craft-fonts 并设置 `CRAFT_FONTS_DIR` 以打包中文字体，然后 `cargo build --release -p lightcraft`；
    - `README.zh-CN.md`：使用说明。注意应用内更新会提示升级到官方版，升级后补丁就没了，要说明清楚；
    - 删除 `wip/`。

## 已知限制（要告诉用户）

- LightCraft 的打印只能输出 PDF（16 位、嵌入 ICC），不能直接送打印机。出 PDF 后要用系统的 PDF 阅读器打印，或在 PhotoCraft 里打印（PhotoCraft 支持 CUPS/IPP/系统打印对话框）。

## 后台调研（可能已丢失，需要时重跑）

- Lightroom Classic 体验调研：修改前/修改后、导出后用 PS 打开、快捷键、全流程、PhotoCraft。
- 修图工具调研：减淡/加深/海绵、快速选择/对象选择、仿制图章/蒙版。
- UI 重排调研的结果已保存在 `docs/research-data/ui-relayout.json`。
