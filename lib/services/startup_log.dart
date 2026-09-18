/// 启动过程与运行期异常记录。
///
/// 设计目标：**任何情况下都不要出现白屏**。若启动环节出错，把错误记录下来并
/// 在界面上显示出来，而不是让用户面对一片空白。
class StartupLog {
  static final List<String> _items = [];

  static List<String> get items => List.unmodifiable(_items);

  static void record(String message) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    if (_items.length > 50) _items.removeAt(0);
    _items.add('[$ts] $message');
  }

  static bool get hasError => _items.isNotEmpty;
}
