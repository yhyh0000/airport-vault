class AppChangelogEntry {
  const AppChangelogEntry({
    required this.version,
    required this.date,
    required this.changes,
  });

  final String version;
  final String date;
  final List<String> changes;
}

const appChangelogEntries = <AppChangelogEntry>[
  AppChangelogEntry(
    version: 'v0.5.10',
    date: '2026-09-20',
    changes: [
      '修复宝可梦礼品卡兑换结果类型的空值分析问题',
    ],
  ),
  AppChangelogEntry(
    version: 'v0.5.9',
    date: '2026-09-20',
    changes: [
      '修复宝可梦登录后仅保存 auth_data 时无法绑定账户的问题',
    ],
  ),
  AppChangelogEntry(
    version: 'v0.5.8',
    date: '2026-09-20',
    changes: [
      '宝可梦机场详情页新增 8.8 免费套餐兑换码入口',
      '接入宝可梦礼品卡真实 API，兑换成功后自动刷新套餐和订阅地址',
      '修复宝可梦 API 主机、授权头和加密响应解析，避免登录后数据为空',
    ],
  ),
  AppChangelogEntry(
    version: 'v0.5.7',
    date: '2026-09-20',
    changes: [
      '移除仪表盘中的重复机场登录、绑定和订阅导入业务',
      '仪表盘改为只读机场状态摘要，机场页面作为唯一账户管理入口',
    ],
  ),
  AppChangelogEntry(
    version: 'v0.5.6',
    date: '2026-09-20',
    changes: [
      '新增独立机场账户仓页面，统一承载账户、签到和订阅来源状态',
      '移动端导航调整为总览、机场、节点、订阅、工具',
      '节点页和订阅页使用更清晰的业务语义，保持 Mihomo 运行能力不变',
    ],
  ),
  AppChangelogEntry(
    version: 'v0.5.5',
    date: '2026-09-20',
    changes: [
      '恢复并前置粘贴订阅链接入口，支持剪贴板直接导入',
      '机场账户面板同时支持自动发现订阅和手动导入订阅',
      '补充机场钥仓三项目融合后的产品设计与信息架构文档',
    ],
  ),
  AppChangelogEntry(
    version: 'v0.5.4',
    date: '2026-09-20',
    changes: [
      '登录页统一为机场钥仓品牌化原生外壳，保留机场官方网页登录与验证码流程',
      'iKun 同步读取订阅记录页，过滤 /user/subscribe_log 页面链接并提取真正订阅地址',
    ],
  ),
  AppChangelogEntry(
    version: 'v0.5.3',
    date: '2026-09-20',
    changes: [
      '修复机场订阅地址为空或缺少 host 时导入配置报 DioException',
      '兼容 /link/、//host/link/ 和 HTML 转义订阅地址，并增加导入前地址校验',
    ],
  ),
  AppChangelogEntry(
    version: 'v0.5.2',
    date: '2026-09-20',
    changes: [
      '同步更新 iKun 当前主要域名的入口测试，确保 Release 构建正常通过',
    ],
  ),
  AppChangelogEntry(
    version: 'v0.5.1',
    date: '2026-09-20',
    changes: [
      '修复 iKun 自动测速误选域名说明页导致登录后无账户数据的问题',
      '优先使用当前官方主要域名，并要求入口探测必须返回真实邮箱和密码登录表单',
    ],
  ),
  AppChangelogEntry(
    version: 'v0.5.0',
    date: '2026-09-20',
    changes: [
      '修复 iKun 登录成功后 HttpOnly 会话 Cookie 未完整回传，补充 Android 原生 CookieManager 读取与持久化',
      '适配 iKun 当前用户页的今日已用、剩余流量和 /link/ 订阅地址结构',
      '账户同步增加 /user/profile 兼容回退，提升不同 iKun 主题页面的数据读取成功率',
    ],
  ),
  AppChangelogEntry(
    version: 'v0.4.0',
    date: '2026-09-20',
    changes: [
      '机场登录页改为与 App 统一的原生卡片、配色和状态栏布局',
      '保留机场官方网页登录与验证码流程，并在页面内注入轻量统一样式',
      '登录状态和完成绑定操作集中到原生底部操作栏，减少网页页面与 App 的割裂感',
    ],
  ),
  AppChangelogEntry(
    version: 'v0.3.1',
    date: '2026-09-20',
    changes: [
      '修正机场入口单元测试仍断言已过期域名的问题，恢复 Android 发布流水线',
      '入口测速全部失败时自动回退默认入口，不再要求用户手动选择地址',
    ],
  ),
  AppChangelogEntry(
    version: 'v0.3.0',
    date: '2026-09-20',
    changes: [
      '登录时自动并行探测机场入口并选择最快可用地址，不再要求用户手动挑选域名',
      '订阅导入携带机场登录 Cookie/Token，并保存到订阅源用于后续自动更新',
      '账户中心增加订阅地址复制和明确的导入结果提示，补齐机场管理核心链路',
    ],
  ),
  AppChangelogEntry(
    version: 'v0.2.2',
    date: '2026-09-20',
    changes: [
      '宝可梦绑定支持自定义 HTTPS 入口，机场更换域名后无需等待发版',
      '网页入口加载失败时显示具体错误和重试提示',
    ],
  ),
  AppChangelogEntry(
    version: 'v0.2.1',
    date: '2026-09-20',
    changes: [
      '修复 iKun 默认入口证书过期导致 WebView 无法加载的问题，切换到可用的 ikuuu.pw 域名',
    ],
  ),
  AppChangelogEntry(
    version: 'v0.2.0',
    date: '2026-09-20',
    changes: [
      '机场账户改为原生绑定流程，登录成功后自动返回账户中心',
      '新增账户状态、流量、到期时间、签到和订阅导入入口',
      '完善 iKun 与 Pokemon 的登录失效提示和重新绑定流程',
    ],
  ),
  AppChangelogEntry(
    version: 'v2.2.3',
    date: '2026-09-12',
    changes: ['优化界面长按反馈显示'],
  ),
  AppChangelogEntry(
    version: 'v2.2.2',
    date: '2026-09-11',
    changes: [
      "解决了一些影响使用体验的bug",
      "修复订阅排序偶发失效",
      "调整主题色彩预设",
      "优化首次订阅导入的内核预热",
      "优化UI文案显示",
      "减少弹窗噪音",
    ],
  ),
  AppChangelogEntry(
    version: 'v2.2.1',
    date: '2026-09-10',
    changes: ["修复网络、DNS、自定义规则等设置未正确生效的问题；优化仪表盘延迟数值显示，避免文字拥挤或裁切。"],
  ),
  AppChangelogEntry(
    version: 'v2.2.0',
    date: '2026-09-09',
    changes: ["优化大量订阅下代理界面卡顿问题", "整理了一些启动链路上的时序问题"],
  ),
  AppChangelogEntry(
    version: 'v2.1.9',
    date: '2026-09-07',
    changes: ['降低订阅同步内存占用', '优化代理被回收后的恢复'],
  ),
  AppChangelogEntry(
    version: 'v2.1.8',
    date: '2026-09-07',
    changes: ["提升代理留存能力，优化后台低内存回收"],
  ),
  AppChangelogEntry(
    version: 'v2.1.5',
    date: '2026-09-02',
    changes: [
      "优化代理页超长节点名称显示，卡片折叠展开滚动动画，节点卡片长按显示叶子节点全称",
      "修复双开、分身应用网络受限",
      "更新版本号",
      "优化应用内更新检查与下载，GitHub 访问受限时自动使用加速线路并校验 APK 完整性",
    ],
  ),
  AppChangelogEntry(
    version: 'v2.1.4',
    date: '2026-09-01',
    changes: ['优化流媒体检测YouTube检测结果'],
  ),
  AppChangelogEntry(
    version: 'v2.1.3',
    date: '2026-08-31',
    changes: ["优化代理留存能力", "优化仪表盘UI显示"],
  ),
  AppChangelogEntry(
    version: 'v2.1.2',
    date: '2026-08-25',
    changes: ["优化显示体验", "提升静态色彩模式下的视觉效果"],
  ),
  AppChangelogEntry(
    version: 'v2.1.1',
    date: '2026-08-25',
    changes: [
      "优化 VPN 启停、服务连接及状态同步，减少后台运行、界面重建和首次启动时的异常状态。",
      "优化订阅与配置更新链路，加强 Mihomo 配置校验与字段保护，降低更新失败或配置被意外覆盖的风险。",
      "优化代理组、节点更新及延迟预热流程，减少配置切换时的竞争与等待，提升日常使用流畅度。",
    ],
  ),
  AppChangelogEntry(
    version: 'v2.1.0',
    date: '2026-08-21',
    changes: [
      "重构 Mihomo 配置兼容逻辑，提升原生配置的兼容性与稳定性。",
      "优化代理组选择、节点固定及状态同步，更贴近 Mihomo 原生行为。",
      "优化网络诊断、智能暂停与 VPN 运行逻辑，提升日常使用稳定性。",
      "优化启动、页面切换和后台任务，降低不必要的资源占用。",
    ],
  ),
  AppChangelogEntry(
    version: 'v2.0.9',
    date: '2026-08-17',
    changes: [
      "优化英文界面文案与文字缩放适配，减少多处文本截断。 优化流媒体检测界面及模式选择菜单显示。 修复 Worker 备份恢复时误清空脚本、规则和策略组的问题。 优化订阅类型标签与订阅名称的对齐效果。",
    ],
  ),
  AppChangelogEntry(
    version: 'v2.0.8',
    date: '2026-07-24',
    changes: ["修复仅统计代理流量 优化订阅卡信息布局"],
  ),
  AppChangelogEntry(
    version: 'v2.0.7',
    date: '2026-07-22',
    changes: [
      'changelog207Item1',
      'changelog207Item2',
      'changelog207Item3',
      'changelog207Item4',
    ],
  ),
  AppChangelogEntry(
    version: 'v2.0.5',
    date: '2026-07-19',
    changes: ['changelog205Item1', 'changelog205Item2', 'changelog205Item3'],
  ),
  AppChangelogEntry(
    version: 'v2.0.4',
    date: '2026-07-17',
    changes: ['changelog204Item1', 'changelog204Item2', 'changelog204Item3'],
  ),
];

const lastShownChangelogVersionKey = 'lastShownChangelogVersion';

bool shouldShowChangelogAfterUpdate({
  required bool wasUpdated,
  required String? lastShownVersion,
  List<AppChangelogEntry> entries = appChangelogEntries,
}) {
  if (!wasUpdated || entries.isEmpty) return false;
  return lastShownVersion != entries.first.version;
}
