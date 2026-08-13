import 'package:subfay/subfay.dart';

/// Minimal usage of the Subfay Flutter SDK.
Future<void> main() async {
  await Subfay.instance.configure(
    apiKey: 'pk_live_xxxxx',
    environment: Environment.production,
  );

  await Subfay.instance.identify(externalUserId: 'user_123');

  final hasPremium = await Subfay.instance.hasEntitlement('premium');
  print('premium: $hasPremium');

  Subfay.instance.entitlementsStream.listen((entitlements) {
    print('active entitlements: $entitlements');
  });
}
