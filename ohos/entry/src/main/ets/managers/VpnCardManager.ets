import { common } from '@kit.AbilityKit'
import { formBindingData, formProvider } from '@kit.FormKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { rpc } from '@kit.IPCKit'

interface VpnCardRegistration { id: string; token: string }
interface VpnCardSummary { profileName: string; easyTier: boolean; ready: boolean; easyTierStatus?: string; vpnStatus?: string }
export interface VpnCardRequest { formId: string; token: string; enable?: boolean }
interface VpnCardData {
  formId: string
  cardToken: string
  vpnStatus: string
  controlReady: boolean
  profileName: string
  easyTierEnabled: boolean
  easyTierStatus: string
}

export class VpnCardReply implements rpc.Parcelable {
  marshalling(sequence: rpc.MessageSequence): boolean {
    sequence.writeString('received')
    return true
  }
  unmarshalling(sequence: rpc.MessageSequence): boolean {
    sequence.readString()
    return true
  }
}

// Persist card authorization and a non-sensitive summary, never VPN credentials.
export default class VpnCardManager {
  private context: common.Context
  constructor(context: common.Context) { this.context = context }

  private read(name: string): string {
    try { return fs.readTextSync(`${this.context.filesDir}/${name}.json`) } catch (_) { return '' }
  }

  private write(name: string, value: string): void {
    const target = `${this.context.filesDir}/${name}.json`
    const temporary = `${target}.tmp`
    const file = fs.openSync(temporary, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC)
    try { fs.writeSync(file.fd, value) } finally { fs.closeSync(file) }
    fs.renameSync(temporary, target)
  }

  private registrations(): VpnCardRegistration[] {
    try {
      const rows = JSON.parse(this.read('vpn-card-ids')) as VpnCardRegistration[]
      return rows.filter((row: VpnCardRegistration) => /^\d+$/.test(row.id) && typeof row.token === 'string')
    } catch (_) { return [] }
  }

  private summary(): VpnCardSummary {
    try {
      const value = JSON.parse(this.read('vpn-card-summary')) as VpnCardSummary
      if (typeof value.profileName !== 'string' || typeof value.easyTier !== 'boolean' || typeof value.ready !== 'boolean') {
        throw new Error('Invalid card summary')
      }
      return value
    } catch (_) {
      return { profileName: '', easyTier: false, ready: false }
    }
  }

  register(id: string): formBindingData.FormBindingData {
    const rows = this.registrations()
    let registration = rows.find((row: VpnCardRegistration) => row.id === id)
    if (!registration && /^\d+$/.test(id)) {
      registration = { id, token: util.generateRandomUUID(true) }
      rows.push(registration)
      this.write('vpn-card-ids', JSON.stringify(rows))
    }
    return this.data(registration ?? { id: '', token: '' }, 'unknown', false)
  }

  remove(id: string): void {
    this.write('vpn-card-ids', JSON.stringify(this.registrations().filter((row: VpnCardRegistration) => row.id !== id)))
  }

  accepts(request: VpnCardRequest): boolean {
    return typeof request.formId === 'string' && typeof request.token === 'string' &&
      this.registrations().some((row: VpnCardRegistration) => row.id === request.formId && row.token === request.token)
  }

  updateSummary(profileName: string, easyTier: boolean): void {
    try {
      const summary = this.summary()
      summary.profileName = profileName.slice(0, 64)
      summary.easyTier = easyTier
      if (!easyTier) summary.easyTierStatus = 'disabled'
      else if (!summary.easyTierStatus || summary.easyTierStatus === 'disabled') summary.easyTierStatus = 'unknown'
      this.write('vpn-card-summary', JSON.stringify(summary))
    } catch (_) {}
  }

  setReady(ready: boolean): void {
    try {
      const summary = this.summary()
      summary.ready = ready
      this.write('vpn-card-summary', JSON.stringify(summary))
    } catch (_) {}
  }

  setEasyTierStatus(status: string): void {
    if (!['disabled', 'starting', 'ready', 'unavailable', 'stopped'].includes(status)) return
    const summary = this.summary()
    summary.easyTierStatus = summary.easyTier ? status : 'disabled'
    this.write('vpn-card-summary', JSON.stringify(summary))
    this.publish(summary.vpnStatus ?? 'unknown')
  }

  private data(registration: VpnCardRegistration, status: string, ready: boolean = this.summary().ready): formBindingData.FormBindingData {
    const summary = this.summary()
    const data: VpnCardData = {
      formId: registration.id, cardToken: registration.token,
      vpnStatus: status, controlReady: ready,
      profileName: summary.profileName, easyTierEnabled: summary.easyTier,
      easyTierStatus: summary.easyTier ? summary.easyTierStatus ?? 'unknown' : 'disabled',
    }
    return formBindingData.createFormBindingData(data)
  }

  publish(status: string, ready?: boolean): void {
    try {
      const summary = this.summary()
      const changed = summary.vpnStatus !== status
      summary.vpnStatus = status
      if (summary.easyTier && status === 'stopped') summary.easyTierStatus = 'stopped'
      if (summary.easyTier && status === 'starting' && changed) summary.easyTierStatus = 'starting'
      if (summary.easyTier && status === 'failed') summary.easyTierStatus = 'unavailable'
      this.write('vpn-card-summary', JSON.stringify(summary))
    } catch (_) {}
    for (const registration of this.registrations()) {
      try { formProvider.updateForm(registration.id, this.data(registration, status, ready)).catch(() => {}) } catch (_) {}
    }
  }
}
