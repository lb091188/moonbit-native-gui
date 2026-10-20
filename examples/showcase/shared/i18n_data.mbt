// 演示板英文目录（内嵌,零文件 IO）。键=中文原文,便于 `t_or(key, 中文)` 形态:
// 中文态不加载本目录即回落中文;切英文时 i18n_load 本串覆盖。
// 侧栏页名走 [nav] 段（key = "nav." + 中文页名）;组名走 nav.g.*。

pub const EN_CATALOG : String =
  "[meta]\nlocale = \"en\"\n" +
  "[nav]\n" +
  "\"基础组件\" = \"Basics\"\n\"表单组件\" = \"Forms\"\n\"导航组件\" = \"Navigation\"\n" +
  "\"数据展示\" = \"Data\"\n\"图表\" = \"Charts\"\n\"代码文档\" = \"Code & Docs\"\n\"Store\" = \"Store\"\n" +
  "\"反馈组件\" = \"Feedback\"\n\"事件与布局\" = \"Events & Layout\"\n\"窗口\" = \"Window\"\n" +
  "\"系统集成\" = \"System\"\n\"图标库\" = \"Icon Library\"\n\"画布与富文本\" = \"Canvas & Rich Text\"\n" +
  "\"过渡与效果\" = \"Motion & Effects\"\n\"系统能力探测\" = \"Sys Probe\"\n" +
  "\"图标字体\" = \"Icon Font\"\n\"国际化\" = \"i18n\"\n\"RTL 排版\" = \"RTL Type\"\n" +
  "\"g.components\" = \"Components\"\n\"g.system\" = \"System\"\n\"g.localization\" = \"Localization\"\n"
