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

  private busy(): boolean {
    return this.vpnStatus === 'starting' || this.vpnStatus === 'stopping'
  }
  private statusText(): Resource {
    if (this.vpnStatus === 'connected') return $r('app.string.widget_connected')
    if (this.vpnStatus === 'starting') return $r('app.string.widget_starting')
    if (this.vpnStatus === 'stopping') return $r('app.string.widget_stopping')
    if (this.vpnStatus === 'failed') return $r('app.string.widget_failed')
    if (!this.controlReady) return $r('app.string.widget_open_required')
    return $r('app.string.widget_disconnected')
  }
  private buttonText(): Resource {
    if (this.busy()) return this.statusText()
    if (!this.controlReady) return $r('app.string.widget_open_control')
    return this.vpnStatus === 'connected' ? $r('app.string.widget_stop') : $r('app.string.widget_start')
  }
  private open(enable?: boolean): void {
    postCardAction(this, {
      action: 'router', abilityName: 'EntryAbility',
      params: { formId: this.formId, token: this.cardToken, vpnCardEnable: enable ?? '' },
    })
  }

  build() {
    Column({ space: 7 }) {
      Row() {
        Text('FlClash').fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font')).layoutWeight(1)
        Text($r('app.string.widget_open')).fontSize(11)
          .fontColor($r('sys.color.font_secondary')).onClick(() => this.open())
      }.width('100%')
      Row({ space: 6 }) {
        Text(this.statusText()).fontSize(12).fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font')).layoutWeight(1).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.easyTierEnabled && this.vpnStatus === 'connected') {
          Text('EasyTier').fontSize(10).fontColor($r('sys.color.font_secondary'))
        }
      }.width('100%')
      Row({ space: 8 }) {
        Text(this.profileName).fontSize(11).fontColor($r('sys.color.font_secondary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        Button(this.buttonText(), { type: ButtonType.Capsule }).fontSize(12).height(30)
          .padding({ left: 12, right: 12 }).enabled(!this.busy())
          .onClick(() => {
            const enable = this.vpnStatus !== 'connected'
            if (!this.controlReady) this.open(enable)
            else postCardAction(this, {
              action: 'call', abilityName: 'EntryAbility',
              params: { method: 'vpnCardToggle', formId: this.formId, token: this.cardToken, enable },
            })
          })
      }.width('100%')
    }
    .padding(12).width('100%').height('100%').justifyContent(FlexAlign.Center)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .onAppear(() => {
      postCardAction(this, {
        action: 'call', abilityName: 'EntryAbility',
        params: { method: 'vpnCardRefresh', formId: this.formId, token: this.cardToken },
      })
    })
  }
}
