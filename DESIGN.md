# 鸿蒙与 EasyTier 的 v0.9.2 设计锚

唯一方向：完整复用上游 v0.9.2 的 `material_ui` 与 `lib/ui`，包括主题、组件、间距、连续曲率圆角和动效；主页、详情、配置属于同一套原生应用界面。不新增 Web 风格、素材或功能，也不再提供多方向设计方案或调用外部模型。

功能契约：用户在 3 秒内能看清 VPN 真实运行状态与独立的 EasyTier 状态，可直接启停 VPN，并在失败时看到重试或进入应用恢复的入口。启用配置不能冒充运行成功；启动中、停止、失败、未知和过期状态必须可区分。

首页 EasyTier 沿用内网 IP 卡的结构：标题与详情入口、真实虚拟 IPv4 及复制按钮、内层圆角状态行与独立的配置启用开关。只有 VPN 运行状态已确认且 EasyTier 遥测为 ready 时展示、复制当前地址；未分配显示已有提示，连接中使用已有骨架，停止、未知、过期和关闭不显示旧地址。开关复用设置页的校验、停机门禁、配置表单与应用路径，异步期间防止重复操作，不启动第二个 VPN。卡片仍通过新版主页编辑移动、移除或重新添加。详情继续展示网络、本机 IPv4、节点、直连/中继、可用的实测延迟及连接地址；工具入口进入同一详情。中继没有端到端 RTT 时显示“—”。

实现以当前源码为准：

- [DashboardCard](lib/views/dashboard/widgets/card.dart) 使用 `dashboardCardPadding` 和 `dashboardCardRadius`，移动端默认内边距为横向 20 dp、纵向 18 dp；[DashboardCorner](lib/views/dashboard/style.dart) 的移动端卡片圆角为 34 dp。EasyTier 与内网 IP 卡共用 `DashboardCardHeader`、`DashboardFitText`、`DashboardSwitchRow`、复制反馈及字阶；内层行沿用内网 IP 的 20 dp 圆角与间距，窄屏大字时按现有规则隐藏图标以保证状态和开关空间。
- [AppShape / AppRadius](lib/ui/shape.dart) 提供连续曲率形状，[AppTextStyle](lib/ui/typography.dart) 提供文字层级，颜色取自主题与 `SurfaceLevel`，不另建调色板。
- 页面沿用 `CommonScaffold`、`CommonCard`、`FormPage` 和 `FormRow`；页面过渡与按压反馈沿用现有组件及 `context.motionDuration`。现有 [motion.dart](lib/ui/motion.dart) 的 `fadeTabDuration` 为 220 ms，不为本次适配另设一套动画参数。

鸿蒙原生 Form 保留平台控件，独立展示 VPN 与 EasyTier 状态；unknown 或应用未就绪时进入 App 确认。配置名、启用标记和旧缓存均不能替代服务结果。

保留已有订阅与 EasyTier 配置，按新版布局规则迁移并持久化用户排序。验收须重新取得本分支证据：启停与错误恢复、入口/详情/配置导航、浅深色与大字体布局、旧配置和 Form；旧版截图、测试数量或 CI 结果不作为本次通过依据。
