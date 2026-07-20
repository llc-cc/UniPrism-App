# 万有棱镜 App 登录与账号找回后端需求

> 客户端已支持短信登录，并预留账号密码登录界面。密码登录、旧手机号找回、微信登录和游客数据合并需要后端实现后才能在正式包开放。

## 1. 统一登录响应

短信、密码和微信登录成功后统一返回：

```json
{
  "ok": true,
  "data": {
    "token": "access-token",
    "refreshToken": "refresh-token-if-used",
    "expiresIn": 7200,
    "user": {
      "id": "public-user-id",
      "name": "用户称呼",
      "phoneMasked": "138****0000"
    },
    "exploreSessionId": "merged-session-id"
  }
}
```

错误响应至少区分：参数错误、验证码错误/过期、密码错误、账号锁定、账号不存在、需要绑定手机号、请求过于频繁和服务异常。

## 2. 现有短信登录需要补充确认

现有接口：

```text
POST /api/miniapp/auth/sms/send
POST /api/miniapp/auth/sms/login
```

上线前确认：

- [ ] 图形验证或风控策略
- [ ] 同一手机号、IP、设备的发送频率限制
- [ ] 验证码有效期、错误次数和一次性使用
- [ ] 生产环境永远不返回 `devCode`
- [ ] 登录响应不返回完整敏感资料
- [ ] 短信发送记录和安全审计不记录明文验证码

## 3. 账号密码登录

建议接口：

```text
POST /api/app/auth/password/login
```

```json
{
  "account": "手机号或账号",
  "password": "用户输入的密码",
  "anonymousId": "可选",
  "exploreSessionId": "可选"
}
```

后端要求：

- 密码使用可靠的单向密码哈希算法保存，不得明文或可逆加密保存。
- 支持失败次数限制、短期锁定和安全通知。
- 已有短信账号如果没有设置过密码，不得默认生成可猜测密码。
- 增加设置密码、修改密码和重置密码接口。
- 密码修改或账号找回后撤销旧登录会话。

客户端开关：

```text
--dart-define=PASSWORD_LOGIN_ENABLED=true
--dart-define=PASSWORD_LOGIN_PATH=/api/app/auth/password/login
```

后端未完成前保持关闭。

## 4. 忘记密码与旧手机号停用

需要两种流程：

### 仍能接收原手机号短信

```text
发验证码 → 验证原手机号 → 设置新密码 → 撤销旧会话
```

### 原手机号已经停用

不能仅验证新手机号后直接换绑，否则容易被冒领。建议：

```text
创建找回工单
→ 提交原账号线索和新联系方式
→ 客服/自动风控核验
→ 审核通过后换绑
→ 通知原有联系方式
→ 撤销旧 Token
```

需要主体、产品和法务确定允许收集的核验材料、保存期限、客服处理时限和申诉规则。

## 5. 微信一键登录

需要同时完成：

- 微信开放平台注册移动应用并取得应用身份。
- Android 包名、签名和 iOS Bundle ID 与微信后台一致。
- 客户端接入微信官方移动应用授权 SDK。
- 客户端只获取临时授权码并发送给后端。
- AppSecret 只保存在后端，禁止写入 Flutter 或安装包。
- 后端用临时授权码换取微信身份并建立账号绑定关系。

建议接口：

```text
POST /api/app/auth/wechat/login
```

```json
{
  "code": "wechat-temporary-code",
  "anonymousId": "可选",
  "exploreSessionId": "可选"
}
```

必须处理：微信首次登录绑定手机号、微信已绑定其他账号、手机号账号与微信账号合并、用户解除绑定和微信授权取消。

后端及微信 SDK 未完成前，正式包不展示微信登录按钮。

## 6. 游客进度合并

用户可能先以游客身份完成部分测评，再登录。登录时必须传递或关联：

- `anonymousId`
- 游客 `exploreSessionId`
- 当前测评答案和阶段进度

后端在事务中将游客 Session 绑定到登录用户，返回合并后的 `exploreSessionId`。冲突时需要明确以游客最新进度、账号云端进度还是询问用户为准，不能静默丢失答案。

## 7. 会话与注销

- [ ] Access Token 过期和刷新策略
- [ ] 退出登录撤销本机 Refresh Token
- [ ] 修改密码后撤销其他设备会话
- [ ] 账号注销前再次验证身份
- [ ] 注销完成后 Token 全部失效
- [ ] 数据删除、匿名化和依法保留规则
- [ ] 登录、找回、换绑和注销保留必要安全审计
