# fafu课程表 v2.2.0 · Android 应用

福建农林大学课表 App。Flutter 开发，蓝白纯色简约风格。

**v2.2.0**：学校**统一身份认证**登录，**登录一次自动续登**。账号密码加密存本机
（Android Keystore），会话过期时打开 App 自动静默重登——**零后台任务、零常驻通知**，
划掉 App、杀后台都不影响，轻量简洁。

---

## 一、功能

| 模块 | 说明 |
| --- | --- |
| 今日课程 | 主页显示今天的课表，含节次、起止时间、地点、教师，并高亮"即将上课"的那一节 |
| 周课表 | 按周查看，可切换周次；**课表网格**与**列表**两种视图，表头自动标出今天 |
| 课程管理 | 自动同步 + 手动添加 / 编辑 / 删除课程：名称、教师、地点、星期、节次、起止周、单双周 |
| 上课提醒 | 两种方式可选：**推送消息**（通知栏，响一声）／**闹钟提醒**（全屏弹出 + 闹钟铃声 + 震动）；可设提前 5/10/15/20/30 分钟 |
| 自动续登 | 打开 App 时检查会话，过期则用本机加密保存的账号密码静默重登，全程无感 |
| 学期设置 | 设置"开学第一周的周日"，或直接告诉 App"现在是第几周"，用于计算当前周次 |

### 登录

- 学校**统一身份认证**（CAS）登录，账号密码 AES 加密传输、Keystore 加密保存
- 会话过期 → 打开 App 自动静默重登；需要验证码等特殊情况回退到网页手动登录
- 设置页可退出登录（清除会话和账号密码）

### 界面

- 纯净蓝白配色：主色 `#1565C0`，背景 `#F6F9FD`，卡片纯白
- 底部四个 Tab：今日 / 课表 / 课程 / 设置
- 卡片式圆角布局，无阴影、无渐变，扁平简约

---

## 二、使用

1. 打开 App → 用学号/手机号 + 统一身份认证密码登录一次
2. 自动同步课表，之后每次打开自动检查并同步
3. 到「设置」→「上课提醒」选择提醒方式，并按需授权通知/闹钟权限

作息时间（第 N 节的起止时刻）写在 `lib/theme.dart` 的 `PeriodTime` 中，
若与学校实际作息不符，改这里即可。

---

## 三、项目结构

```
lib/
├── main.dart                     入口 + 底部导航（打开自动同步，无后台任务）
├── theme.dart                    蓝白配色与节次作息时间表
├── models/course.dart            Course / Schedule 模型、周次判断
├── services/
│   ├── store.dart                本地存储（课表、学期设置、提醒设置、会话）
│   ├── credential_store.dart     账号密码加密存储（flutter_secure_storage）
│   ├── cas_client.dart           静默 CAS 登录（AES 加密账号密码，纯 HTTP）
│   ├── timetable_api.dart        课表接口（CAS Cookie + JWT，X-APP-CODE 伪装官方客户端）
│   ├── sync_service.dart         会话检查 + 静默重登 + 课表同步
│   ├── notification_service.dart 推送消息 / 闹钟两种提醒
│   ├── reminder_planner.dart     由课表推算未来两周的提醒时刻
│   └── startup_log.dart          启动异常记录（防白屏）
├── pages/                        home / week / courses / course_edit / settings /
│                                 login（原生） / web_login（网页回退）
└── widgets/                      course_card / week_picker
```

## 四、构建

```bash
flutter pub get
flutter build apk --release
```

或推送到 main 分支，GitHub Actions 自动构建并发布 Release。

产物为 arm64 APK（minSdk 24）。
