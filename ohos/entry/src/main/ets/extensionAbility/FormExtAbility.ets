import { FormExtensionAbility, formBindingData, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import VpnCardManager from '../managers/VpnCardManager';

export default class FormExtAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const id = want.parameters?.['ohos.extra.param.key.form_identity'] as string
    return new VpnCardManager(this.context).register(id ?? '')
  }
  onUpdateForm(formId: string): void {
    const manager = new VpnCardManager(this.context)
    formProvider.updateForm(formId, manager.register(formId)).catch(() => {})
  }
  onCastToNormalForm(formId: string): void {
    new VpnCardManager(this.context).register(formId)
  }
  onRemoveForm(formId: string): void {
    new VpnCardManager(this.context).remove(formId)
  }
}
