# iKun / 宝可梦机场真实网页业务调研

> 调研时间：2026-09-20  
> 调研方式：使用已授权账号登录真实网页，读取登录后页面、路由、控件结构和前端公开调用逻辑。  
> 安全说明：本文不保存邮箱、密码、Cookie、Token、订阅 Token、IP 或完整订阅地址。

## 结论先行

这两个机场不能共用一套“登录后抓一个页面”的实现：

| 机场 | 网站形态 | 登录态 | 订阅入口 | 账户页面 |
| --- | --- | --- | --- | --- |
| iKun | SSPANEL 风格的服务端渲染页面 | Cookie 会话 | 首页便捷导入区域，订阅地址以编码字段和客户端映射提供 | `/user` |
| 宝可梦 | Vue/XBoard 风格的 SPA | 登录响应中的 Bearer Token，前端还保存 `auth_data` | `/dashboard` 的设备 Tab、通用订阅链接和一键导入 | `/dashboard` |

移动端应分别实现两个 Adapter，只共享账户状态、订阅导入和错误模型，不共享请求路径和解析器。

## 一、iKun 真实业务

### 1. 路由和页面职责

真实登录页为：

```text
GET /auth/login
```

登录成功后跳转：

```text
GET /user
```

已确认的登录后页面：

| 路径 | 真实职责 | 移动端用途 |
| --- | --- | --- |
| `/user` | 首页仪表盘、账户统计、签到状态、便捷订阅入口 | 账户同步主页面 |
| `/user/profile` | 账号安全、通知开关、登录 IP 记录 | 账户详情和安全状态 |
| `/user/node` | 免费版/专业版节点列表，展示地区、倍率、限速 | 辅助信息，不作为订阅源 |
| `/user/tutorial` | 各平台客户端和教程入口 | 帮助页 |
| `/user/subscribe_log` | 订阅使用审计记录 | 仅用于确认订阅请求是否成功 |
| `/user/edit` | 节点相关设置 | 后续按需求接入 |

`/user/subscribe_log` 不是订阅链接页面。它只显示订阅访问的 ID、客户端类型、IP、时间和 User-Agent。此前把这个页面当成订阅地址来源，是订阅导入失败的主要原因之一。

### 2. 登录态和会话校验

- 登录表单是邮箱、密码和 Geetest 4 验证。
- 登录成功的可靠信号是页面进入 `/user`，并出现“首页”、账户统计和侧边菜单。
- App 不能只判断 WebView URL 是否离开 `/auth/login`，应再次读取 `/user` 的账户标识和统计卡片。
- iKun 的登录态必须通过 Android WebView 的 CookieManager 持久化；原始密码不应保存。
- 后续网页请求应继续携带会话 Cookie，并使用当前站点的 `Referer`/`Origin`。

### 3. `/user` 可读取的账户数据

首页实际展示：

- 会员时长/套餐状态；
- 剩余流量和今日已用流量；
- 在线设备数和上次使用时间；
- 钱包余额和返利信息；
- 服务端实际时间与设备时间校准提示；
- 公告和使用限制；
- 最近 72 小时流量图的“加载数据”入口；
- “便捷导入”区域。

移动端第一版应优先同步前四项和签到状态，公告及长篇说明放到折叠详情中，不能把整页公告当成首页主体。

### 4. 签到状态

当前真实账号首页显示：

```text
明日再来
```

对应 DOM 是 `#checkin-div` 内的 disabled 按钮，没有可直接复用的页面 `onclick`。这说明当前账号当天已经完成签到，不能据此猜测一个固定的 `/user/checkin` 请求。

移动端实现规则：

1. 先同步 `/user`；
2. 识别签到按钮文字和 disabled 状态；
3. `明日再来` 显示“今日已签到”；
4. 只有在真实账号处于可签到状态时，才继续抓取有效的表单/请求契约；
5. 不要在没有验证过的情况下强行调用猜测的签到接口。

### 5. 订阅地址的真实来源

首页“便捷导入”区域的结构如下：

- “Clash 订阅链接”下拉菜单；
- “一键导入 Clash 配置”，调用 `importSublink('clashr')`；
- “复制 Clash 订阅链接”；
- “一键导入 Shadowrocket 订阅”，调用 `importSublink('shadowrocket')`；
- V2Ray + SS 与 SS 复制按钮在当前账号页面上是 disabled。

页面中观察到的真实数据字段：

```text
data-clipboard-text-encoded = Base64 编码后的订阅地址
data-clipboard-text-extra   = 额外查询参数，例如 &extend=1
```

页面内的客户端映射逻辑为：

```text
importSublink('clashr')       -> oneclickImport('clash', decodedSubInfo.clashr)
importSublink('shadowrocket') -> oneclickImport('shadowrocket', decodedSubInfo.shadowrocket)
```

实现要求：

- 首选解析 `[data-clipboard-text-encoded]`，Base64 解码后得到完整 URL；
- 额外参数只追加一次；
- 必须用 `Uri.parse` 检查 scheme、host 和 path，host 为空直接报“机场未返回有效订阅地址”；
- 不要把 `/user/subscribe_log` 的链接当订阅地址；
- 导入配置时继续使用登录会话 Cookie，并携带 Referer/Origin；
- 订阅地址属于高敏感 Token，不写日志、不写产品文档、不上传崩溃报告；
- 导入成功后刷新 `/user/subscribe_log` 只作为审计验证，不作为订阅 URL 来源。

### 6. 节点页的含义

`/user/node` 将节点分成“免费版节点”和“专业版节点”，每个节点展示：

- 节点名称和地区；
- 倍率；
- 限速/带宽；
- 简短描述。

节点页是网站展示信息，不应替代 Clash 订阅配置。真正用于 Mihomo 的节点列表仍以订阅返回内容为准。

## 二、宝可梦真实业务

### 1. 登录和路由

登录页实际从 `/#/login` 解析到：

```text
/login
```

登录表单没有 Geetest，输入邮箱和密码后直接登录。登录成功跳转：

```text
/dashboard
```

当前页面实际加载的 API 模块中可确认的登录调用契约（API 主机与门户页面分离）：

```http
POST https://api123.136470.xyz/api/v1/passport/auth/login
Content-Type: multipart/form-data

{
  "email": "邮箱",
  "password": "密码"
}
```

前端请求层从 `localStorage.auth_data` 读取认证值，并在后续请求发送：

```http
Authorization: <auth_data>
theme-ua: mala-pro
```

接口响应经过前端公开的 10 层替换解码后再解析 JSON。当后续请求返回 403 时，网站会清理登录态并回到 `/login`。

移动端实现要求：

- 宝可梦当前登录页可以继续使用官方 WebView 完成登录；保存 `auth_data` 或用户 Token 后，再由 API Adapter 请求数据；
- API base 默认是 `https://api123.136470.xyz/api/v1`，同时读取网页配置中的 `api_base_url` 覆盖值；
- `auth_data` 已带 `Bearer ` 时原样发送，否则补上 `Bearer `；
- 403 统一转换为“登录已过期，请重新绑定账户”；
- 不把 Token 写入日志或异常上报；
- API 返回的加密字符串必须先按网页同样的替换表解码 10 次，再解析 JSON，不能把编码响应当普通 JSON。

### 2. `/dashboard` 页面职责

登录后首页实际包含：

- 套餐名称、剩余时长和续费/升级入口；
- 流量已用、剩余和流量重置倒计时；
- Windows、Mac、Android、iOS 客户端下载入口；
- “订阅与导入”区域；
- 系统公告弹窗。

左侧业务菜单实际包括：

```text
主页 / 套餐购买 / 订单列表 / 工单列表 / 文档中心
个人信息 / 邀请信息 / 流量明细 / 节点地图 / 苹果账号
```

移动端不需要复制整套后台菜单，应把账户、流量和订阅放在机场详情页，把套餐/订单/工单作为后续扩展功能。

### 3. 订阅与导入真实逻辑

首页提供三个设备 Tab：

```text
苹果手机软件 / 安卓手机软件 / Windows 和 Mac 电脑软件
```

Android Tab 实际显示：

- ClashMeta；
- 其他由 `window.APP_CONFIG.appDisplay` 控制是否显示的客户端；
- “一键导入”；
- “重置密钥”；
- “复制通用订阅链接”。

前端公开模块确认了以下核心逻辑：

```text
subscribeUrl = subscribe_url + '&flag=' + clientFlag + '&name=' + siteName
```

客户端深链格式包括：

```text
Clash / ClashMeta:
clash://install-config?url=<encoded-subscribe-url>&name=<name>

Sing-box:
sing-box://import-remote-profile?url=<encoded-subscribe-url>&name=<name>

Shadowrocket:
shadowrocket://add/sub//<encoded-subscribe-url>?remark=<name>
```

V2rayN/V2rayNG 被标记为 `copyOnly`，页面提示用户复制通用订阅链接后手动导入；其他客户端优先使用一键导入。

网页前端每 5 秒和窗口获得焦点时读取 `subscribe_url`，说明订阅地址可能由登录响应或“重置密钥”动作写入前端状态，而不是固定渲染在普通 DOM 属性上。

当前 API 模块还确认了订阅地址接口：

```http
GET https://api123.136470.xyz/api/v1/user/getSubscribe
Authorization: <auth_data>
```

返回对象的 `data` 中包含 `subscribe_url`；响应同样需要按网页的替换表解码后读取。移动端不应读取或记录完整订阅 Token，只在内存中交给导入器。

移动端实现要求：

1. 登录成功后主动获取/解析通用订阅地址；
2. 地址有效后自动生成 ClashMeta/Mihomo 导入任务；
3. 对原始订阅 URL 追加 `flag` 和 `name` 时保留已有查询参数；
4. “一键导入”只作为辅助深链，核心流程必须有复制链接和 App 内直接导入两个 fallback；
5. “重置密钥”是破坏性操作，会让已有客户端需要重新配置，必须单独二次确认，不能放在普通同步按钮旁边。

当前调研中，宝可梦页面的“复制通用订阅链接”是 Vue 按钮而非 href；它背后的订阅 URL 已通过公开 API 模块确认来自 `/user/getSubscribe`，移动端无需依赖系统剪贴板读取。浏览器页面仍只用于展示和人工兜底，不能把完整订阅 Token 写入日志。

### 4. 8.8 免费套餐兑换

仪表盘套餐卡的真实入口是“兑换礼品卡”，不是套餐购买页中的付费下单。弹窗字段标签为“兑换码”，提交按钮为“兑换”。公开前端组件确认请求契约：

```http
POST https://api123.136470.xyz/api/v1/user/redeemgiftcard
Authorization: <auth_data>
Content-Type: multipart/form-data

giftcard=<兑换码>
```

成功响应包含 `data=true`、`type` 和 `value`。网页按 `type` 展示结果：余额增加、订阅时长增加、套餐流量增加、流量重置或订阅套餐增加时长。移动端应只在宝可梦账户已绑定时显示“领取 8.8 免费套餐”，兑换成功后重新请求 `/user/info` 与 `/user/getSubscribe`，刷新套餐、流量、到期时间和订阅地址；兑换失败应展示服务端消息，不自动重试。

这是会改变账户状态的操作，移动端必须让用户明确点击“兑换”，不能在登录、同步或打开页面时自动提交。

### 5. 宝可梦签到判断

当前宝可梦登录后的真实首页没有看到独立的“每日签到”菜单或签到按钮，核心业务是套餐、流量、订阅和工单。移动端不应照搬 iKun 的签到按钮；如果后续发现 API 返回签到字段，再以账户状态字段驱动 UI。

## 三、移动端真实业务流程

### iKun

```text
测速选入口
  -> /auth/login + Geetest
  -> 保存 WebView Cookie
  -> GET /user 校验登录和读取账户摘要
  -> 解析 data-clipboard-text-encoded
  -> Base64 解码 + 合并 extra 参数
  -> URL 校验
  -> 自动导入 Mihomo/Clash 配置
  -> 再次 GET /user/subscribe_log 作为可选审计验证
```

### 宝可梦

```text
测速选入口
  -> 官方登录页完成登录
  -> 保存 auth_data/Token 到安全存储
  -> API GET /user/info + GET /user/getSubscribe
  -> 读取通用 subscribe_url
  -> 追加 flag/name
  -> 直接导入 ClashMeta 或复制 URL
  -> 兑换入口：POST /user/redeemgiftcard(multipart giftcard)
  -> 兑换成功后重新拉取账户和订阅
  -> 403 清理 Token 并要求重新登录
```

## 四、当前代码需要遵守的边界

1. 仪表盘只显示机场状态摘要；登录、签到、发现订阅、导入只放在机场详情页。
2. iKun 和宝可梦必须有独立 Adapter，不把 iKun 的 Cookie 逻辑套到宝可梦。
3. 订阅地址只在内存和安全存储中短暂存在，日志全部脱敏。
4. 任何 URL 进入 `Uri.parse` 前先做 host 校验，禁止再次出现 `No host specified in URI`。
5. 不把“订阅记录”误做成“订阅链接”。
6. 不把网站节点展示页误做成 Mihomo 配置源。
7. 不把“重置密钥”做成普通刷新动作。
8. 所有登录后接口都要有“会话有效 / 会话过期 / 页面结构变化 / 订阅为空”四类错误状态。

## 五、待继续确认的接口

- iKun 当前账号已显示“明日再来”，因此尚未在可签到状态下确认真正签到请求；后续需要使用一个当天未签到的测试状态或读取前端请求记录。
- 宝可梦 `subscribe_url` 已从公开 API 模块确认来自 `/user/getSubscribe`；真实订阅 Token 仍不写入本文。
- 宝可梦礼品卡兑换已从公开 API 模块确认来自 `/user/redeemgiftcard`，移动端实现需要用真实已登录账号验证成功和失败消息，但不能用调研账号提交兑换码。
- 宝可梦 Android/ClashMeta 的一键导入深链可以确定；最终订阅 URL 是否可直接拉取仍需在移动端使用已保存认证态验证。
