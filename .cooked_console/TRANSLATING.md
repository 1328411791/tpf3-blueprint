# 翻译指南

模组界面、工具说明、保存反馈及错误提示集中在根目录的 `strings.json`，使用游戏原生的多语言加载机制。已提供 `en`（英文）和 `zh_CN`（简体中文），共 100 个文本键。文件为 UTF-8 JSON，不需要编译。

## 添加语言

复制 `en` 对象，改为目标语言代码，然后翻译每个键右边的文本。键名 `BLUEPRINT_...` 不要修改。常见代码：`zh_TW`（繁体中文）、`de`、`fr`、`ja`、`ko`。游戏按自身语言设置选择翻译；未翻译的键回退到英文，再缺失时显示键名。

例如：

```json
"fr": {
  "BLUEPRINT_MANAGER": "Gestion des modèles",
  "BLUEPRINT_COUNT": "{count} modèles"
}
```

此示例仅说明添加语言的格式；对象之间需要逗号，JSON 不允许注释或尾随逗号。可以先添加少量条目，其余内容会显示英文。

## 占位符

`{name}`、`{id}`、`{count}`、`{error}` 等是运行时插入的数据。保留原文中的所有占位符及拼写，可以调整它们的顺序；不要翻译花括号里的名称。

`BLUEPRINT_DEFAULT_NAME` 控制新增模板的默认名称，`BLUEPRINT_COPY_NAME` 控制复制时的名称。已有模板和玩家自己输入的名称不会因切换语言而改写。建筑原本的名称、第三方模组资源名和游戏产生的错误内容由其来源决定语言。

## Mod Hub 文案

游戏规定 Mod Hub 的名称、摘要、描述使用 `_metadata/modinfo.json` 的 `localization` 字段，单独在该字段添加目标语言的 `name`、`summary`、`description`。其默认文案用于未提供翻译的语言。

## 验证

运行 `python tests/run_tests.py`（需要开发依赖 `lupa`）。测试检查 JSON、文本键、占位符、中英文界面调用点、英文回退以及模板操作。已有语言可只保留部分条目；新增键应始终先补齐英文。

保存翻译后，选择对应游戏语言并重新载入地图，检查按钮长度、工具提示、模板列表与保存失败提示。切换语言后的实际加载和排版仍需在游戏中验证。

原生格式参考：[Transport Fever 3 官方 Wiki：Mod Definition / strings.json](https://wiki.transportfever3.com/doku.php?id=modding%3Ageneral%3Amoddefinition)。
