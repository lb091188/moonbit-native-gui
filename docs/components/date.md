# Date & time

Value model (`ui/datetime.mbt`): `DateYMD{y,m,d}`, `TimeHMS{h,m,s}` (seconds default 0; `format(show_seconds=true)` yields `HH:MM:SS`), `DateRange`, `TimeRange`, `DateTimeRange`, with the pure functions `month_grid` (calendar cells), `month_shift` (month paging), `days_in_month`, `date_leap` (leap year), `date_weekday`, `range_state_of` (range membership), `today_date` (system today), `time_clamp` (time clamping).

### `calendar(on_pick? : (DateYMD) -> Unit, …)`

- Inline month calendar: ‹/› change the month, click picks a day

### `date_picker(value : Store[DateYMD?], on_change?, …)`

- Date picker: field + month-calendar popup; the pick echoes back as `YYYY-MM-DD`

### `date_range_picker(value : Store[DateRange], on_change?, …)`

- Date-range picker

### `time_range_picker(value : Store[TimeRange], on_change?, …, show_seconds?)`

- Time-range picker: columnar stepper popup (each column is + / value / − / unit, `:` separated, wrapping at the bounds), not `input`; `show_seconds=true` adds a seconds column

### `datetime_range_picker(value : Store[DateTimeRange], on_change?, …)`

- Date-time range picker

> "Today" goes through `wm_local_date` → `@shell.local_ymd()` for system calendar time; the monotonic `now_ms` clock cannot derive a date.
