# Subfay Flutter SDK

Entitlements, customers and subscription state for Flutter apps, powered by
[Subfay](https://subfay.com).

## Install

```yaml
dependencies:
  subfay: ^1.0.0
```

## Usage

```dart
import 'package:subfay/subfay.dart';

// Configure once at startup with your publishable key
await Subfay.instance.configure(
  apiKey: 'pk_live_xxxxx',
  environment: Environment.production,
);

// Identify the signed-in user
await Subfay.instance.identify(externalUserId: 'user_123');

// Gate a feature on an entitlement
if (await Subfay.instance.hasEntitlement('premium')) {
  // unlock premium
}

// React to entitlement changes
Subfay.instance.entitlementsStream.listen((entitlements) {
  print('Active entitlements: $entitlements');
});
```

## Purchases

This SDK does not run store transactions. Take the purchase with your store
plugin (e.g. `in_app_purchase`), send the receipt to **your** server, and
validate it there with your secret key via `POST /iap/validate`. Once Subfay
records the entitlement, it shows up here.

## Links

- 📖 Docs: https://docs.subfay.com
- 🐛 Issues: https://github.com/subfay/subfay-flutter/issues

## License

MIT — see [LICENSE](LICENSE).
