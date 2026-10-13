# EasyTier dashboard status

The homepage status card follows the existing FlClash Material theme and CommonCard surface, 14 px corner radius and 16 px content spacing. It adds no new colors, fonts, animation or dashboard layout preference.

Within three seconds, users can read EasyTier runtime status, their virtual IPv4 address and the discovered node count. Each node shows its selectable IPv4 and hostname, direct or relay connection type, and measured direct-link delay. The count describes discovered nodes, not an immediate online guarantee. Relay delay is unavailable. Starting, stopped, unavailable and stale states show clear text; expired data never presents a live delay.

The entry sits above the existing editable grid in the same scroll view on HarmonyOS. Disabled EasyTier uses a compact setup tile; enabled EasyTier shows the status card with a settings button. Both lead to the same dedicated settings page. Its EasyTier IPv6 switch defaults off and is independent of FlClash IPv6; changes require stopping and restarting the VPN. Existing persisted grid items remain intact. Three nodes are initially visible, with one native text button to expand or collapse the list. Rows use natural height and wrap on narrow screens and with enlarged fonts. IP addresses and machine names can be selected and copied.

Acceptance uses widget checks for state, disclosure and overflow, plus real Flutter PNG renders in dark/light phone, wide and 320 px enlarged-text layouts. Runtime system fonts remain unchanged; the CI-only CJK font supports readable screenshot evidence.
