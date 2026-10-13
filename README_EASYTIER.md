# 鸿蒙 EasyTier 单 App 集成

最终安装的是一个 FlClash HAP、一个图标、一个设置界面和一个系统 VPN。EasyTier 原生库作为 HAR 编译进同一个 App，在 FlClash 的 VPN 扩展进程内运行，无需另装或启动 EasyTier App。

嵌入模式通过 N-API 读取状态和处理套接字保护，不启动独立客户端使用的 kernel/nearby-management Unix Socket。普通 EasyTier 客户端仍保留原有 IPC 启停流程。

## 使用

1. 在 FlClash 导入原有代理订阅。
2. 停止 VPN，点击首页 EasyTier 摘要卡片进入详情，再点右上角设置按钮进入「EasyTier 配置」。原「网络 → EasyTier」入口仍可使用。
3. 填写与其他 EasyTier 节点一致的网络名、网络密钥，以及至少一个可到达的节点 URL，例如 `tcp://vpn.example.com:11010`。每行一个节点。
4. 「补充 IPv4 CIDR（可选）」可留空，已有内容会保留。EasyTier 会自动提供虚拟 IPv4 网段和远端发布的子网路由，包括经过中继的节点；仅在需要额外指定网段时手动补充，每行一个 CIDR。
5. 开启 EasyTier，保存后在主界面启动 VPN。配置页显示自动学习的网段和同步状态；路由变化会更新分流规则，无需重启 VPN。公网继续使用原订阅规则，已学习和手动补充的网段通过内置 EasyTier 转发。

首页只显示紧凑的 EasyTier 摘要卡片，升级时默认追加到已有卡片末尾。它可通过原有「主页编辑」移动、排序、移除或重新添加，后续启动尊重已保存的布局。点击进入独立详情页，查看本机虚拟 IPv4、全部已发现节点的名称和 IP、直连/中继以及实测延迟。详情参考鸿蒙客户端的概况和节点卡片结构；约每两秒刷新，延迟变化不会触发代理配置重载。中继节点没有端到端实测 RTT 时显示“—”，不会用中继服务器的延迟代替。节点来自路由表，断开后的条目可能短暂保留；状态数据过期后不再展示旧延迟。

「EasyTier IPv6」独立控制 EasyTier 与节点之间的 IPv6 连接，默认关闭，旧配置保持原行为。打开后可尝试 IPv6 直连，但仍取决于两端的 IPv6 连通性和防火墙。它不会修改 FlClash 的 IPv6 设置，内网分流仍使用已支持的 IPv4 网段；停止 VPN 后修改，再重新启动生效。EasyTier 关闭时，摘要卡片仍可打开详情与配置。

直连节点提供可用时的本地与远端传输地址，便于区分局域网地址和公网地址。只展示已解析的数字 IP 与端口，不展示 URL 凭据或查询参数；中继节点不借用下一跳的地址。P2P 表示覆盖网的一跳连接，本身不保证选择的是 Wi-Fi 局域网地址。

远端局域网仍需在 EasyTier 节点上配置子网代理。例如访问 `http://192.168.50.10:8080`，需要远端发布 `192.168.50.0/24`；手机不能从远端网卡地址自行推断或创建这条路由。路由快照已收到不代表目标服务已验证连通。

启用期间使用规则模式，切换全局或直连会被拒绝。修改 EasyTier 配置前先停止 VPN，再重新启动。内网 TCP/UDP 经 `127.0.0.1:17890` 的本地 SOCKS5 转发，内核不会为 EasyTier 再创建系统 TUN。17890 不可与 FlClash 的入站端口冲突。

自动学习和手动补充都只接受 RFC1918 私有 IPv4 和 `100.64.0.0/10` 范围的网段，拒绝默认路由、公网、IPv6、回环地址，以及与系统 VPN 的 `172.19.0.0/30` 重叠的网段。已学习但从路由表撤回的网段会保留 `REJECT` 规则，阻止回落到公网代理；重新学习到的网段及手动补充优先使用 EasyTier。既未学习过也未手动指定的私网仍遵循原订阅规则。关闭 EasyTier 或更换网络身份会清除本次学习记录。

启动会等待 EasyTier 分配虚拟 IPv4 并连接至少一个节点，30 秒内未连接则清理本次 VPN 启动。启动失败会显示原生返回的阶段和错误提示，并清除首页计时状态；可据此区分配置、VPN 创建或 EasyTier 启动失败。节点连接成功不代表每个内网服务均已验证连通；可先用实际服务的 TCP/UDP 连接测试。首版不提供 ping、广播发现或其他节点主动连接手机。

诊断版会把 `[STARTUP]`、`[VPN]`、`[EasyTier]` 阶段记录显示在 FlClash 原有日志页面，包括尚在等待连接、启动结果和失败回收。本次构建号为 `2026101306`，启动记录包含版本标记 `ET-LOG-20261013-6`。阶段记录只写必要状态，不主动输出完整配置；原生消息和启动异常中的当前网络密钥会在显示、导出前脱敏。可先进入「工具 → 应用程序 → 日志捕获」开启原有内核日志，复现一次后进入「工具 → 更多 → 日志」，用右上角保存图标导出。诊断记录与普通日志共用最近 1000 条内存记录；切换或重新应用配置不会清空日志，手动清除和重启应用仍会清空。新增记录用于定位失败阶段，不代表已修复真机网络连接。

后台 EasyTier 内核记录使用 `[EasyTier] [Core]` 标记，保留原始日志等级并可导出，但不再逐条弹出通知。明确的 EasyTier 启动或套接字保护失败、VPN 故障及普通代理错误仍保持原有提示。

仅按目标 IP 网段分流。访问内部域名时需自行在 FlClash DNS/Hosts 配置中提供正确的内网解析；本集成不自动改写公网 DNS 或添加域名分流。网络密钥按现有 App 设置机制保存，导出的配置备份也包含它，请按敏感配置管理备份。

## 鸿蒙桌面卡片

桌面 FlClash 卡片显示 VPN 状态、当前配置名和 EasyTier 启用标记，提供 VPN 启停按钮及独立的“打开应用”入口。应用完成初始化并在后台运行时，卡片通过与首页相同的启停流程直接控制现有 VPN；启停中禁止重复提交，最终状态以服务结果为准。

应用进程关闭或尚未完成初始化时，卡片会提示打开应用，通过“打开并操作”进入应用后执行所选操作；首次 VPN 授权或缺少配置也需要在应用中处理。系统强制结束进程后，旧卡片首次点击可能先刷新为需要打开应用的状态。升级后若旧卡片未刷新，请移除并重新添加。卡片属于桌面服务卡片，本版没有增加系统控制中心开关。

## 构建与验证

HAR 是 App 的编译依赖，由 Actions 先编译固定版本的 EasyTier，再放入 `ohos/entry/libs/easytier-ohrs.har`，最后打包同一个 FlClash HAP。这是一个 App 的依赖构建顺序。

修改模型和本地化后生成已有代码：

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart run intl_utils:generate
flutter test test/common/easytier_test.dart
flutter analyze --no-fatal-infos
```

使用支持鸿蒙的 Flutter SDK 和 OpenHarmony SDK 执行仓库原有鸿蒙打包流程。HAR 类型定义必须包含 `runEmbeddedNetworkInstance`、`stopEmbeddedNetworkInstance`、`enableSocketProtection`、`nextSocketProtectionRequest`、`completeSocketProtection`、`disableSocketProtection`、`failSocketProtection` 和 `collectRuntimeStateJson`。

需要真机确认：首次启动及停止、失败回收、重复启动、Wi-Fi/移动网络切换、后台运行，以及跨 EasyTier 节点的 TCP 和 UDP 往返。CI 构建成功不代替这些运行验证。
