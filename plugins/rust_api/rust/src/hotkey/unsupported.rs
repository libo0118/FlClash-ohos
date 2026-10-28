use crate::api::hotkey::{HotKeyFailure, HotKeySpec};
use crate::frb_generated::StreamSink;
use flutter_rust_bridge::for_generated::SseCodec;

// Mobile entry points keep one set of bindings for every platform.
const UNSUPPORTED: &str = "Global hotkeys are not available on this platform";

#[cfg_attr(test, allow(dead_code))]
pub fn listen(_sink: StreamSink<u32, SseCodec>) -> Result<(), String> {
    Err(UNSUPPORTED.into())
}

pub fn set_hot_keys(_specs: Vec<HotKeySpec>) -> Result<Vec<HotKeyFailure>, String> {
    Err(UNSUPPORTED.into())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::hotkey::HotKeyModifier;

    #[test]
    fn rejects_global_hotkeys_without_registering_them() {
        let specs = vec![HotKeySpec {
            id: 7,
            key: 0x0007_0004,
            modifiers: vec![HotKeyModifier::Control],
        }];
        for specs in [Vec::new(), specs] {
            assert_eq!(
                set_hot_keys(specs).unwrap_err(),
                "Global hotkeys are not available on this platform"
            );
        }
    }
}
