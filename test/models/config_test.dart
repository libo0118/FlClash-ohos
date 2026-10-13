import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/material.dart';
import 'package:test/test.dart';

/// Helper to round-trip a model through JSON encode/decode.
T roundTrip<T>(
  Object? Function() toJson,
  T Function(Map<String, Object?> json) fromJson,
) {
  final encoded = jsonEncode(toJson());
  final decoded = jsonDecode(encoded) as Map<String, Object?>;
  return fromJson(decoded);
}

void main() {
  group('GeoResource JSON', () {
    test('exposes lowercase GeoResource values', () {
      expect(GeoResource.MMDB.value, 'mmdb');
      expect(GeoResource.ASN.value, 'asn');
      expect(GeoResource.GEOIP.value, 'geo-ip');
      expect(GeoResource.GEOSITE.value, 'geo-site');
    });

    test('parses current lowercase GeoResource keys from config JSON', () {
      final config = PatchClashConfig.fromJson({
        'geox-url': {
          'mmdb': 'https://example.com/mmdb',
          'asn': 'https://example.com/asn.mmdb',
          'geo-ip': 'https://example.com/geoip.dat',
          'geo-site': 'https://example.com/geosite.dat',
        },
      });

      expect(config.geoXUrl, {
        GeoResource.MMDB: 'https://example.com/mmdb',
        GeoResource.ASN: 'https://example.com/asn.mmdb',
        GeoResource.GEOIP: 'https://example.com/geoip.dat',
        GeoResource.GEOSITE: 'https://example.com/geosite.dat',
      });
    });

    test('parses legacy GeoResource keys from config JSON', () {
      final config = PatchClashConfig.fromJson({
        'geox-url': {
          'geoip': 'https://example.com/legacy-geoip.dat',
          'geosite': 'https://example.com/legacy-geosite.dat',
        },
      });

      expect(config.geoXUrl, {
        GeoResource.GEOIP: 'https://example.com/legacy-geoip.dat',
        GeoResource.GEOSITE: 'https://example.com/legacy-geosite.dat',
      });
    });

    test('GeoXUrl defaults use GeoResource keys', () {
      expect(defaultGeoXUrl.keys, GeoResource.values);
    });

    test('PatchClashConfig serializes geoXUrl map with lowercase keys', () {
      final json = const PatchClashConfig(
        geoXUrl: {GeoResource.GEOIP: 'https://example.com/geoip.dat'},
      ).toJson();

      expect(json['geox-url'], {'geo-ip': 'https://example.com/geoip.dat'});
    });

    test('converts geoXUrl map to raw config map', () {
      const geoXUrl = {
        GeoResource.MMDB: 'https://example.com/mmdb',
        GeoResource.GEOSITE: 'https://example.com/geosite.dat',
      };

      expect(geoXUrl.raw, {
        'mmdb': 'https://example.com/mmdb',
        'geo-site': 'https://example.com/geosite.dat',
      });
    });

    test('PatchClashConfig parses geoXUrl map with GeoResource keys', () {
      final config = PatchClashConfig.fromJson({
        'geox-url': {'mmdb': 'https://example.com/mmdb'},
      });

      expect(config.geoXUrl, {GeoResource.MMDB: 'https://example.com/mmdb'});
    });
  });

  group('AppSettingProps JSON round-trip', () {
    test('default values survive round-trip', () {
      const props = AppSettingProps();
      final restored = roundTrip(
        () => props.toJson(),
        AppSettingProps.fromJson,
      );
      expect(restored.onlyStatisticsProxy, false);
      expect(restored.autoLaunch, false);
      expect(restored.silentLaunch, false);
      expect(restored.autoRun, false);
      expect(restored.openLogs, false);
      expect(restored.closeConnections, true);
      expect(restored.isAnimateToPage, true);
      expect(restored.autoCheckUpdate, true);
      expect(restored.showLabel, false);
      expect(restored.minimizeOnExit, true);
      expect(restored.restoreStrategy, RestoreStrategy.compatible);
      expect(restored.customUserAgent, '');
      expect(restored.testUrl, defaultTestUrl);
    });

    test('custom values survive round-trip', () {
      const props = AppSettingProps(
        locale: 'zh_CN',
        onlyStatisticsProxy: true,
        autoLaunch: true,
        closeConnections: false,
        testUrl: 'https://custom.test',
        customUserAgent: 'CustomUA/1.0',
      );
      final restored = roundTrip(
        () => props.toJson(),
        AppSettingProps.fromJson,
      );
      expect(restored.locale, 'zh_CN');
      expect(restored.onlyStatisticsProxy, true);
      expect(restored.autoLaunch, true);
      expect(restored.closeConnections, false);
      expect(restored.testUrl, 'https://custom.test');
      expect(restored.customUserAgent, 'CustomUA/1.0');
    });

    test('safeFromJson returns default on null', () {
      final result = AppSettingProps.safeFromJson(null);
      expect(result, isA<AppSettingProps>());
      expect(result.onlyStatisticsProxy, false);
    });

    test('safeFromJson returns default on invalid JSON', () {
      final result = AppSettingProps.safeFromJson({'invalid': 'data'});
      expect(result, isA<AppSettingProps>());
    });
  });

  group('EasyTier dashboard layout persistence', () {
    test('new settings place EasyTier last with the current layout version', () {
      const props = AppSettingProps();

      expect(props.dashboardWidgets.last, DashboardWidget.easyTier);
      expect(props.dashboardLayoutVersion, currentDashboardLayoutVersion);
      expect(roundTrip(props.toJson, AppSettingProps.fromJson), props);
    });

    test('legacy config appends once while preserving its custom order', () {
      final config = Config.fromJson({
        'appSettingProps': {
          'locale': 'zh_CN',
          'dashboardWidgets': ['memoryInfo', 'networkSpeed', 'trafficUsage'],
        },
      });
      const expected = [
        DashboardWidget.memoryInfo,
        DashboardWidget.networkSpeed,
        DashboardWidget.trafficUsage,
        DashboardWidget.easyTier,
      ];

      expect(config.appSettingProps.dashboardWidgets, expected);
      expect(config.appSettingProps.locale, 'zh_CN');
      expect(
        config.appSettingProps.dashboardLayoutVersion,
        currentDashboardLayoutVersion,
      );
      final restored = roundTrip(() => config.toJson(), Config.fromJson);
      expect(restored.appSettingProps.dashboardWidgets, expected);
    });

    test('safeFromJson migrates an explicitly empty legacy layout', () {
      final props = AppSettingProps.safeFromJson({'dashboardWidgets': []});

      expect(props.dashboardWidgets, [DashboardWidget.easyTier]);
      expect(props.dashboardLayoutVersion, currentDashboardLayoutVersion);
      expect(roundTrip(props.toJson, AppSettingProps.safeFromJson), props);
    });

    test('legacy layout already containing EasyTier is not duplicated', () {
      final props = AppSettingProps.fromJson({
        'dashboardLayoutVersion': 0,
        'dashboardWidgets': ['easyTier', 'memoryInfo', 'networkSpeed'],
      });

      expect(props.dashboardWidgets, [
        DashboardWidget.easyTier,
        DashboardWidget.memoryInfo,
        DashboardWidget.networkSpeed,
      ]);
      expect(props.dashboardLayoutVersion, currentDashboardLayoutVersion);
    });

    test('malformed layout markers preserve other settings while migrating', () {
      for (final marker in ['broken', true, <String, Object?>{}, <Object?>[], double.nan, double.infinity, double.negativeInfinity]) {
        final json = <String, Object?>{
          'dashboardLayoutVersion': marker,
          'dashboardWidgets': ['networkSpeed', 'memoryInfo'],
          'locale': 'ja',
          'autoLaunch': true,
          'closeConnections': false,
        };
        for (final props in [AppSettingProps.fromJson(json), AppSettingProps.safeFromJson(json)]) {
          expect(props.dashboardWidgets, [DashboardWidget.networkSpeed, DashboardWidget.memoryInfo, DashboardWidget.easyTier]);
          expect(props.locale, 'ja');
          expect(props.autoLaunch, true);
          expect(props.closeConnections, false);
          expect(props.dashboardLayoutVersion, currentDashboardLayoutVersion);
        }
      }
    });

    test('a future layout version preserves custom order and removed tiles', () {
      final props = AppSettingProps.fromJson({
        'dashboardLayoutVersion': currentDashboardLayoutVersion + 1,
        'dashboardWidgets': ['memoryInfo', 'trafficUsage', 'networkSpeed'],
      });

      expect(props.dashboardWidgets, [DashboardWidget.memoryInfo, DashboardWidget.trafficUsage, DashboardWidget.networkSpeed]);
      expect(props.dashboardLayoutVersion, currentDashboardLayoutVersion + 1);
      expect(roundTrip(props.toJson, AppSettingProps.fromJson), props);
    });

    test('the grid save mapping preserves a moved tile on reload', () {
      final moved = [
        DashboardWidget.easyTier.widget,
        DashboardWidget.intranetIp.widget,
        DashboardWidget.networkSpeed.widget,
      ].map(DashboardWidget.getDashboardWidget).toList();
      final config = Config(
        themeProps: const ThemeProps(),
        appSettingProps: const AppSettingProps().copyWith(
          dashboardWidgets: moved,
        ),
      );

      final restored = roundTrip(() => config.toJson(), Config.fromJson);
      expect(restored.appSettingProps.dashboardWidgets, moved);
      expect(restored.appSettingProps.dashboardWidgets.first,
          DashboardWidget.easyTier);
    });

    test('a removed tile stays removed after saving a migrated config', () {
      final migrated = Config.fromJson({
        'appSettingProps': {
          'dashboardWidgets': ['networkSpeed', 'intranetIp'],
        },
      });
      final config = migrated.copyWith(
        appSettingProps: migrated.appSettingProps.copyWith(
          dashboardWidgets: [
            DashboardWidget.networkSpeed,
            DashboardWidget.intranetIp,
          ],
        ),
      );

      final restored = roundTrip(() => config.toJson(), Config.fromJson);
      expect(restored.appSettingProps.dashboardWidgets, [
        DashboardWidget.networkSpeed,
        DashboardWidget.intranetIp,
      ]);
      expect(
        roundTrip(restored.appSettingProps.toJson, AppSettingProps.safeFromJson)
            .dashboardWidgets,
        restored.appSettingProps.dashboardWidgets,
      );
    });

    test('a marked empty layout remains empty', () {
      final props = AppSettingProps.fromJson({
        'dashboardLayoutVersion': currentDashboardLayoutVersion,
        'dashboardWidgets': [],
      });

      expect(props.dashboardWidgets, isEmpty);
      expect(roundTrip(props.toJson, AppSettingProps.fromJson).dashboardWidgets, isEmpty);
    });

    test('the editable entry is available only on HarmonyOS', () {
      final entry = DashboardWidget.easyTier;

      expect(entry.platforms, [SupportPlatform.ohos]);
      expect(entry.widget.crossAxisCellCount, 8);
      expect(DashboardWidget.getDashboardWidget(entry.widget), entry);
      for (final platform in SupportPlatform.values) {
        final visible = defaultDashboardWidgets
            .where((item) => item.platforms.contains(platform));
        expect(visible.contains(entry), platform == SupportPlatform.ohos);
      }
    });
  });

  group('WindowProps JSON round-trip', () {
    test('default values', () {
      const props = WindowProps();
      expect(props.width, 0);
      expect(props.height, 0);
      expect(props.top, null);
      expect(props.left, null);
    });

    test('fromJson handles null', () {
      final props = WindowProps.fromJson(null);
      expect(props.width, 0);
    });

    test('size extension defaults to 680x580 when empty', () {
      const props = WindowProps();
      expect(props.size.width, 680);
      expect(props.size.height, 580);
    });

    test('size extension uses actual values', () {
      const props = WindowProps(width: 800, height: 600);
      expect(props.size.width, 800);
      expect(props.size.height, 600);
    });

    test('round-trip with values', () {
      const props = WindowProps(width: 1024, height: 768, top: 100, left: 200);
      final restored = roundTrip(() => props.toJson(), WindowProps.fromJson);
      expect(restored.width, 1024);
      expect(restored.height, 768);
      expect(restored.top, 100);
      expect(restored.left, 200);
    });
  });

  group('VpnProps JSON round-trip', () {
    test('default values', () {
      const props = VpnProps();
      expect(props.enable, true);
      expect(props.systemProxy, true);
      expect(props.ipv6, false);
      expect(props.allowBypass, true);
      expect(props.dnsHijacking, false);
      expect(props.accessControlProps.enable, false);
    });

    test('fromJson handles null', () {
      final props = VpnProps.fromJson(null);
      expect(props.enable, true);
    });

    test('round-trip with custom values', () {
      const accessControl = AccessControlProps(
        enable: true,
        mode: AccessControlMode.acceptSelected,
      );
      const props = VpnProps(
        enable: false,
        systemProxy: false,
        ipv6: true,
        accessControlProps: accessControl,
      );
      final restored = roundTrip(() => props.toJson(), VpnProps.fromJson);
      expect(restored.enable, false);
      expect(restored.systemProxy, false);
      expect(restored.ipv6, true);
    });
  });

  group('NetworkProps JSON round-trip', () {
    test('default values', () {
      const props = NetworkProps();
      expect(props.systemProxy, true);
      expect(props.bypassDomain, defaultBypassDomain);
      expect(props.routeMode, RouteMode.config);
      expect(props.autoSetSystemDns, true);
      expect(props.appendSystemDns, false);
    });

    test('round-trip with custom values', () {
      const props = NetworkProps(
        systemProxy: false,
        bypassDomain: ['example.com'],
        routeMode: RouteMode.bypassPrivate,
      );
      final restored = roundTrip(() => props.toJson(), NetworkProps.fromJson);
      expect(restored.systemProxy, false);
      expect(restored.bypassDomain, ['example.com']);
      expect(restored.routeMode, RouteMode.bypassPrivate);
    });
  });

  group('PatchClashConfig JSON round-trip', () {
    test('defaults match Clash patch defaults', () {
      const config = PatchClashConfig();

      expect(config.mixedPort, defaultMixedPort);
      expect(config.allowLan, false);
      expect(config.mode, Mode.rule);
      expect(config.externalController, ExternalControllerStatus.close);
      expect(config.geodataLoader, GeodataLoader.memconservative);
    });

    test('custom values survive round-trip', () {
      const config = PatchClashConfig(
        mixedPort: 7890,
        allowLan: true,
        mode: Mode.rule,
        logLevel: LogLevel.debug,
        externalController: ExternalControllerStatus.open,
        geodataLoader: GeodataLoader.memconservative,
      );

      final restored = roundTrip(
        () => config.toJson(),
        PatchClashConfig.fromJson,
      );

      expect(restored.mixedPort, 7890);
      expect(restored.allowLan, true);
      expect(restored.mode, Mode.rule);
      expect(restored.logLevel, LogLevel.debug);
      expect(restored.externalController, ExternalControllerStatus.open);
      expect(restored.geodataLoader, GeodataLoader.memconservative);
    });
  });

  group('ProxiesStyleProps JSON round-trip', () {
    test('default values', () {
      const props = ProxiesStyleProps();
      expect(props.type, ProxiesType.tab);
      expect(props.sortType, ProxiesSortType.none);
      expect(props.layout, ProxiesLayout.standard);
    });

    test('round-trip with custom values', () {
      const props = ProxiesStyleProps(
        type: ProxiesType.list,
        sortType: ProxiesSortType.delay,
      );
      final restored = roundTrip(
        () => props.toJson(),
        ProxiesStyleProps.fromJson,
      );
      expect(restored.type, ProxiesType.list);
      expect(restored.sortType, ProxiesSortType.delay);
    });
  });

  group('ThemeProps JSON round-trip', () {
    test('default values', () {
      const props = ThemeProps();
      expect(props.primaryColor, null);
      expect(props.primaryColors, defaultPrimaryColors);
      expect(props.themeMode, ThemeMode.dark);
      expect(props.pureBlack, false);
      expect(props.textScale.scale, 1.0);
    });

    test('safeFromJson returns default on null', () {
      final result = ThemeProps.safeFromJson(null);
      expect(result.themeMode, ThemeMode.dark);
    });

    test('round-trip with custom values', () {
      const props = ThemeProps(
        primaryColor: 0xFF123456,
        themeMode: ThemeMode.light,
        pureBlack: true,
        textScale: TextScale(enable: true, scale: 1.5),
      );
      final restored = roundTrip(() => props.toJson(), ThemeProps.fromJson);
      expect(restored.primaryColor, 0xFF123456);
      expect(restored.themeMode, ThemeMode.light);
      expect(restored.pureBlack, true);
      expect(restored.textScale.scale, 1.5);
    });
  });

  group('AccessControlProps', () {
    test('currentList returns acceptList in acceptSelected mode', () {
      const props = AccessControlProps(
        enable: true,
        mode: AccessControlMode.acceptSelected,
        acceptList: ['app1', 'app2'],
        rejectList: ['app3'],
      );
      expect(props.currentList, ['app1', 'app2']);
    });

    test('currentList returns rejectList in rejectSelected mode', () {
      const props = AccessControlProps(
        enable: true,
        mode: AccessControlMode.rejectSelected,
        acceptList: ['app1'],
        rejectList: ['app3', 'app4'],
      );
      expect(props.currentList, ['app3', 'app4']);
    });
  });

  group('Config composite serialization', () {
    test('default Config round-trip', () {
      const config = Config(themeProps: ThemeProps());
      final restored = roundTrip(() => config.toJson(), Config.fromJson);
      expect(restored.currentProfileId, null);
      expect(restored.overrideDns, false);
      expect(restored.networkProps.systemProxy, true);
      expect(restored.vpnProps.enable, true);
      expect(restored.hotKeyActions, isEmpty);
    });

    test('realFromJson handles null', () {
      final result = Config.realFromJson(null);
      expect(result.appSettingProps.onlyStatisticsProxy, false);
    });

    test('full config round-trip', () {
      const config = Config(
        currentProfileId: 42,
        overrideDns: true,
        hotKeyActions: [],
        appSettingProps: AppSettingProps(locale: 'en', autoLaunch: true),
        networkProps: NetworkProps(systemProxy: false),
        vpnProps: VpnProps(enable: false),
        themeProps: ThemeProps(
          primaryColor: 0xFF00FF00,
          themeMode: ThemeMode.system,
        ),
        windowProps: WindowProps(width: 1280, height: 720),
      );
      final restored = roundTrip(() => config.toJson(), Config.fromJson);
      expect(restored.currentProfileId, 42);
      expect(restored.overrideDns, true);
      expect(restored.appSettingProps.locale, 'en');
      expect(restored.appSettingProps.autoLaunch, true);
      expect(restored.networkProps.systemProxy, false);
      expect(restored.vpnProps.enable, false);
      expect(restored.windowProps.width, 1280);
      expect(restored.windowProps.height, 720);
    });
  });
}
