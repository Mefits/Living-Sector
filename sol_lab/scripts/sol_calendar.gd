extends RefCounted
## One astronomical calendar for the Sol Lab test. 1 Earth orbit = 1 year.
## Frozen Sol seed: Earth orbital_period = 700 native units.
const EARTH_YEAR_NATIVE: float = 700.0
const DAYS_PER_YEAR: int = 365

static func days_to_native(days: float) -> float:
 return maxf(days, 0.0) * EARTH_YEAR_NATIVE / float(DAYS_PER_YEAR)

static func native_to_days(native_time: float) -> float:
 return maxf(native_time, 0.0) * float(DAYS_PER_YEAR) / EARTH_YEAR_NATIVE

static func calendar_text(native_time: float) -> String:
 var whole_days: int = int(floor(native_to_days(native_time)))
 var year: int = whole_days / DAYS_PER_YEAR + 1
 var day_of_year: int = whole_days % DAYS_PER_YEAR + 1
 return "Год %d · день %03d/%d" % [year, day_of_year, DAYS_PER_YEAR]

static func days_remaining(now_native: float, finish_native: float) -> int:
 return maxi(0, ceili(native_to_days(maxf(
  finish_native - now_native, 0.0))))
