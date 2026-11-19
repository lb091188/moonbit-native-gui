# 日期与时间

值模型（`ui/datetime.mbt`）：`DateYMD{y,m,d}`、`TimeHMS{h,m,s}`（秒默认 0，`format(show_seconds=true)` 输出 `HH:MM:SS`）、`DateRange`、`TimeRange`、`DateTimeRange`，配纯函数 `month_grid`（月历格子）/ `month_shift`（翻月）/ `days_in_month` / `date_leap`（闰年）/ `date_weekday` / `range_state_of`（区间判定）/ `today_date`（系统今天）/ `time_clamp`（时刻夹取）。

### `calendar(on_pick? : (DateYMD) -> Unit, value? : Store[DateYMD?], today? : DateYMD, class?, handle?)`

- 内联月历：‹ / › 切月，点击选中一天
- `on_pick`：选中回调
- `value`：传入时以 Store 为唯一权威（外部 `set` 立即反映），不传则组件自持
- `today`：基准日，默认系统今天

### `date_picker(value : Store[DateYMD?], on_change?, placeholder?="请选择日期", clearable?=true, today? : DateYMD, width?=180.0, focus_id?, class?, handle?)`

- 日期选择：字段 + 月历浮层，选中回显 `YYYY-MM-DD`
- `clearable`：可清空已选；`today`：基准日

### `date_range_picker(value : Store[DateRange], on_change?, placeholder?="请选择日期区间", clearable?=true, today? : DateYMD, width?=220.0, handle?)`

- 日期区间选择器

### `time_range_picker(value : Store[TimeRange], on_change?, width?=110.0, show_seconds?=false, handle?)`

- 时间区间选择器：列式步进弹层（每列 + / 数值 / − / 单位，`:` 分隔，到界回绕），非 `input`
- `show_seconds`：增加秒列

### `datetime_range_picker(value : Store[DateTimeRange], on_change?, today? : DateYMD, date_width?=130.0, time_width?=86.0, show_seconds?=false, handle?)`

- 日期时间区间选择器

> 「今天」经 `wm_local_date` → `@shell.local_ymd()` 取系统日历时间；单调钟 `now_ms` 不能用于推算日期。
