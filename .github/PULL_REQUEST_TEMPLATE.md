<!--
一句话标题请按 `【标签】做了什么` 写，提交信息同规。
Keep the title (and commit messages) as `【tag】what it does`, one feature per commit.
-->

## 改了什么 / What changed

-

## 为什么现在需要 / Why now

<!-- 真实用例优先：写你在哪个应用里卡住；参考实现的同名 API 不构成理由。
     Lead with the real use case. "Another toolkit has this" is not a reason on its own. -->

## 关联 / Links

- Issue: `#`
- 路线图条目 / Roadmap entry:

## 门禁读数 / Gate results

在 `gui/` 下执行，两条都要零错误零警告：

```sh
moon check --deny-warn
moon test ui render text theme icons sys input win dbus chart mdview style base shell widget router
```

- [ ] `moon check --deny-warn` 通过
- [ ] `moon test` 对应包全绿（贴最后一次读数行）
- [ ] 改动只碰 C 桩时已 `moon clean` 重链（改桩不重链是已知坑，见 `docs/zh/build.md` §9）
- [ ] 工具链改动另跑 `cd tools/native-gui-tools && moon test ./mngkit ./mng ./proc ./inst`

## 真机验证 / On real hardware

本库的视觉与交互判定由人在真机执行，无头测试不等于界面正确。请写明：

| 平台 | 是否跑过 | 用例编号 / 操作步骤 |
| ---- | -------- | ------------------- |
| Linux | | 例：SC-4.5 |
| Windows | | |
| macOS | | |

未跑的平台请在表里写「未验」，不要留空——路线图按平台标状态（✅ 已验 / 🚧 已合入待真机 / ❌ 未做 / ⏳ 待定）。

## 文档同步 / Docs

- [ ] `docs/zh/` 对应文档已改（中文先行）
- [ ] `docs/` 同路径英文文档已同步
- [ ] `docs/zh/roadmap.md` 状态位已更新
- [ ] 新增真机型：`测试文档/测试用例.md` 补条目（记录台加载它现算清单，不用改网页）
- [ ] 实测坑与口径回写 `experience/adaptation/`

## 破坏性改动 / Breaking changes

<!-- 0.x 阶段允许破坏，但必须在提交信息与文档写明；接口按最严平台定契约。
     Allowed during 0.x, but must be named in the commit message and docs. -->

- [ ] 无破坏 / None
- [ ] 有破坏：影响面与迁移写法
