# fafu课程表 v3.0.0 测试版 · Android 应用

福建农林大学课表 App。Flutter 开发，蓝白纯色简约风格。

学校**统一身份认证**登录，保存本地课表；重新打开或回到前台时自动恢复登录并同步。

---

## 一、功能

| 模块 | 说明 |
| --- | --- |
| 今日课程 | 主页显示今天的课表，含节次、起止时间、地点、教师，并高亮"即将上课"的那一节 |
| 周课表 | 按周查看，可切换周次；**课表网格**与**列表**两种视图，表头自动标出今天 |
| 课程管理 | 自动同步 + 手动添加 / 编辑 / 删除课程：名称、教师、地点、星期、节次、起止周、单双周 |
| 上课提醒 | 两种方式可选：**推送消息**（通知栏，响一声）／**闹钟提醒**（全屏弹出 + 闹钟铃声 + 震动）；可设提前 5/10/15/20/30 分钟 |
| 自动同步 | 启动及回到前台时恢复会话并同步；后台按设置频率检查更新，课程变动可通知 |
| 学期设置 | 设置"开学第一周的周日"，或直接告诉 App"现在是第几周"，用于计算当前周次 |

### 登录

- 学校**统一身份认证**（WebView SSO）登录，一次登录
- 登录时分别保存课表网关和学校 CAS Cookie，网关失效后使用 CAS 换取新网关和 JWT
- 杀掉应用后，下次开启会读取保存的会话并尝试同步；网络失败时保留本地课表
- 学校认证目前使用 HTTP，自动恢复需要在应用内明确开启一次；课表和令牌接口使用 HTTPS
- CAS 会话自身失效时仍需重新登录，不保证永久登录

### 界面

- 纯净蓝白配色：主色 `#1565C0`，背景 `#F6F9FD`，卡片纯白
- 底部四个 Tab：今日 / 课表 / 课程 / 设置
- 卡片式圆角布局，无阴影、无渐变，扁平简约

---

## 二、使用

1. 打开 App → 设置 → **统一身份认证登录**，完成学校登录
2. 自动同步课表（或点"立即同步"）
3. 到「设置」→「上课提醒」选择提醒方式，并按需授权通知/闹钟权限
4. 如需后台定时更新，可在系统设置允许后台运行；下次开启时的同步不依赖后台任务运行

### 会话恢复测试

v3.0.0 Release 提供独立包名 `cn.fafu.fafu_kebiao.v3test` 的「FAFU v3 测试版」，
可以与正式版和之前的「FAFU同步测试」同时安装。
独立测试版需要重新登录或导入自己的学校会话，不会读取另一个应用的私有数据。
在设置中选择「导入保存的学校会话」，粘贴手机上脚本生成的
`fafu_sso_session` 文件内容，然后按提示允许 HTTP 认证并同步。
诊断结果 `fafu_sso_result` 不包含 Cookie，不能作为登录会话导入。
会话文件相当于登录凭据，请只在自己的手机中使用，不上传到仓库或发送给别人。

完成一次同步后，杀掉测试应用并重新打开，检查设置里的「上次同步」是否更新。
也可关闭网络后重新打开，确认本地课表仍能显示，再联网回到前台重试。
关闭「自动同步课表」后，应用不会自动发起同步。

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
│   ├── timetable_api.dart        课表接口（CAS Cookie + JWT，X-APP-CODE 标识课表应用）
│   ├── sync_service.dart         登录恢复、课表同步及课程变动检测
│   ├── scoped_session.dart       按域名和路径保存 Cookie，手动处理 CAS 跳转
│   ├── web_session_cookies.dart  从登录 WebView 读取两种会话
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
FAFU_SESSION_TEST=true flutter build apk --release
```

使用 Flutter 3.47.6 和 JDK 17。Release 附件中的 `fafu_course_timetable-v3.0.0-source.zip`
已还原二进制文件；直接从 GitHub 下载仓库源码时，先还原仓库里的 `.b64` 文件：

```bash
find . -name '*.b64' | while read -r f; do
  base64 -d "$f" > "${f%.b64}"
  rm "$f"
done
chmod +x android/gradlew
```

不设置 `FAFU_SESSION_TEST` 时构建原包名应用。测试 APK 使用 CI 调试密钥签名，
后续重新构建的测试包可能需要卸载旧测试版后安装。

`Publish v3.0.0 test release` 工作流先分析改动代码、运行测试，再构建并检查 APK 的
包名和版本；将 APK、可构建源码 ZIP、构建信息和 SHA-256 校验文件一并发布为预发布。
main 分支的普通构建只上传 Actions 产物，不再覆盖已有版本的 Release。

测试 APK 包含多种 Android 架构（minSdk 24）。真实手机的登录、长期会话有效期和学校
服务端撤销策略还需要实际使用验证；学校 CAS 会话过期后仍需重新登录。
