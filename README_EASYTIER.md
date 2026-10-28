# 鸿蒙 EasyTier 单 App 集成（v0.9.2 适配）

本轮在 [feature/easytier-ui-v0.9.2-ohos](https://github.com/libo0118/FlClash-ohos/tree/feature/easytier-ui-v0.9.2-ohos) 合并上游 v0.9.2，完整复用其 `material_ui` 与 `lib/ui` 主题和组件，计划版本为 `0.9.2+2026102801`。当前为集成分支；下文描述代码中的使用流程，新版代码生成、分析、测试、HAP 构建与真机验收仍待验证。旧版测试数量或 CI 结果不作为本轮验证证据。

最终安装的是一个 FlClash HAP、一个图标、一个设置界面和一个系统 VPN。EasyTier 原生库作为 HAR 编译进同一个 App，在 FlClash 的 VPN 扩展进程内运行，无需另装或启动 EasyTier App。

嵌入模式通过 N-API 读取状态和处理套接字保护，不启动独立客户端使用的 kernel/nearby-management Unix Socket。普通 EasyTier 客户端仍保留原有 IPC 启停流程。

## 使用

1. 在 FlClash 导入原有代理订阅。
2. 停止 VPN，点击首页 EasyTier 紧凑入口进入详情，再点右上角设置按钮进入「EasyTier 配置」。也可从新版「工具 → 设置 → EasyTier」进入同一详情页。
3. 填写与其他 EasyTier 节点一致的网络名、网络密钥，以及至少一个可到达的节点 URL，例如 `tcp://vpn.example.com:11010`。每行一个节点。
4. 「补充 IPv4 CIDR（可选）」可留空，已有内容会保留。EasyTier 会自动提供虚拟 IPv4 网段和远端发布的子网路由，包括经过中继的节点；仅在需要额外指定网段时手动补充，每行一个 CIDR。
5. 开启 EasyTier，保存后在主界面启动 VPN。配置页显示自动学习的网段和同步状态；路由变化会更新分流规则，无需重启 VPN。公网继续使用原订阅规则，已学习和手动补充的网段通过内置 EasyTier 转发。

首页 VPN 卡片读取原生服务的实际运行状态，可直接启停，查询失败时提供重试；配置开关和计时不能代替运行结果。EasyTier 另用紧凑入口显示状态和已发现节点数，可通过新版主页编辑移动、排序、移除或重新添加。点击进入独立详情页，查看网络、本机虚拟 IPv4、全部已发现节点的名称和 IP、直连/中继及实测延迟，配置页沿用相同主题和表单。约每两秒刷新，延迟变化不会触发代理配置重载。中继节点没有端到端实测 RTT 时显示“—”，不会用中继服务器的延迟代替。节点来自路由表，断开后的条目可能短暂保留；状态数据过期后不再展示旧延迟。

「EasyTier IPv6」独立控制 EasyTier 与节点之间的 IPv6 连接，默认关闭，旧配置保持原行为。打开后可尝试 IPv6 直连，但仍取决于两端的 IPv6 连通性和防火墙。它不会修改 FlClash 的 IPv6 设置，内网分流仍使用已支持的 IPv4 网段；停止 VPN 后修改，再重新启动生效。EasyTier 关闭时，摘要卡片仍可打开详情与配置。

直连节点提供可用时的本地与远端传输地址，便于区分局域网地址和公网地址。只展示已解析的数字 IP 与端口，不展示 URL 凭据或查询参数；中继节点不借用下一跳的地址。P2P 表示覆盖网的一跳连接，本身不保证选择的是 Wi-Fi 局域网地址。

远端局域网仍需在 EasyTier 节点上配置子网代理。例如访问 `http://192.168.50.10:8080`，需要远端发布 `192.168.50.0/24`；手机不能从远端网卡地址自行推断或创建这条路由。路由快照已收到不代表目标服务已验证连通。

启用期间使用规则模式，切换全局或直连会被拒绝。修改 EasyTier 配置前先停止 VPN，再重新启动。内网 TCP/UDP 经 `127.0.0.1:17890` 的本地 SOCKS5 转发，内核不会为 EasyTier 再创建系统 TUN。17890 不可与 FlClash 的入站端口冲突。

自动学习和手动补充都只接受 RFC1918 私有 IPv4 和 `100.64.0.0/10` 范围的网段，拒绝默认路由、公网、IPv6、回环地址，以及与系统 VPN 的 `172.19.0.0/30` 重叠的网段。已学习但从路由表撤回的网段会保留 `REJECT` 规则，阻止回落到公网代理；重新学习到的网段及手动补充优先使用 EasyTier。既未学习过也未手动指定的私网仍遵循原订阅规则。关闭 EasyTier 或更换网络身份会清除本次学习记录。

启动会等待 EasyTier 分配虚拟 IPv4 并连接至少一个节点，30 秒内未连接则清理本次 VPN 启动。启动失败会显示原生返回的阶段和错误提示，并清除首页计时状态；可据此区分配置、VPN 创建或 EasyTier 启动失败。节点连接成功不代表每个内网服务均已验证连通；可先用实际服务的 TCP/UDP 连接测试。首版不提供 ping、广播发现或其他节点主动连接手机。

诊断记录在 FlClash 日志页显示 `[STARTUP]`、`[VPN]`、`[EasyTier]` 阶段，包括等待连接、启动结果和失败回收；版本与阶段标记以实际启动记录为准。阶段记录只写必要状态，不主动输出完整配置；原生消息和启动异常中的当前网络密钥会在显示、导出前脱敏。开启应用设置中的日志捕获，复现后从工具的日志入口打开日志页，用保存操作导出。诊断记录与普通日志共用最近 1000 条内存记录；切换或重新应用配置不会清空日志，手动清除和重启应用仍会清空。新增记录用于定位失败阶段，不代表已修复真机网络连接。

后台 EasyTier 内核记录使用 `[EasyTier] [Core]` 标记，保留原始日志等级并可导出，但不再逐条弹出通知。明确的 EasyTier 启动或套接字保护失败、VPN 故障及普通代理错误仍保持原有提示。

仅按目标 IP 网段分流。访问内部域名时需自行在 FlClash DNS/Hosts 配置中提供正确的内网解析；本集成不自动改写公网 DNS 或添加域名分流。网络密钥按现有 App 设置机制保存，导出的配置备份也包含它，请按敏感配置管理备份。

## 旧配置迁移

升级沿用已有订阅、覆写、DNS/Hosts、EasyTier 网络名、密钥、节点 URL 和补充 CIDR，不要求清空数据或重新导入。EasyTier IPv6 仍默认关闭。旧首页组件按 v0.9.2 的布局读取规则映射为新版组件；鸿蒙已有布局只在首次迁移时补入缺少的 EasyTier 入口，此后尊重已保存的排序与移除。上游主题和布局迁移仍按其自身规则执行。

升级前可用现有备份功能保存配置；备份包含网络密钥。旧配置往返读取、升级后布局持久化与实际流量仍须在本分支重新验证。

## 鸿蒙桌面卡片

原生 Form 保留鸿蒙平台控件，分别显示 VPN 运行状态与 EasyTier 运行状态，并显示当前配置名；EasyTier 开关已打开不等于运行成功。卡片提供 VPN 启停和独立的“打开应用”入口。应用完成初始化并在后台运行时，卡片通过与首页相同的启停流程控制现有 VPN；启停中禁止重复提交，最终状态以服务结果为准。

状态为 unknown、应用进程关闭或尚未完成初始化时，卡片引导打开应用确认并处理；首次 VPN 授权或缺少配置也需要在应用中处理。系统强制结束进程后，旧卡片首次点击可能先刷新为需要打开应用的状态。升级后若旧卡片未刷新，请移除并重新添加。卡片属于桌面服务卡片，本版没有增加系统控制中心开关。

## 构建与验证

HAR 是 App 的编译依赖。鸿蒙构建流程需要先编译固定版本的 EasyTier，再放入 `ohos/entry/libs/easytier-ohrs.har`，最后打包同一个 FlClash HAP；新分支 CI 是否完成此流程，须以本轮实际运行结果为准。

修改模型和本地化后生成已有代码：

```bash
flutter pub get
dart run intl_utils:generate
dart run build_runner build --delete-conflicting-outputs
flutter test test/common/easytier_test.dart
flutter test test/models/config_test.dart test/widgets/easytier_configuration_test.dart test/widgets/easytier_peers_test.dart test/widgets/ohos_vpn_test.dart
flutter analyze --no-fatal-infos
```

使用支持鸿蒙的 Flutter SDK 和 OpenHarmony SDK 执行仓库原有鸿蒙打包流程。HAR 类型定义必须包含 `runEmbeddedNetworkInstance`、`stopEmbeddedNetworkInstance`、`enableSocketProtection`、`nextSocketProtectionRequest`、`completeSocketProtection`、`disableSocketProtection`、`failSocketProtection` 和 `collectRuntimeStateJson`。

待验证：新生成物与源码一致、静态分析及相关测试、鸿蒙 HAP 构建、浅色/深色与大字体下的新 UI、旧配置迁移和布局持久化。需要真机确认：首次授权、启动及停止、失败重试和回收、重复启动、Wi-Fi/移动网络切换、后台运行、原生 Form 状态与操作，以及跨 EasyTier 节点的 TCP 和 UDP 往返。CI 构建成功不代替这些运行验证。
