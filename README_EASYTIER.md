# 鸿蒙 EasyTier 单 App 集成

最终安装的是一个 FlClash HAP、一个图标、一个设置界面和一个系统 VPN。EasyTier 原生库作为 HAR 编译进同一个 App，在 FlClash 的 VPN 扩展进程内运行，无需另装或启动 EasyTier App。

嵌入模式通过 N-API 读取状态和处理套接字保护，不启动独立客户端使用的 kernel/nearby-management Unix Socket。普通 EasyTier 客户端仍保留原有 IPC 启停流程。

## 使用

1. 在 FlClash 导入原有代理订阅。
2. 停止 VPN，进入「网络 → EasyTier → EasyTier 配置」。
3. 填写与其他 EasyTier 节点一致的网络名、网络密钥，以及至少一个可到达的节点 URL，例如 `tcp://vpn.example.com:11010`。每行一个节点。
4. 「补充 IPv4 CIDR（可选）」可留空，已有内容会保留。EasyTier 会自动提供虚拟 IPv4 网段和远端发布的子网路由，包括经过中继的节点；仅在需要额外指定网段时手动补充，每行一个 CIDR。
5. 开启 EasyTier，保存后在主界面启动 VPN。配置页显示自动学习的网段和同步状态；路由变化会更新分流规则，无需重启 VPN。公网继续使用原订阅规则，已学习和手动补充的网段通过内置 EasyTier 转发。

远端局域网仍需在 EasyTier 节点上配置子网代理。例如访问 `http://192.168.50.10:8080`，需要远端发布 `192.168.50.0/24`；手机不能从远端网卡地址自行推断或创建这条路由。路由快照已收到不代表目标服务已验证连通。

启用期间使用规则模式，切换全局或直连会被拒绝。修改 EasyTier 配置前先停止 VPN，再重新启动。内网 TCP/UDP 经 `127.0.0.1:17890` 的本地 SOCKS5 转发，内核不会为 EasyTier 再创建系统 TUN。17890 不可与 FlClash 的入站端口冲突。

自动学习和手动补充都只接受 RFC1918 私有 IPv4 和 `100.64.0.0/10` 范围的网段，拒绝默认路由、公网、IPv6、回环地址，以及与系统 VPN 的 `172.19.0.0/30` 重叠的网段。已学习但从路由表撤回的网段会保留 `REJECT` 规则，阻止回落到公网代理；重新学习到的网段及手动补充优先使用 EasyTier。既未学习过也未手动指定的私网仍遵循原订阅规则。关闭 EasyTier 或更换网络身份会清除本次学习记录。

启动会等待 EasyTier 分配虚拟 IPv4 并连接至少一个节点，30 秒内未连接则清理本次 VPN 启动。启动失败会显示原生返回的阶段和错误提示，并清除首页计时状态；可据此区分配置、VPN 创建或 EasyTier 启动失败。节点连接成功不代表每个内网服务均已验证连通；可先用实际服务的 TCP/UDP 连接测试。首版不提供 ping、广播发现或其他节点主动连接手机。

诊断版会把 `[STARTUP]`、`[VPN]`、`[EasyTier]` 阶段记录显示在 FlClash 原有日志页面，包括尚在等待连接、启动结果和失败回收。本次构建号为 `2026101303`，启动记录包含版本标记 `ET-LOG-20261013-3`。阶段记录只写必要状态，不主动输出完整配置；原生消息和启动异常中的当前网络密钥会在显示、导出前脱敏。可先进入「工具 → 应用程序 → 日志捕获」开启原有内核日志，复现一次后进入「工具 → 更多 → 日志」，用右上角保存图标导出。诊断记录与普通日志共用最近 1000 条内存记录；切换或重新应用配置不会清空日志，手动清除和重启应用仍会清空。新增记录用于定位失败阶段，不代表已修复真机网络连接。

仅按目标 IP 网段分流。访问内部域名时需自行在 FlClash DNS/Hosts 配置中提供正确的内网解析；本集成不自动改写公网 DNS 或添加域名分流。网络密钥按现有 App 设置机制保存，导出的配置备份也包含它，请按敏感配置管理备份。

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
