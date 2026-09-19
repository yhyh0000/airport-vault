# 机场网页业务适配说明

## 为什么采用网页会话

参考 `tianyugithub/linux-sb-mobile` 的实现，本项目不把机场账号密码交给自己的服务器，也不尝试绕过机场的验证码。Android 端打开机场官方网页登录页，用户在页面内完成 Geetest、Telegram 登录或其他挑战；登录后，应用只读取当前站点的 Cookie 与前端 token，并在本机安全存储。

业务请求随后沿用网页端同源访问方式：带上 Cookie、Referer、Origin 和必要的 `X-Requested-With`，读取网页或 JSON，再将结果转换为机场钥仓自己的数据结构。机场域名、HTML 标记和接口可能变化，因此解析器保持容错，并且每个站点的入口可以单独切换。

## 当前适配

### iKun

- 默认入口：`https://ikuuu.top`，同时保留 `ikuuu.pw`、`ikuuu.co`、`ikuuu.ltd`、`ikuuu.fyi`、`ikuuu.win`、`ikuuu.foo` 和 `ikuuu.de` 备用入口。
- 登录：官方 `/auth/login` 页面，网页登录后读取 Cookie。
- 账户页：`/user`，先解开当前站点返回的 base64 页面包装，再从页面文本与 `subscription-userinfo` 响应头读取流量、到期时间和订阅地址。
- 签到：无请求体的 `POST /user/checkin`，按 `ret/msg` 以及“已签到”文案判断结果；不发送空 JSON，避免旧版 SSPanel 返回 405。
- 备注：iKuuu 域名经常变更，入口不应硬编码成永久唯一地址。

### 宝可梦

- 默认入口：`https://web2.52pokemon.cc`，同时保留 `love.52pokemon.cc`、`web4.52pokemon.cc`、`52pokemon.yunjnet.com` 和旧入口备用。宝可梦导航页当前提供主题一 `web2.52pokemon.cc` 与主题二 `love.52pokemon.cc`。
- 登录：优先按 V2Board/XBoard 的 `/#/login` SPA 页面处理；Cookie 之外同时读取 localStorage 中的 token。
- 账户：`GET /api/v1/user/info`，兼容 `u/d/transfer_enable/expired_at` 字段。
- 订阅：`GET /api/v1/user/getSubscribe`，兼容 `subscribe_url/subscribeUrl`。
- 签到：优先 `POST /api/v1/user/checkin`，遇到 404/405 时回退到 `/user/checkin`。

## 失败处理

1. 401、419、登录页重定向或登录页标记出现时，提示用户重新网页登录。
2. 站点返回的提示文案原样脱敏后展示，不把 Cookie、token、密码写入日志。
3. 解析不到流量时仍保留账户登录状态，允许用户刷新或直接导入订阅。
4. 站点改版后只需要更新对应适配器，不影响 Mihomo 订阅与 VPN 内核。

本功能是用户主动操作的本机客户端能力，不提供云端代签，也不内置账号信息。
