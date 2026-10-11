import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class SchoolClock {
  static tz.Location? _location;
  static tz.Location get location {
    if (_location == null) {
      tzdata.initializeTimeZones();
      _location = tz.getLocation('Asia/Shanghai');
    }
    return _location!;
  }
  static tz.TZDateTime now([DateTime? instant]) =>
      tz.TZDateTime.from(instant ?? DateTime.now(), location);
  static tz.TZDateTime at(int year, int month, int day, [int hour = 0, int minute = 0]) =>
      tz.TZDateTime(location, year, month, day, hour, minute);
}
