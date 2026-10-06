# fafu课程表 v2.1.1 · Android 应用

福建农林大学课表 App。Flutter 开发，蓝白纯色简约风格。

**v2.1.x**：学校**统一身份认证**登录，自动同步课表，后台保活，会话过期自动提醒。

---

## 一、功能

| 模块 | 说明 |
| --- | --- |
| 今日课程 | 主页显示今天的课表，含节次、起止时间、地点、教师，并高亮"即将上课"的那一节 |
| 周课表 | 按周查看，可切换周次；**课表网格**与**列表**两种视图，表头自动标出今天 |
| 课程管理 | 自动同步 + 手动添加 / 编辑 / 删除课程：名称、教师、地点、星期、节次、起止周、单双周 |
| 上课提醒 | 两种方式可选：**推送消息**（通知栏，响一声）／**闹钟提醒**（全屏弹出 + 闹钟铃声 + 震动）；可设提前 5/10/15/20/30 分钟 |
| 自动同步 | 后台定时同步课表，检测到课程变动推送通知；**心跳保活**每 15 分钟续一次登录会话 |
| 学期设置 | 设置"开学第一周的周日"，或直接告诉 App"现在是第几周"，用于计算当前周次 |

### 登录

- 学校**统一身份认证**（WebView SSO）登录，一次登录
- **心跳保活**：后台每 15 分钟发一次轻量请求续会话，防止登录过期
- 会话过期时推送通知提醒重新登录
- 设置页显示"保活心跳"时间，可判断后台任务是否存活

### 界面

- 纯净蓝白配色：主色 `#1565C0`，背景 `#F6F9FD`，卡片纯白
- 底部四个 Tab：今日 / 课表 / 课程 / 设置
- 卡片式圆角布局，无阴影、无渐变，扁平简约

---

## 二、使用

1. 打开 App → 设置 → **统一身份认证登录**，完成学校登录
2. 自动同步课表（或点"立即同步"）
3. 到「设置」→「上课提醒」选择提醒方式，并按需授权通知/闹钟权限
4. vivo/小米等手机：到系统设置允许 App **后台高耗电** + **自启动**，保证保活任务运行

作息时间（第 N 节的起止时刻）写在 `lib/theme.dart` 的 `PeriodTime` 中，
若与学校实际作息不符，改这里即可。

---

## 三、项目结构

```
lib/
├── main.dart                     入口 + 底部导航
├── theme.dart                    蓝白配色与节次作息时间表
├── models/course.dart            Course / Schedule 模型、周次判断
├── services/
│   ├── store.dart                本地存储（课表、学期设置、提醒设置、会话）
│   ├── timetable_api.dart        课表接口（CAS Cookie + JWT，X-APP-CODE 伪装官方客户端）
│   ├── sync_service.dart         同步逻辑 + 心跳保活
│   ├── background_service.dart   WorkManager 后台任务（15 分钟唤醒）
│   ├── web_login_page.dart       统一身份认证 WebView 登录
│   ├── reminder_planner.dart     由课表推算未来两周的提醒时刻
│   ├── notification_service.dart 推送消息 / 闹钟两种提醒
│   └── startup_log.dart          启动异常记录（防白屏）
├── pages/                        home / week / courses / course_edit / settings
└── widgets/                      course_card / week_picker
```

## 四、构建

```bash
flutter pub get
flutter build apk --release
```

或推送到 main 分支，GitHub Actions 自动构建并发布 Release。

产物为 arm64 APK（minSdk 24）。
