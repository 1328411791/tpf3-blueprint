# 原生建造菜单模板研究示例

这个示例展示“添加菜单卡片 → 点击卡片 → 用原版建筑放置固定布局”的文件结构。
它会在铁路建筑菜单（截图所在类别）和仓库菜单注册同一张卡片，尝试同时放置两座普通货物仓库。
铁路分类仅用来验证截图位置的接入方式；正式仓库模板通常只保留 `warehouses`。

状态：JSON 与引用路径经过静态核对；尚未在游戏中加载、放置、保存或删除验证。
这是开发原型，不是已验证的完整蓝图库。没有自动保存现有建筑、区域框选或周边道路功能。

## 文件用途

- `mod.json`：技术标识。
- `_metadata/modinfo.json`：Mod Hub 中的名称、描述。
- `content/templates/warehouse_pair.metacon.tl`：原生菜单卡片与建造脚本引用。
- `content/templates/warehouse_pair.script.lua`：返回两座仓库及各自的相对位置和模块。

图标引用原版资源，游戏原版也使用不带 `@2x` 的逻辑名称，实际文件为 `@2x.tga`。
本例未重新分发原版模型、贴图或建筑脚本。

## VS Code 开发配置

已按游戏安装目录中的 `vscode-template` 补齐开发配置：

- `.vscode/extensions.json`：推荐安装官方模板指定的 `pdesaulniers.vscode-teal` 扩展。
- `tlconfig.lua`：引用本机游戏的 `api/tealdef` 和 `base/tealdef` 类型定义。
- `all_def.tl`：引入 `api_def` 与 `content_def`，不包含模板中的示例 Mod 引用。

在 VS Code 中打开本项目根目录（包含 `mod.json` 和 `tlconfig.lua` 的目录），安装推荐扩展。
当前游戏路径为 `D:/SteamLibrary/steamapps/common/Transport Fever 3`；迁移到其他电脑或更换安装目录时，修改 `tlconfig.lua` 中的两个路径。
这些文件用于编辑器开发支持；游戏内加载与放置仍需按下面的步骤验证。

## 手动试验步骤

1. 将整个 `liha_blueprint_demo` 文件夹复制到本机开发目录：
   `C:\Program Files (x86)\Steam\userdata\364060473\3493540\local\staging_area\`。
2. 在游戏 Mod Hub 里查找 `Blueprint Menu Demo`，在单独的试验地图启用。
3. 从 1900 年或以后开始，检查铁路建筑和仓库菜单是否出现 `Blueprint Demo: Warehouse Pair`。
4. 点击卡片：检查预览是否为两座仓库、旋转与高程是否正常、是否正常计费。
5. 放置后检查两座建筑的模块编辑、道路连接、存货功能；再保存并重新载入。

调研过程只生成了工作区里的这些文件，没有复制到游戏目录或更改现有存档。
正式开发时先替换固定仓库布局，再接入“读取现有建筑”的数据采集功能。

完整设计见上级目录 `blueprint-mod-research-2026-10-01.md`。
