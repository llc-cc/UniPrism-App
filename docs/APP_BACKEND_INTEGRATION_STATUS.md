# APP 后端对接状态

更新日期：2026-07-20

## 已在 APP 接入

| 功能 | 使用的后端接口 | APP 状态 |
| --- | --- | --- |
| 短信验证码登录 | `/api/miniapp/auth/sms/send`、`/api/miniapp/auth/sms/login` | 已接入 |
| 开发环境模拟手机号 | 同上；非生产后端返回 `devCode` | 已接入一键测试，仍使用后端真实 Token |
| 登录态恢复 | `/api/miniapp/auth/me` | 已接入 |
| 游客/登录测评会话 | `/api/explore/session`、`/api/miniapp/explore/session` | 已接入 |
| 测评答案保存与恢复 | `/api/explore/discover/answers` | 已接入 |
| 阶段结果与最终评分 | `/api/interest-v020/stage-preview`、`/api/interest-v020/score` | 已接入 |
| 首页专业推荐与画像卡 | `/api/miniapp/explore/home-popular-majors`、`/api/interest-v020/persona-card` | 已接入 |
| 完整报告 | `/api/miniapp/reports/latest`、`generate`、`status` | 已接入恢复、生成、轮询和正文展示 |
| 数学专业介绍 | `/api/miniapp/explore/math/major-intro` | 已接入文案与图片 |
| 数学课程目录 | `/api/miniapp/explore/math/course-intro-pages` | 已接入 |
| 数学课程内容 | `/api/miniapp/explore/math/professional-page` | APP 已接入解析和页面展示 |

## 当前需要后续完成

| 项目 | 当前实际情况 | 后续处理 |
| --- | --- | --- |
| 线上数学课程详情接口 | 2026-07-20 实测带 `pageId` 请求仍返回页面 ID 列表，没有返回详情正文 | 后端检查该路由的查询参数读取、静态缓存或部署版本；修复后 APP 无需改接口即可展示 |
| 课程互动组件 | 后端已返回 `interaction` 标识，APP 目前展示明确的待适配提示 | 按标识逐个实现 Flutter 原生互动组件 |
| 课程视频播放 | 后端已返回视频地址，APP 目前展示资源卡 | 接入 Flutter 视频播放器、加载和全屏逻辑 |
| 真实报告通知 | APP 当前有本地通知演示，报告页面会主动轮询 | 后端接入推送供应商后，将真实 `reportId` 下发给 APP |
| 账号密码登录 | APP 页面已预留，正式开关关闭 | 后端提供正式密码登录接口后启用 |
| 微信一键登录 | APP 配置已预留，未展示入口 | 完成微信开放平台资料、客户端 SDK 和后端换码/绑定接口 |
| 旧手机号不可用 | 当前没有账号申诉与换绑接口 | 后端完成身份校验、换绑和审计流程后接入 |

## 联调说明

- 默认 API 地址为 `https://uniprism.cn`，可通过 `--dart-define=API_BASE_URL=...` 切换环境。
- 报告接口必须使用已登录用户，并且当前探索会话已经完成测评。
- 公开的专业介绍和课程目录线上接口已验证可访问。
- APP 不为缺失接口制造假数据；接口异常会显示错误和重试入口。
- 模拟手机号只模拟短信送达，必须连接允许返回 `devCode` 的非生产后端；不会生成本地假 Token。
- 可通过 `SIMULATED_PHONE_NUMBER` 指定测试手机号，通过 `ENABLE_SIMULATED_PHONE_LOGIN=false` 关闭入口。
