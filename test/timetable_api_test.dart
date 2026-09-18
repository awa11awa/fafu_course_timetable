// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:fafu_kebiao/services/timetable_api.dart';

void main() {
  test('dateAt 必须是 yyyy-MM-dd HH:mm:ss（只给日期会 400）', () {
    expect(TimetableApi.dateTimeParam('2026-09-18'), '2026-09-18 00:00:00');
    expect(TimetableApi.dateTimeParam('2026-09-18 12:00:00'),
        '2026-09-18 12:00:00');
  });

  test('识别登录页 HTML（网关只认 Cookie，缺了会 302 回来）', () {
    expect(TimetableApi.looksHtml('<!DOCTYPE html><html>'), true);
    expect(TimetableApi.looksHtml('  <html><head>'), true);
    expect(TimetableApi.looksHtml('{"code":200}'), false);
  });

  test('从各种返回里挖 access_token', () {
    expect(TimetableApi.tokenOf('{"access_token":"abc.def.ghi"}'),
        'abc.def.ghi');
    expect(TimetableApi.tokenOf('junk "access_token" : "xyz" tail'), 'xyz');
    expect(TimetableApi.tokenOf('{"error":"access_denied"}'), null);
  });

  test('JWT 载荷取值', () {
    // {"user_name":"张三","user_no":"123"}
    const t = 'x.eyJ1c2VyX25hbWUiOiLlvKDkuIkiLCJ1c2VyX25vIjoiMTIzIn0.y';
    expect(TimetableApi.jwtField(t, 'user_name'), '张三');
    expect(TimetableApi.jwtField(t, 'user_no'), '123');
    expect(TimetableApi.jwtField('bad', 'user_name'), '');
  });

  test('教师名去重', () {
    expect(TimetableApi.cleanTeacher('刘必雄(刘必雄)'), '刘必雄');
    expect(TimetableApi.cleanTeacher('刘必雄（liu bi xiong）'), '刘必雄');
    expect(TimetableApi.cleanTeacher('官明友'), '官明友');
    expect(TimetableApi.cleanTeacher(''), '');
  });

  test('错误提示不出现"空白报错"（转义不可见字符）', () {
    expect(TimetableApi.snippet('\uFEFF'), r'\uFEFF');
    expect(TimetableApi.snippet('\x1f\x8b'), r'\x1f\x8b');
    expect(TimetableApi.snippet('中文正常'), '中文正常');
  });
}
