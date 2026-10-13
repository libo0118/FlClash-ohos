# 鸿蒙 EasyTier 单 App 集成

最终安装的是一个 FlClash HAP、一个图标、一个设置界面和一个系统 VPN。EasyTier 原生库作为 HAR 编译进同一个 App，在 FlClash 的 VPN 扩展进程内运行，无需另装或启动 EasyTier App。

## 使用

1. 在 FlClash 导入原有代理订阅。
2. 停止 VPN，进入「网络 → EasyTier → EasyTier 配置」。
3. 填写与其他 EasyTier 节点一致的网络名、网络密钥，以及至少一个可到达的节点 URL，例如 `tcp://vpn.example.com:11010`。每行一个节点。
4. 仅填写实际需要访问的内网 IPv4 网段，例如 EasyTier 虚拟网段 `10.144.144.0/24` 和远端节点发布的局域网 `192.168.50.0/24`。默认网段只是示例，必须与实际远端网络一致。每行一个 CIDR，远端节点需要配置对应的子网代理。
5. 开启 EasyTier，保存后在主界面启动 VPN。公网继续使用原订阅的规则，指定内网网段通过内置 EasyTier 转发。

启用期间使用规则模式，切换全局或直连会被拒绝。修改 EasyTier 配置前先停止 VPN，再重新启动。内网 TCP/UDP 经 `127.0.0.1:17890` 的本地 SOCKS5 转发，内核不会为 EasyTier 再创建系统 TUN。17890 不可与 FlClash 的入站端口冲突。

为避免无意扩大分流范围，首版只接受私有 IPv4 和 `100.64.0.0/10` 范围的明确网络 CIDR，拒绝默认路由以及与系统 VPN 的 `172.19.0.0/30` 重叠的网段。未填写的私网继续遵循原订阅规则。填写的网段直接指向本地 SOCKS5，不配置公网代理回退。

启动会等待 EasyTier 分配虚拟 IPv4 并连接至少一个节点，30 秒内未连接则清理本次 VPN 启动。启动失败会显示原生返回的阶段和错误提示，并清除首页计时状态；可据此区分配置、VPN 创建或 EasyTier 启动失败。节点连接成功不代表每个内网服务均已验证连通；可先用实际服务的 TCP/UDP 连接测试。首版不提供 ping、广播发现或其他节点主动连接手机。

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
