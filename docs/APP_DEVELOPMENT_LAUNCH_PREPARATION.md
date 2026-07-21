# 万有棱镜 App 开发上线前准备与办理清单

> 本文只处理 App 开发、备案、资质、签名、隐私、开发者平台和应用市场提审前准备。推广链接、渠道归因和运营执行另见运营交付文档。
>
> 优先级：`P0` 不确认就不要制作正式包；`P1` 开发期间必须完成；`P2` 提审前完成；`P3` 上线前验收。

## 0. 一页登记表：先在这里填写最终结果

填写规则：内部人员决定的内容直接填写最终值；平台生成的内容填写平台返回值；密码只填写公司密码管理器中的记录位置，不得写入本文或 Git。

| 优先级 | 项目 | 来源 | 建议/示例 | 最终值 | 负责人 | 状态 |
|---|---|---|---|---|---|---|
| P0 | 首发平台范围 | 公司内部决定 | `仅 Android` / `Android+iOS` / `iOS 第二阶段` | 待填写 | 公司/产品 | 待确认 |
| P0 | App 正式名称 | 公司内部决定 | `万有棱镜` | 待填写 | 产品/公司 | 待确认 |
| P0 | 上线主体 | 公司内部决定 | `营业执照上的公司全称` | 待填写 | 公司 | 待确认 |
| P0 | Android Application ID（包名） | 公司与开发决定 | `cn.uniprism.app` | 待填写 | 公司/开发 | 待确认 |
| P0 | Android namespace | 开发填写，建议与包名相同 | `cn.uniprism.app` | 待填写 | 开发 | 待确认 |
| P0 | iOS Bundle ID | 公司与开发决定，再到 Apple 注册 | `cn.uniprism.app` | 待填写 | 公司/开发 | 待确认 |
| P0 | URL Scheme | 公司与开发决定 | `uniprism` | 待填写 | 开发 | 待确认 |
| P0 | 官网域名 | 公司内部决定 | `https://www.uniprism.cn` | 待填写 | 公司/后端 | 待确认 |
| P0 | API 生产地址 | 公司与后端决定 | `https://api.uniprism.cn`；当前代码暂用 `https://uniprism.cn` | 待填写 | 后端 | 待确认 |
| P0 | 静态资源域名 | 公司与后端决定 | `https://assets.uniprism.cn` | 待填写 | 后端 | 待确认 |
| P0 | App 唤醒域名 | 公司与后端决定 | `https://link.uniprism.cn` | 待填写 | 后端/开发 | 待确认 |
| P0 | 隐私政策地址 | 公司提供公开 HTTPS 页面 | `https://www.uniprism.cn/privacy` | 待填写 | 法务/后端 | 待准备 |
| P0 | 用户协议地址 | 公司提供公开 HTTPS 页面 | `https://www.uniprism.cn/agreement` | 待填写 | 法务/后端 | 待准备 |
| P0 | 客服与注销入口 | 公司内部决定 | 客服电话、邮箱、网页地址 | 待填写 | 运营/客服 | 待准备 |
| P0 | iOS 上线主体 | 公司内部决定 | 建议使用组织账号，不使用开发个人账号 | 待填写 | 公司 | 待确认 |
| P0 | iOS 构建环境 | 公司提供，开发使用 | 可签名和上传的 Mac、Xcode | 待填写 | 公司/开发 | iOS 阶段 |
| P0 | iOS 付费报告方案 | 公司、产品和开发决定 | App 内解锁数字报告，原则上接入 Apple IAP | 待填写 | 公司/产品/开发 | iOS 阶段 |
| P0 | 是否面向未成年人 | 公司内部决定 | `是/否；适用年龄` | 待填写 | 产品/法务 | 待确认 |
| P0 | 是否收费 | 公司内部决定 | `免费/报告付费/会员/课程` | 待填写 | 产品/财务 | 待确认 |
| P1 | Android keystore | 开发在公司可信设备生成 | `uniprism-release.jks` | 待生成 | 开发 | 待处理 |
| P1 | Android key alias | 开发决定 | `uniprism_release` | 待填写 | 开发 | 待处理 |
| P1 | Android 正式签名公钥 | 从正式签名证书导出，或由阿里云备案助手从 APK 识别 | 公钥内容/证书文件 | 待生成 | 开发 | 待处理 |
| P1 | Android 证书 MD5 | 从正式签名证书读取，阿里云 APP 备案使用 | `AA:BB:...` | 待生成 | 开发 | 待处理 |
| P1 | Android 证书 SHA-1 | 从正式签名证书读取，部分开放平台使用 | `AA:BB:...` | 待生成 | 开发 | 待处理 |
| P1 | Android SHA-256 | 从正式签名证书读取 | `AA:BB:...` | 待生成 | 开发 | 待处理 |
| P1 | 正式签名 APK | 使用正式 keystore 生成的可安装 APK，不要求全部功能已开发完成 | `app-release.apk` | 待生成 | 开发 | 待处理 |
| P1 | Apple D-U-N-S Number | 公司查询或申请 | 9 位企业识别编号 | 待获取 | 公司管理员 | iOS 阶段 |
| P1 | Apple Team ID | Apple 审核公司账号后分配 | 10 位字符串，如 `A1B2C3D4E5` | 待获取 | 公司管理员 | iOS 阶段 |
| P1 | iOS App ID | Team ID 与 Bundle ID 组成 | `<TeamID>.cn.uniprism.app` | 待获取 | 公司管理员/开发 | iOS 阶段 |
| P1 | App Store Apple ID | App Store Connect 创建 App 后生成 | 数字，如 `6741234567` | 待获取 | 公司管理员 | iOS 阶段 |
| P1 | iOS 证书和描述文件 | Apple/Xcode 创建 | 建议 Xcode 自动签名 | 待获取 | iOS 开发 | iOS 阶段 |
| P1 | iOS 备案证书公钥和 SHA-1 | 从 iOS 签名证书读取 | 提交 iOS 运行平台备案 | 待获取 | iOS 开发 | iOS 阶段 |
| P1 | iOS IAP 商品 ID | App Store Connect 创建 | 如 `cn.uniprism.report.unlock`，最终以商品模型为准 | 待获取 | 产品/公司管理员/开发 | iOS 阶段 |
| P1 | 正式版本号 | 产品与开发决定 | `1.0.0` | 待填写 | 产品/开发 | 待确认 |
| P1 | 首次构建号 | 开发决定，每次上传递增 | `1` | 待填写 | 开发 | 待确认 |
| P1 | 最低系统版本 | 开发决定并测试 | iOS 当前 `13.0`；Android 待确认 | 待填写 | 开发 | 待确认 |
| P1 | APP 备案编号 | 通过接入服务商/分发平台备案后获得 | `省份简称ICP备XXXXXXXX号-XA` | 待获取 | 公司/备案负责人 | 待办理 |
| P1 | 软件著作权 | 中国版权保护中心审核后获得 | 软件名称和版本必须与上线信息一致 | 待获取 | 公司/知识产权 | 待办理 |
| P2 | 商店图标和截图 | 设计提供，开发/运营上传 | 见第 7 节 | 待准备 | 设计 | 待处理 |

## 1. P0：开发正式功能前必须由内部拍板

### 1.1 产品和主体信息

以下内容不是开发人员自行猜测，必须由公司、产品或法务确认。

| 需要决定 | 示例 | 决定后影响 |
|---|---|---|
| 正式 App 名称 | `万有棱镜` | 软著、APP 备案、隐私政策、商店名称和安装名称 |
| 上线主体 | `营业执照上的公司全称` | Apple/Android 开发者账号、备案、合同和收款 |
| 产品服务类型 | `专业方向探索与测评` | 商店分类、备案类目、隐私政策和行业资质 |
| 用户年龄范围 | `主要面向 16 周岁以上用户` | 未成年人保护、同意流程和年龄分级 |
| 收费方式 | `测评免费，完整报告付费` | Apple 内购、Android 支付、退款协议和商店说明 |
| 客服方式 | `客服电话 + 客服邮箱 + App 内客服页` | 隐私政策、注销、投诉和商店审核 |

公司需归档：营业执照彩色扫描件、统一社会信用代码、法人信息、经办人及授权书、公司邮箱和手机号、办公地址、客服信息、域名证书、银行和税务资料。

### 1.2 Android 包名与 iOS Bundle ID

本项目建议 Android 和 iOS 统一使用：

```text
cn.uniprism.app
```

命名依据：公司域名 `uniprism.cn` 反向排列为 `cn.uniprism`，再追加产品段 `app`。

内部命名规则：

- 使用公司长期控制的域名反向命名。
- 只使用小写英文字母、数字和英文句点，避免跨平台差异。
- Android 至少两段，每一段以字母开头；不能使用中文、空格或横杠。
- 首次上架后不得改名；修改会被市场识别为另一个 App。
- 如果以前已经发布过同一 App，必须沿用历史包名和签名，不得直接使用本文示例。

当前工程仍是占位值：

| 平台 | 当前值 | 正式确认后填写位置 |
|---|---|---|
| Android Application ID | `com.example.uniprism_app` | `android/app/build.gradle.kts` 的 `applicationId` |
| Android namespace | `com.example.uniprism_app` | `android/app/build.gradle.kts` 的 `namespace` |
| iOS Bundle ID | `com.example.uniprismApp` | Xcode → Runner Target → General/Signing & Capabilities → Bundle Identifier |
| iOS 测试 Target | `com.example.uniprismApp.RunnerTests` | 跟随正式 Bundle ID 改为 `cn.uniprism.app.RunnerTests` |

官方规则：[Android Application ID](https://developer.android.com/build/configure-app-module)、[Apple Bundle ID](https://developer.apple.com/documentation/BundleResources/Information-Property-List/CFBundleIdentifier)。

### 1.3 URL Scheme、跳转路径和正式链接

URL Scheme 只是地址最前面的协议名称，不是完整跳转路径。

```text
uniprism://open/report?id=8888
└─Scheme   └─Host └Path  └参数
```

建议内部确定：

```text
URL Scheme：uniprism
正式 HTTPS 唤醒域名：https://link.uniprism.cn
```

建议路由：

| 页面 | App 备用 Scheme | 对外正式 HTTPS 链接 |
|---|---|---|
| 首页 | `uniprism://open/home` | `https://link.uniprism.cn/open/home` |
| 测评 | `uniprism://open/test?id=1001` | `https://link.uniprism.cn/open/test?id=1001` |
| 报告 | `uniprism://open/report?id=8888` | `https://link.uniprism.cn/open/report?id=8888` |
| 活动 | `uniprism://open/activity?id=2001` | `https://link.uniprism.cn/open/activity?id=2001` |
| 登录 | `uniprism://open/login` | `https://link.uniprism.cn/open/login` |

不要使用 `app://`：名称过于通用，可能与其他 App 冲突。推广和分享统一使用 HTTPS；Scheme 只作为未配置 Universal Links/App Links 时的备用能力。

开发填写位置：

- Android：`android/app/src/main/AndroidManifest.xml` 的 `intent-filter`。
- iOS：Xcode → Runner Target → Info → URL Types → URL Schemes。
- Flutter：统一 Deep Link 路由解析器，校验页面和参数白名单。

官方说明：[Apple 自定义 URL Scheme](https://developer.apple.com/documentation/Xcode/defining-a-custom-url-scheme-for-your-app)、[Android Intent Data](https://developer.android.com/guide/topics/manifest/data-element)。

### 1.4 生产域名

内部需要确认并写入第 0 节：

| 用途 | 建议示例 | 必须确认 |
|---|---|---|
| 官网 | `https://www.uniprism.cn` | 域名归属、ICP备案、HTTPS |
| API | `https://api.uniprism.cn` | 生产服务器、HTTPS、接口版本和监控 |
| 静态资源 | `https://assets.uniprism.cn` | CDN、HTTPS、防盗链和跨域策略 |
| App 唤醒 | `https://link.uniprism.cn` | Android/iOS 域名验证文件 |
| 隐私政策 | `https://www.uniprism.cn/privacy` | 无需登录即可访问，内容与 App 实际行为一致 |
| 用户协议 | `https://www.uniprism.cn/agreement` | 无需登录即可访问 |
| 客服支持 | `https://www.uniprism.cn/support` | 联系方式真实有效 |

当前代码的 API 默认地址是 `https://uniprism.cn`，静态资源使用 `https://assets.uniprism.cn`。是否改成独立的 `api.uniprism.cn`，由后端确认后再修改。

## 2. P0：立即启动耗时较长的平台和资质申请

这些工作可以与 App 开发并行，但不能拖到开发结束才办理。

### 2.1 Apple Developer 组织账号

如本期上线 iOS，建议使用公司组织账号，避免 App 归属开发个人。

申请入口：[Apple Developer Program](https://developer.apple.com/programs/enroll/)

申请前准备：

- 公司控制的 Apple Account，并开启双重认证。
- 营业执照上的法定公司名称、地址、电话。
- D‑U‑N‑S Number（邓白氏编码）。
- 与公司有关联且可公开访问的官网和域名邮箱。
- 有权代表公司签署协议的联系人及验证材料。
- 年费支付方式。

办理路径：

1. 打开 Apple Developer Program 注册入口并登录公司 Apple Account。
2. 选择 `Organization`，不要误选个人账号。
3. 填写公司法定信息、D‑U‑N‑S、官网和签署权限联系人。
4. 完成身份/公司审核、协议和年费支付。
5. 审核通过后进入 Apple Developer Account → Membership details，抄录 Team ID 到第 0 节。
6. Account Holder/Admin 在 Users and Access 中邀请开发人员，不共享主账号密码。

最终交付：Apple 组织账号、Team ID、Account Holder、开发人员账号权限；只记录账号归属和公司密码管理器记录编号。

官方说明：[Apple 开发者账号概览](https://developer.apple.com/help/account/basics/about-your-developer-account)、[组织注册材料](https://developer.apple.com/help/account/membership/enrolling-in-the-app)。

### 2.2 Android 应用市场公司账号

使用营业执照主体和公司长期邮箱/手机号分别注册。注册完成后邀请开发人员或创建子账号，不直接共享公司主账号密码。

| 平台 | 官方入口 | 控制台内路径 | 首阶段需要上传/填写 | 阶段结果 |
|---|---|---|---|---|
| 华为 | [AppGallery Connect](https://developer.huawei.com/consumer/cn/appgallery) | 控制台 → 用户与访问/认证 → 我的应用 → 新建 | 主体认证、营业执照、联系人；创建 App 时填包名 | 公司账号和应用记录 |
| 小米 | [小米开放平台](https://dev.mi.com/) | 管理中心 → 账号认证 → 应用服务 → 创建应用 | 主体认证、营业执照、联系人；创建 App 时填包名 | 公司账号和应用记录 |
| OPPO | [OPPO 开放平台](https://open.oppomobile.com/) | 管理中心 → 账号认证 → 应用服务 → 创建应用 | 主体认证、营业执照、联系人；创建 App 时填包名 | 公司账号和应用记录 |
| vivo | [vivo 开发者平台](https://developers.vivo.com/) | 管理中心 → 开发者认证 → 应用与游戏 → 创建应用 | 主体认证、营业执照、联系人；创建 App 时填包名 | 公司账号和应用记录 |
| 荣耀 | [荣耀开发者服务平台](https://developer.honor.com/cn/) | 管理中心 → 开发者认证 → 应用服务 → 创建应用 | 主体认证、营业执照、联系人；创建 App 时填包名 | 公司账号和应用记录 |
| 应用宝 | [腾讯开放平台](https://open.tencent.com/) | 管理中心 → 开发者资质 → 移动应用 → 创建应用 | 主体认证、营业执照、联系人；创建 App 时填包名 | 公司账号和应用记录 |

控制台菜单名称可能更新；找不到时在对应平台搜索“开发者认证”“创建应用”“应用上架”。不要在包名尚未由公司确认时创建正式应用记录。

### 2.3 软件著作权

办理入口：[中国版权保护中心](https://www.ccopyright.com.cn/)

建议路径：登录中国版权保护中心版权登记系统 → 计算机软件著作权相关业务 → 计算机软件著作权登记申请。

内部先确认：

```text
软件全称：万有棱镜软件
软件简称：万有棱镜
版本号：V1.0.0
著作权人：营业执照上的公司全称
开发完成日期、首次发表状态：按真实情况填写
```

准备并上传：申请表、公司身份证明、符合要求的源程序材料、用户手册/设计说明书、委托或授权材料。最终归档受理文件和软著证书。

名称和版本必须与后续 APP 备案、应用市场材料保持一致；是否强制以各市场提审时的最新规则为准，但建议现在开始办理。

### 2.4 APP 备案

APP 主办者不是直接在工信部公共查询页自行提交。应通过服务器/云服务接入商，或者符合要求的 App 分发平台，由对方通过国家备案系统代为提交。

办理路径：

1. 确认生产服务器、域名和网络接入服务商，例如实际使用的云服务商。
2. 登录该接入商备案控制台，选择 `APP 备案`；找不到时联系接入商备案客服。
3. 选择已有 ICP 主体或新建主体，填写公司、负责人、App、域名、服务器、服务类目等信息。
4. 按接入商要求上传营业执照、负责人材料、真实性核验和承诺书。
5. 接入商核验后提交公司所在地省级通信管理局。
6. 管局审核通过后取得 APP 备案编号，填写到第 0 节并在 App 显著位置展示和链接备案查询页。

办理前必须有：正式名称、主体、服务类目、图标、域名、服务器接入信息、Android 包名、iOS Bundle ID（上线 iOS 时）和签名证书信息。教育类服务是否需要主管部门前置审核文件，应由公司/备案负责人向所在地通信管理局或接入商确认。

APP 备案不是所有资料都由开发提供。公司/备案经办人先提供主体和产品信息，开发只返回真实技术特征，备案通过后经办人再把备案结果交还开发。

#### 公司/备案经办人先提供给开发

| 资料 | 示例/说明 | 用途 |
|---|---|---|
| APP 最终名称 | `万有棱镜` | 安装名称、备案名称、软著和市场名称保持关联 |
| 上线主体 | 营业执照上的公司全称、统一社会信用代码 | 确定备案主办者 |
| 已有 ICP 信息 | `粤ICP备XXXXXXXX号`、备案主体和域名 | 复用现有备案主体，不由开发猜测 |
| 阿里云备案条件 | 已实名认证的阿里云中国站账号、符合条件的国内服务器和备案负责人 | 由经办人登录和完成身份/短信核验，不向开发共享主账号密码 |
| 备案负责人 | 姓名、公司手机号、邮箱及必要授权 | 接收核验和审核通知 |
| APP 内容分类 | 按真实服务确认，如教育/学习辅助/测评相关类目 | 由产品、公司或法务拍板，开发不自行选择监管类目 |
| APP 主要语言 | 示例：简体中文 | 填写 APP 基础信息 |
| 是否对外提供 SDK | 本项目如不向其他 App 输出 SDK，则填否 | 公司与开发共同确认 |
| APP 正式图标 | 与安装包和市场使用的图标一致 | 填写 APP 基础信息 |
| Android 包名确认 | 建议候选 `cn.uniprism.app`，由公司确认后开发写入 | 开发不能在未确认时自行定为正式值 |
| iOS 是否本期上线 | `仅 Android` / `Android+iOS` / `iOS 第二阶段` | 决定是否现在办理 Apple 账号和登记 iOS 运行平台 |
| iOS Bundle ID 确认 | 建议候选 `cn.uniprism.app`，由公司确认后到 Apple 注册 | 开发不能自行编造 Team ID 或 App Store Apple ID |
| 生产域名和服务器方案 | 已备案域名、API/静态资源域名及阿里云服务器归属 | 开发据此配置真实生产环境 |

#### 开发确认后提供给备案经办人

| 技术资料 | 获取方式 | 是否属于秘密 |
|---|---|---|
| Android 最终包名 | 从正式工程/签名 APK 读取 | 否 |
| 使用正式签名生成的可安装 APK | `flutter build apk --release` | 否，可用于备案检测 |
| 正式签名公钥 | 从签名证书导出，或阿里云备案助手从 APK 识别 | 否 |
| 正式证书 MD5 | 从正式签名证书读取；阿里云 Android APP 备案使用 | 否 |
| 正式证书 SHA-1 | 从正式签名证书读取 | 否，归档备用 |
| 正式证书 SHA-256 | 从正式签名证书读取 | 否，归档并用于 App Links/开放平台 |
| App 实际访问的后台域名 | 根据生产构建和网络请求核对，不能填写未启用的示例域名 | 否 |
| 实际调用的第三方 SDK 清单 | SDK 名称、服务商、用途；以项目依赖和运行行为为准 | 否 |
| 技术功能说明 | 登录、测评、人格画像、报告、支付等真实功能 | 否 |
| iOS Bundle ID（如本期上线） | 从正式 Xcode 工程和 Apple Identifiers 核对 | 否 |
| iOS 签名证书公钥（如本期上线） | 从 Apple 签名证书读取 | 否 |
| iOS 签名证书 SHA-1（如本期上线） | 从 Apple 签名证书读取；阿里云 iOS 运行平台备案使用 | 否 |
| iOS 实际访问的后台域名（如本期上线） | 根据 iOS 生产配置和网络请求核对 | 否 |

其中阿里云 Android APP 备案明确使用包名、签名公钥和证书 MD5；SHA-1、SHA-256同时归档，供开放平台、域名验证和其他市场使用。可以将签名 APK 上传阿里云备案智能助理自动识别特征信息。

同一个名称的 App 同时运行在 Android 和 iOS 时，在同一 APP 备案中添加两个运行平台：Android 填包名、公钥和证书 MD5；iOS 填 Bundle ID、证书公钥和证书 SHA-1。若 Android 备案完成后才增加 iOS，由备案经办人办理新增运行平台/变更备案，不得把未登记的 iOS 特征直接当作已备案。

开发不得交付给备案经办人：

```text
uniprism-release.jks 原文件
keystore 密码
key 密码
android/key.properties
服务器私钥、支付私钥或公司主账号密码
```

#### 备案经办人提交并返还给开发

| 经办人返还内容 | 开发用途 |
|---|---|
| 阿里云备案订单号和提交日期 | 跟踪状态和安排上线时间 |
| 初审/管局补正要求 | 开发只处理其中涉及包名、签名、SDK、域名和功能的问题 |
| 最终 APP 备案编号 | 在 App 显著位置展示并链接备案查询页 |
| 审核通过通知或备案结果截图 | 上架材料归档和应用市场提审 |
| 最终备案的名称、Android/iOS 运行平台、包名/Bundle ID、签名和域名清单 | 开发核对正式构建，避免上线配置与备案不一致 |

五张商店截图不是阿里云 APP 备案的固定五张材料；它们主要用于应用市场详情页。APP 备案当前需要的是 APP 图标和上述基础/运行平台信息，若备案控制台针对当地规则临时要求截图，再由开发与设计按页面要求补充。

不需要等全部 App 功能开发完成才开始备案。名称、包名、正式签名、图标、服务类目、SDK 清单、域名和基础可运行签名 APK 准备完成后即可提交，功能开发继续并行进行。

官方依据：[工信部 APP 备案通知](https://www.gov.cn/zhengce/zhengceku/202308/content_6897341.htm?type=mobile-internet)、[阿里云 APP 备案信息说明](https://help.aliyun.com/zh/icp-filing/basic-icp-service/support/basics-about-icp-filling-for-apps)。备案结果可在 [工信部备案管理系统](https://beian.miit.gov.cn/) 查询。

## 3. P1：开发生成并接入 Android 正式签名

### 3.1 正式签名是什么

Android 正式签名是 App 的长期数字身份。`flutter run` 使用的是自动生成的 Debug 签名，不能用于正式市场发布；正式版必须使用公司自己的 Release keystore。

本项目已经接好 Release 签名读取逻辑：它读取 `android/key.properties`，没有真实配置时会拒绝生成 Release，不会退回 Debug 签名。

### 3.2 生成路径

在公司可信的开发电脑上使用 Android Studio：

1. `Build` → `Generate Signed Bundle / APK`。
2. 选择 `Android App Bundle` → `Next`。
3. `Key store path` 右侧点击 `Create new`。
4. 建议填写：

```text
Key store path：公司受控目录/uniprism-release.jks
Password：公司密码管理器生成的强密码
Alias：uniprism_release
Key password：公司密码管理器生成的强密码
Validity：50 年（不得低于 25 年）
Organization：营业执照上的公司全称
Organizational Unit：Mobile
Country Code：CN
```

5. 生成后立即做至少两份加密备份，由两名授权负责人保管。

官方路径：[Android App Signing](https://developer.android.com/studio/publish/app-signing)。

### 3.3 项目填写位置

将 `android/key.properties.example` 复制为本地 `android/key.properties`：

```properties
storePassword=从公司密码管理器读取
keyPassword=从公司密码管理器读取
keyAlias=uniprism_release
storeFile=D:/公司受控目录/uniprism-release.jks
```

`android/key.properties` 和 `*.jks` 不提交 Git。本文只填写“密钥保管人”和“密码管理器记录编号”。

### 3.4 获取公钥、MD5、SHA-1 和 SHA-256

```powershell
keytool -list -v `
  -keystore "D:\公司受控目录\uniprism-release.jks" `
  -alias uniprism_release
```

输入密码后，将输出中的 `MD5`、`SHA1` 和 `SHA256` 抄录到第 0 节。

需要导出公开证书时执行：

```powershell
keytool -exportcert -rfc `
  -keystore "D:\公司受控目录\uniprism-release.jks" `
  -alias uniprism_release `
  -file "uniprism-release-cert.pem"
```

该 PEM 是公开证书，不是私钥。阿里云备案时也可以直接上传正式签名 APK，由备案智能助理识别包名、公钥和证书指纹。不得提供 keystore 原文件、keystore 密码或 key 密码。

### 3.5 生成正式包

```powershell
flutter build appbundle --release
flutter build apk --release
```

正式包必须由同一个 keystore 签名。若需要同时上架国内市场和 Google Play，应先决定签名托管方案；需要跨多个市场保持同一签名时，保留并使用公司的原始签名密钥。

## 4. P1：iOS 四种 ID、证书和填写路径

### 4.1 四种 ID 一次分清

| 名称 | 示例 | 谁决定/生成 | 在哪里获取 | 填在哪里/用于什么 |
|---|---|---|---|---|
| Bundle ID | `cn.uniprism.app` | 公司与开发先决定 | Apple Developer → Certificates, Identifiers & Profiles → Identifiers → `+` 注册 | Xcode Runner Target 的 Bundle Identifier；App Store Connect 创建 App 时选择 |
| Team ID | `A1B2C3D4E5` | Apple 审核组织账号后分配 | Apple Developer Account → Membership details | 签名、Associated Domains；不需要自行编造 |
| App ID / Application Identifier | `A1B2C3D4E5.cn.uniprism.app` | Team ID + Bundle ID 组成 | 注册 Explicit App ID 后，在 Identifiers 和签名权限中使用 | 证书、描述文件、推送、Universal Links 的服务器关联文件 |
| App Store Apple ID | `6741234567` | App Store Connect 自动生成 | App Store Connect → My Apps → 选择 App → App Information | App Store 详情页链接，如 `https://apps.apple.com/cn/app/id6741234567` |

不要把以下内容混在一起：

```text
Bundle ID：cn.uniprism.app
Team ID：Apple 分配的 10 位字符串
App ID：<Team ID>.cn.uniprism.app
Apple ID：创建商店 App 后生成的纯数字
```

### 4.2 公司/Apple 管理员先提供给开发

开发不能在公司 Apple 组织账号尚未开通时自行产生 Team ID、证书或 App Store Apple ID。公司先完成账号和授权，再把以下信息交给开发：

```text
[ ] 本期是否上线 iOS
[ ] Apple Developer 组织账号已审核通过
[ ] D-U-N-S Number 已确认
[ ] Apple Team ID
[ ] iOS Bundle ID 候选值已确认
[ ] Apple Developer 团队邀请
[ ] App Store Connect 用户邀请
[ ] Developer/App Manager 所需权限
[ ] 可用于 iOS Archive 和上传的 Mac/Xcode 环境
[ ] iOS 是否同步开放付费报告
```

公司通过团队邀请授权，不向开发发送 Apple 主账号密码、双重认证验证码或 Account Holder 私密信息。

### 4.3 注册 Bundle ID / Explicit App ID

入口：[Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list)

路径：

1. `Identifiers` → 左上角 `+`。
2. 选择 `App IDs` → `App`。
3. Description 填 `万有棱镜`。
4. 选择 `Explicit App ID`。
5. Bundle ID 填已经内部确认的 `cn.uniprism.app`。
6. 按需启用 `Associated Domains`、`Push Notifications` 等能力。
7. `Continue` → `Register`。

官方说明：[Register an App ID](https://developer.apple.com/help/account/identifiers/register-an-app-id/)。

### 4.4 创建 App Store Connect App 和数字 Apple ID

入口：[App Store Connect](https://appstoreconnect.apple.com/apps)

路径：

1. `My Apps` → 左上角 `+` → `New App`。
2. Platforms 选择 `iOS`。
3. Name 填 `万有棱镜`。
4. Primary Language 选择 `Simplified Chinese`。
5. Bundle ID 选择已注册的 `cn.uniprism.app`。
6. SKU 填内部唯一编号，例如 `uniprism-ios-001`。
7. 点击 `Create`。
8. 进入 App → `App Information`，将数字 Apple ID 抄录到第 0 节。

创建 App 记录前，Account Holder 必须先签署最新协议。创建权限通常需要 Account Holder、Admin 或 App Manager。[Apple 创建 App 记录](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)。

### 4.5 证书和描述文件

推荐由 Xcode 自动管理，不要求非开发人员手工创建：

1. 在 Mac 安装 Xcode。
2. 打开 `ios/Runner.xcworkspace`，不要打开 `.xcodeproj`。
3. Xcode → Settings → Accounts → 登录受邀的公司开发账号。
4. Runner Target → Signing & Capabilities。
5. 勾选 `Automatically manage signing`。
6. Team 选择公司 Team。
7. Bundle Identifier 确认为 `cn.uniprism.app`。

Xcode 会创建或匹配 Development/Distribution Certificate 和对应 Provisioning Profile。Windows 可以开发 Flutter 和 Android，但最终 iOS Archive、签名和上传必须在 Mac/Xcode 完成。

### 4.6 开发完成后返给公司/Apple 管理员

开发拿到 Team、Bundle ID 和权限后，完成正式 iOS 配置并返还：

```text
[ ] 最终 iOS Bundle ID
[ ] 版本号和构建号
[ ] Xcode Team 和自动签名配置已验证
[ ] iOS Archive/TestFlight 构建
[ ] iOS 权限用途清单
[ ] iOS 第三方 SDK 清单
[ ] iOS 实际收集的数据类型
[ ] iOS 实际后台域名
[ ] URL Scheme 和 Universal Links 配置
[ ] 审核演示账号和核心功能操作说明
```

不将本机私钥、Apple 主账号密码或双重认证验证码放入普通交付文件。证书和描述文件优先通过 Apple 团队权限及 Xcode 自动签名管理。

### 4.7 iOS APP 备案交接

如本期包含 iOS，开发向备案经办人提供：

```text
[ ] iOS Bundle ID
[ ] iOS 签名证书公钥
[ ] iOS 签名证书 SHA-1
[ ] iOS 实际访问的后台域名
[ ] iOS 版本号和构建号
[ ] iOS 第三方 SDK 清单
[ ] iOS 功能说明
```

备案经办人提交后返给开发：

```text
[ ] iOS 运行平台已加入 APP 备案的结果
[ ] 最终备案 Bundle ID、证书和域名信息
[ ] APP 备案编号
[ ] 审核通过通知或补正原文
```

阿里云 iOS APP 特征信息使用 Bundle ID、签名证书公钥和证书 SHA-1。[阿里云 App 特征信息](https://help.aliyun.com/zh/icp-filing/basic-icp-service/user-guide/fill-in-app-feature-information)

### 4.8 iOS 付费报告与 Apple IAP

本项目的“付费解锁完整测评报告”属于 App 内解锁数字内容/功能。若 iOS 版本开放该购买入口，原则上使用 Apple In-App Purchase，不直接照搬 Android 的微信支付或支付宝解锁按钮。[Apple App Review Guidelines 3.1.1](https://developer.apple.com/app-store/review/guidelines/)

公司/产品先提供：

```text
[ ] iOS 报告商品名称和展示文案
[ ] 售价和可售地区
[ ] 一次购买解锁什么内容
[ ] 同一用户是否会购买多份不同报告
[ ] 商品应为消耗型、非消耗型或其他模型的产品结论
[ ] 退款、恢复购买和跨设备权益规则
[ ] App Store Connect 内购管理权限
[ ] 协议、税务和收款信息已完成
```

开发返还：

```text
[ ] 最终 IAP 商品 ID 和客户端配置
[ ] StoreKit 购买流程
[ ] 服务端交易验证和防重复发放方案
[ ] 支付成功、取消、失败和待确认状态
[ ] 恢复购买/账号权益同步（适用时）
[ ] Sandbox/TestFlight 支付测试结果
[ ] 提交内购审核需要的截图和说明
```

公司管理员最后返给开发：

```text
[ ] IAP 商品已创建并可测试的状态
[ ] 审核结果或完整驳回原因
[ ] 正式商品 ID、价格和上架状态
```

商品类型不能只凭“报告”名称决定，应根据用户能否重复购买不同报告、权益是否永久和是否需要恢复购买共同确定。

### 4.9 App Store 隐私和提审交接

公司/法务先提供：

```text
[ ] 隐私政策最终 URL
[ ] 用户协议、客服和隐私选择/账号注销 URL
[ ] 数据收集、保存期限、共享和删除规则
[ ] App Store 名称、副标题、介绍、关键词和年龄分级
[ ] iPhone 商店截图和 1024×1024 图标
[ ] iOS 审核版本的收费说明
```

开发返还：

```text
[ ] App 自身和第三方 SDK 实际收集的数据类型
[ ] 数据是否关联用户身份、是否用于追踪及具体用途
[ ] iOS 权限和 Info.plist 用途说明
[ ] TestFlight 构建、审核账号和审核路径
[ ] 登录、测评、人格画像、报告、IAP 和注销操作说明
```

Apple 管理员在 App Store Connect → My Apps → 万有棱镜 → App Privacy 中填写并发布隐私问卷。隐私政策 URL 为必填，问卷必须覆盖 App 本身及第三方 SDK 的真实数据行为。[Apple App Privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)

### 4.10 Apple 管理员最终返给开发

```text
[ ] App Store Apple ID
[ ] App Store Connect 应用记录和开发访问权限
[ ] TestFlight 内测/外测审核状态
[ ] App Review 完整驳回原因或审核通过通知
[ ] 审核通过的版本号和构建号
[ ] 正式 App Store 详情页链接
[ ] IAP 商品审核和上架状态
```

技术驳回由开发修复；主体、协议、税务、分类和商店材料问题由公司对应负责人处理；隐私和支付问题由公司、法务与开发共同处理。

## 5. P1：配置 Android App Links 与 iOS Universal Links

正式推广、分享和网页跳转统一使用：

```text
https://link.uniprism.cn/open/...
```

### 5.1 Android 域名验证文件

服务器部署：

```text
https://link.uniprism.cn/.well-known/assetlinks.json
```

示例：

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "cn.uniprism.app",
      "sha256_cert_fingerprints": ["正式签名的 SHA-256"]
    }
  }
]
```

填写来源：`package_name` 来自第 0 节 Android 包名；SHA-256 来自第 3 节正式 keystore。官方说明：[Android assetlinks.json](https://developer.android.com/training/app-links/configure-assetlinks)。

### 5.2 iOS 域名验证文件

服务器部署：

```text
https://link.uniprism.cn/.well-known/apple-app-site-association
```

其中应用标识使用：

```text
<Team ID>.cn.uniprism.app
```

Xcode → Runner Target → Signing & Capabilities → `+ Capability` → `Associated Domains`，添加：

```text
applinks:link.uniprism.cn
```

官方说明：[Apple Associated Domains](https://developer.apple.com/documentation/Xcode/supporting-associated-domains)。

### 5.3 验收结果

- 安装 App：点击 HTTPS 链接直接进入对应页面。
- 未安装 App：打开网页或下载落地页。
- 非法页面、非法参数和敏感操作不得直接执行。
- Android Debug、Android Release 和 iOS 分别测试冷启动、后台和前台三种状态。

## 6. P1：隐私、协议、权限和用户权益

公司/法务需要提供，开发根据最终文本实现，不能只写文档不检查真实代码。

### 6.1 公司或法务交付给开发

- [ ] 隐私政策最终正文和公开 HTTPS URL
- [ ] 用户服务协议最终正文和公开 HTTPS URL
- [ ] 个人信息收集清单：字段、目的、方式、必要性和保存期限
- [ ] Android/iOS 系统权限用途清单
- [ ] 第三方 SDK 清单、主体、用途、收集信息和隐私政策链接
- [ ] 数据共享、委托处理和跨境情况
- [ ] 未成年人保护和监护人同意方案（如适用）
- [ ] 账号注销后的数据删除/匿名化规则
- [ ] 客服、投诉和个人信息保护联系人

### 6.2 开发必须实现并测试

- [ ] 首次启动可明确同意或拒绝隐私政策
- [ ] 用户同意前不初始化非必要 SDK、不申请非必要权限
- [ ] 权限按场景申请，拒绝非必要权限不阻断基础功能
- [ ] App 内可再次查看隐私政策、用户协议和 SDK 清单
- [ ] 用户可以撤回授权、查询、更正和删除个人信息
- [ ] 注册、登录、退出、账号注销和客服入口可用
- [ ] 隐私政策描述与 SDK、接口、权限和日志的真实行为一致

## 7. P2：图标、启动页和商店提审材料

### 7.1 设计交付给开发

| 文件/内容 | 示例要求 | 用途 |
|---|---|---|
| App 图标母版 | `app_icon_master.svg` | 后续统一导出 |
| iOS/商店图标 | `1024×1024 PNG`，正方形，不手动画圆角 | iOS Asset Catalog/App Store |
| Android 前景图 | 透明背景，主体位于安全区 | Adaptive Icon foreground |
| Android 背景层 | 纯色或无透明背景图 | Adaptive Icon background |
| Android 单色图 | 单色轮廓 | 主题图标 |
| 启动页 Logo | SVG 或高清透明 PNG | 不同屏幕适配 |
| 启动页背景 | 颜色值/渐变参数 | 不提供整张手机截图 |
| 商店截图 | 按各市场控制台当前尺寸导出 | 应用详情页 |
| 宣传图 | 按各市场控制台当前尺寸导出 | 推荐位/详情页 |

### 7.2 万有棱镜商店截图选择

商店截图是 App 真实页面截图经过设计排版后的宣传图，不是重新虚构五张产品页面。先由开发使用审核演示账号截取原始真机画面，再由设计统一添加标题、背景和手机边框；不得修改成 App 中不存在的功能或结果。

建议先准备 6 张母版，各市场需要 5 张时选择前 5 张或根据平台位置取舍：

| 顺序 | 截图页面 | 截图状态 | 建议宣传标题 |
|---|---|---|---|
| 1 | 兴趣探索首页 | 展示首页核心入口和底部导航，不出现个人手机号 | `从兴趣出发，探索未来方向` |
| 2 | 专业体验/方向探索 | 展示真实专业列表或专业详情 | `了解专业，提前感受学习方向` |
| 3 | 测评答题页面 | 展示一道已选择答案的题目、阶段进度和继续按钮 | `分阶段完成兴趣与能力测评` |
| 4 | 人格画像页面 | 使用完成全部阶段的演示账号，展示已经解锁的金色人格画像，不截“待解锁”占位图 | `形成属于你的人格画像` |
| 5 | 正式报告页面 | 展示报告摘要、方向建议或数据分析，不暴露测试用户隐私 | `获取更完整的成长分析报告` |
| 6（备用） | 互动学习/模拟训练 | 仅在该模块确定作为正式上线功能时使用，展示真实交互界面 | `在互动体验中了解不同方向` |

如果第一版没有完整“课程页面”，不要使用课程页充数。如果互动模块尚未达到正式上线标准，就不放第 6 张。消息页、登录页、我的页面通常不作为首批商店核心截图。

截图交付流程：

1. 开发准备无真实个人信息的审核演示账号和完整测评数据。
2. 使用目标比例的 Android 真机或模拟器截取无调试标记、无系统错误提示的原始图。
3. 设计在截图外增加短标题、品牌背景和统一设备框，不遮挡关键功能。
4. 保存可编辑母版，再按华为、小米、OPPO、vivo、应用宝控制台当期尺寸分别导出。

### 7.3 公司/产品填写的商店信息

- [ ] App 名称、副标题、简短介绍和完整介绍
- [ ] 分类、关键词、收费方式和年龄分级
- [ ] 隐私政策、用户协议、官网和客服 URL
- [ ] APP 备案编号
- [ ] 软件著作权或其他权属证明
- [ ] 行业资质和前置审批文件（如适用）
- [ ] 审核测试账号、密码和操作说明
- [ ] 注册、测评、报告、收费和注销路径说明
- [ ] 权限用途和第三方 SDK 清单
- [ ] 版本号、更新说明、发布时间和支持设备

审核测试账号只放公司受控的提审记录，不在公开文档或 Git 中保存真实密码。

## 8. P2：版本号、构建号和最低系统

当前 Flutter 配置：

```yaml
version: 1.0.0+1
```

含义：

```text
1.0.0：用户看到的版本号
1：构建号，每次向同一平台重新上传都必须递增
```

建议首次正式发布：

```text
版本号：1.0.0
Android versionCode：1
iOS build number：1
iOS 最低系统：当前工程为 iOS 13.0
Android 最低系统：开发完成依赖兼容和目标设备评估后，在第 0 节确认
```

测试包也必须递增构建号，不能反复上传同一个构建号。

## 9. P3：正式提审前验收

- [ ] 正式名称、主体、包名、Bundle ID、签名、备案和软著信息一致
- [ ] Android Release 包使用正式 keystore，签名 SHA-256 与平台记录一致
- [ ] iOS Team、Bundle ID、证书、描述文件和 App Store 记录一致
- [ ] iOS App Privacy 问卷与客户端、SDK、服务端真实数据行为一致
- [ ] iOS 付费报告使用已审核的 IAP 商品，购买、异常处理和权益恢复测试通过
- [ ] iOS TestFlight 构建、审核账号和 App Review 操作说明可用
- [ ] 正式 API、静态资源和唤醒域名可用，HTTPS 证书有效
- [ ] Android App Links 和 iOS Universal Links 验证通过
- [ ] 隐私政策内容与 App 实际权限、SDK、接口和日志一致
- [ ] 首次同意、拒绝权限、撤回授权和注销均测试通过
- [ ] 注册、登录、退出、游客数据隔离、测评、人格画像和报告流程通过
- [ ] 审核账号可以独立完成全部核心流程
- [ ] 华为、小米、OPPO、vivo、荣耀等目标真机测试通过
- [ ] 弱网、会话失效、服务异常和版本接口异常不会锁死 App
- [ ] 上线包、符号表、签名、备案、软著和审核材料完成内部备份

## 10. 实际执行顺序

1. **P0 确认首发平台并开始正式开发**：先决定 `仅 Android`、`Android+iOS` 或 `iOS 第二阶段`；公司名称、上线主体、服务类型、收费、未成年人范围、包名、Bundle ID、Scheme 和域名一经确认，开发即可替换占位配置并进入正式功能开发，不需要等待备案审核完成。
2. **P0 当天启动长周期事项**：Android 市场账号、软著、ICP/APP 备案材料准备并行办理；如本期上线 iOS，同时办理 Apple 组织账号和 D-U-N-S。
3. **P1 建立正式平台身份**：生成 Android keystore、公钥、MD5、SHA-1、SHA-256 和签名 APK；Apple 审核后由公司返还 Team ID 和权限，注册 Bundle ID/App ID 并创建 App Store Connect 应用。
4. **P1 尽早提交 APP 备案**：Android 基础签名 APK 和备案特征齐全后即提交；如本期含 iOS，在同一备案中添加 iOS Bundle ID、证书公钥、SHA-1 和域名。备案审核与 Flutter 功能开发并行。
5. **P1 开发接入配置**：配置生产域名、Scheme、App Links、Universal Links、隐私和权限流程；iOS 同步完成自动签名、TestFlight 和 App Privacy 技术清单。
6. **P1 完成收费链路**：Android 按确认后的支付方案实现；iOS 付费解锁报告按 Apple IAP 方案创建商品、接入 StoreKit 并完成 Sandbox/TestFlight 测试。
7. **P2 准备提审材料**：图标、截图、介绍、测试账号、软著、备案、隐私和行业资质；iOS 同时完成 App Privacy 问卷、年龄分级、IAP 审核材料和 App Review Notes。
8. **P3 验收后提交**：Android 正式签名打包并提交各安卓市场；iOS 在 Mac/Xcode 完成 Archive、上传 App Store Connect 并提交 App Review。

> 本文中的包名、域名和 SKU 是推荐示例，只有填写进第 0 节“最终值”并由负责人确认后，开发才能当作正式配置。各平台菜单和材料要求可能更新，实际提交以对应官方控制台当期页面为准。
