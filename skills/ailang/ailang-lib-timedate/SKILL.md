---
name: ailang-lib-timedate
description: Library.TimeDate — Time.* wall clock, sleep, format/parse, duration arithmetic. Load for timestamps, delays, or date math. There is no Function.TimeDate.*.
---

# Library.TimeDate (ailang)

Ground truth: `/home/bob/Ailang-Self-Hosting-/Librarys/Library.TimeDate.ailang`.

```
LibraryImport.TimeDate
```

API is **`Time.*`**, not `TimeDate.*`. There is no `Function.TimeDate.tick`, `elapsed`, `nowMicros`, or `formatISO`.

## Wall clock

| Call | Returns |
|------|---------|
| `Time.Unix()` | Unix seconds |
| `Time.UnixMilli()` | Unix milliseconds |
| `Time.UnixNano()` | Unix nanoseconds |
| `Time.Now()` | Timestamp (local offset) |
| `Time.NowUTC()` | Timestamp (UTC) |
| `Time.NowDateTime()` | DateTime |

`Time.FromUnix(unix_timestamp, timezone="UTC")` → DateTime. `Time.Create(year, month, day, …)` builds a DateTime.

## Sleep — milliseconds

`Time.Sleep(duration_ms)` sleeps **milliseconds**, not microseconds.

| Call | Unit |
|------|------|
| `Time.Sleep(ms)` | milliseconds |
| `Time.SleepMilliseconds(ms)` | same as `Sleep` |
| `Time.SleepSeconds(s)` | `Sleep(s * 1000)` |
| `Time.SleepNano(ns)` | nanoseconds |

## Format / parse — named formats, not strftime

```
s  = Time.Format(dt, format)          // default "RFC3339"
dt = Time.Parse(date_string, format="RFC3339")
```

`format` is a name: `RFC3339`, `ISO8601`, `Unix`, `Human`. Not `%Y-%m-%d` / strftime. Unknown names go through `Time.Internal.FormatCustom` / auto-parse.

`Time.FormatDuration(duration, format="auto")` → `"1d 2h …"` / `seconds` / `milliseconds`.

## Add / difference

```
Time.Add(dt, duration)            → DateTime
Time.Subtract(dt, duration)       → DateTime
Time.Difference(dt1, dt2)         → Duration
Time.Timestamp.Add / Subtract / Difference / Compare
```

Build durations with `Time.Duration.Create(seconds, nanoseconds)` or:

`FromMilliseconds` / `FromSeconds` / `FromMinutes` / `FromHours` / `FromDays`.

Also `Time.Duration.Add` / `Subtract` / `TotalMilliseconds` / `TotalSeconds`, `Time.ParseDuration("1h30m")`.

## Calendar

`Time.IsLeapYear(year)` → Boolean. `Time.DaysInMonth(year, month)`.

## Do not invent

| Dead (old skill / demos) | Live |
|---|---|
| `TimeDate.tick` / `elapsed` | `Time.UnixNano` (or Timestamp difference) |
| `TimeDate.sleep(microseconds)` | `Time.Sleep(milliseconds)` |
| `TimeDate.now` / `nowMillis` / `nowMicros` | `Time.Unix` / `UnixMilli` / `UnixNano` |
| `TimeDate.formatISO` / strftime `format` | `Time.Format(dt, "RFC3339"\|"ISO8601"\|"Unix"\|"Human")` |
| `TimeDate.parseISO` | `Time.Parse(s, "RFC3339")` |

The source also declares Timer / Schedule / Timezone helpers. Prefer the calls above; verify any extra name in the library before using it.

Copyright (c) 2025–2026 Sean Collins, 2 Paws Machine and Engineering. SCSL.
