let storage = new LocalStorage()

@Entry(storage)
@Component
struct WidgetCard {
  @LocalStorageProp('formId') formId: string = ''
  @LocalStorageProp('cardToken') cardToken: string = ''
  @LocalStorageProp('vpnStatus') vpnStatus: string = 'unknown'
  @LocalStorageProp('controlReady') controlReady: boolean = false
  @LocalStorageProp('profileName') profileName: string = ''
  @LocalStorageProp('easyTierEnabled') easyTierEnabled: boolean = false
  @LocalStorageProp('easyTierStatus') easyTierStatus: string = 'unknown'

  private busy(): boolean {
    return this.vpnStatus === 'starting' || this.vpnStatus === 'stopping'
  }
  private statusText(): Resource {
    if (this.vpnStatus === 'connected') return $r('app.string.widget_connected')
    if (this.vpnStatus === 'starting') return $r('app.string.widget_starting')
    if (this.vpnStatus === 'stopping') return $r('app.string.widget_stopping')
    if (this.vpnStatus === 'failed') return $r('app.string.widget_failed')
    if (this.vpnStatus === 'unknown') return $r('app.string.widget_unknown')
    if (!this.controlReady) return $r('app.string.widget_open_required')
    return $r('app.string.widget_disconnected')
  }
  private buttonText(): Resource {
    if (this.busy()) return this.statusText()
    if (!this.controlReady || this.vpnStatus === 'unknown') return $r('app.string.widget_open_control')
    return this.vpnStatus === 'connected' ? $r('app.string.widget_stop') : $r('app.string.widget_start')
  }
  private easyTierStatusText(): Resource {
    if (this.easyTierStatus === 'ready') return $r('app.string.widget_easytier_ready')
    if (this.easyTierStatus === 'starting') return $r('app.string.widget_easytier_starting')
    if (this.easyTierStatus === 'stopped') return $r('app.string.widget_easytier_stopped')
    if (this.easyTierStatus === 'unavailable' || this.easyTierStatus === 'stale') {
      return $r('app.string.widget_easytier_unavailable')
    }
    return $r('app.string.widget_easytier_unknown')
  }
  private open(enable?: boolean): void {
    postCardAction(this, {
      action: 'router', abilityName: 'EntryAbility',
      params: { formId: this.formId, token: this.cardToken, vpnCardEnable: enable ?? '' },
    })
  }

  build() {
    Row({ space: 8 }) {
      Column({ space: 2 }) {
        Text('FlClash').fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font')).maxLines(1)
        Text(this.statusText()).fontSize(12).fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font')).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.profileName)
          .fontSize(11).fontColor($r('sys.color.font_secondary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.easyTierEnabled) {
          Row({ space: 4 }) {
            Text('EasyTier').fontSize(10).fontColor($r('sys.color.font_secondary'))
            Text(this.easyTierStatusText()).fontSize(10)
              .fontColor($r('sys.color.font_secondary'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Column({ space: 5 }) {
        Button(this.buttonText(), { type: ButtonType.Capsule }).fontSize(11).height(28).width(72)
          .padding({ left: 8, right: 8 }).enabled(!this.busy())
          .onClick(() => {
            const enable = this.vpnStatus !== 'connected'
            if (!this.controlReady || this.vpnStatus === 'unknown') this.open(enable)
            else postCardAction(this, {
              action: 'call', abilityName: 'EntryAbility',
              params: { method: 'vpnCardToggle', formId: this.formId, token: this.cardToken, enable },
            })
          })
        Text($r('app.string.widget_open')).fontSize(10)
          .fontColor($r('sys.color.font_secondary')).onClick(() => this.open())
      }
    }
    .padding(12).width('100%').height('100%').borderRadius(20)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .onAppear(() => {
      postCardAction(this, {
        action: 'call', abilityName: 'EntryAbility',
        params: { method: 'vpnCardRefresh', formId: this.formId, token: this.cardToken },
      })
    })
  }
}
