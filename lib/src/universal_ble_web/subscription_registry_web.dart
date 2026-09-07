import 'dart:js_interop';
import 'dart:js_interop_unsafe';

const _property = '__universalBleSubscriptions';

Set<String> getWebSubscriptions() {
  final stored = globalContext.getProperty<JSAny?>(_property.toJS);
  if (stored == null || stored.isUndefinedOrNull) return {};
  return (stored as JSArray<JSString>)
      .toDart
      .map((value) => value.toDart)
      .toSet();
}

void setWebSubscriptions(Set<String> subscriptions) {
  globalContext.setProperty(
    _property.toJS,
    subscriptions.map((value) => value.toJS).toList().toJS,
  );
}
