library subfay;

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Subfay Flutter SDK
class Subfay {
  static Subfay? _instance;
  static Subfay get instance => _instance ??= Subfay._();

  Subfay._();

  Configuration? _configuration;
  Customer? _currentCustomer;
  final StreamController<List<String>> _entitlementsController =
      StreamController<List<String>>.broadcast();

  /// Stream of entitlements
  Stream<List<String>> get entitlementsStream => _entitlementsController.stream;

  /// Configure the SDK
  Future<void> configure({
    required String apiKey,
    Environment environment = Environment.production,
    ConfigOptions options = const ConfigOptions(),
  }) async {
    _configuration = Configuration(
      apiKey: apiKey,
      environment: environment,
      options: options,
    );

    _log('SDK configured for $environment', LogLevel.info);
  }

  /// Identify the current user
  Future<Customer> identify({required String externalUserId}) async {
    _ensureConfigured();

    _log('Identifying user: $externalUserId', LogLevel.debug);

    final customer = Customer(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      externalId: externalUserId,
    );

    _currentCustomer = customer;
    await _saveCustomer(customer);

    // Fetch entitlements after identification
    await syncEntitlements();

    return customer;
  }

  /// Get current customer
  Future<Customer?> getCurrentCustomer() async {
    return _currentCustomer ?? await _loadCustomer();
  }

  /// Logout current user
  Future<void> logout() async {
    _currentCustomer = null;
    await _clearAll();
    _entitlementsController.add([]);
    _log('User logged out', LogLevel.info);
  }

  /// Get all entitlements
  Future<List<String>> getEntitlements() async {
    _ensureConfigured();

    final customer = await getCurrentCustomer();
    if (customer == null) {
      throw SubfayException.authenticationError(
        'No customer identified. Call identify() first.',
      );
    }

    // Try cache first
    final cached = await _loadEntitlements();
    if (cached != null && !await _isCacheExpired()) {
      _log('Entitlements loaded from cache', LogLevel.debug);
      return cached;
    }

    // Fetch from server
    return await _fetchEntitlementsFromServer(customer);
  }

  /// Check if user has entitlement
  Future<bool> hasEntitlement(String key) async {
    final entitlements = await getEntitlements();
    return entitlements.contains(key);
  }

  /// Manually sync entitlements
  Future<List<String>> syncEntitlements() async {
    _ensureConfigured();

    final customer = await getCurrentCustomer();
    if (customer == null) {
      throw SubfayException.authenticationError('No customer identified');
    }

    return await _fetchEntitlementsFromServer(customer);
  }

  // Private methods
  void _ensureConfigured() {
    if (_configuration == null) {
      throw SubfayException.invalidConfiguration(
        'SDK not configured. Call Subfay.instance.configure() first.',
      );
    }
  }

  Future<List<String>> _fetchEntitlementsFromServer(Customer customer) async {
    final config = _configuration!;
    final baseURL = config.options.baseURL ?? config.environment.baseURL;
    final url = Uri.parse('$baseURL/entitlements/${customer.externalId}');

    _log('Fetching entitlements from server', LogLevel.debug);

    try {
      final response = await http.get(
        url,
        headers: {
          'X-API-Key': config.apiKey,
          'Content-Type': 'application/json',
          'User-Agent': 'Subfay/Flutter/1.0.0',
        },
      ).timeout(Duration(milliseconds: config.options.timeout));

      if (response.statusCode != 200) {
        throw SubfayException.serverError(
          response.statusCode,
          'Server error: ${response.body}',
        );
      }

      final json = jsonDecode(response.body);
      final entitlements =
          List<String>.from(json['data']['entitlements'] as List);

      // Update cache
      await _saveEntitlements(entitlements);

      // Notify listeners
      _entitlementsController.add(entitlements);

      _log('Entitlements updated: $entitlements', LogLevel.info);

      return entitlements;
    } catch (e) {
      throw SubfayException.networkError('Network error: $e');
    }
  }

  // Cache management
  Future<void> _saveCustomer(Customer customer) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('subfay_customer', jsonEncode(customer.toJson()));
  }

  Future<Customer?> _loadCustomer() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('subfay_customer');
    if (data == null) return null;
    return Customer.fromJson(jsonDecode(data));
  }

  Future<void> _saveEntitlements(List<String> entitlements) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('subfay_entitlements', jsonEncode(entitlements));
    await prefs.setInt(
      'subfay_last_sync',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<List<String>?> _loadEntitlements() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('subfay_entitlements');
    if (data == null) return null;
    return List<String>.from(jsonDecode(data) as List);
  }

  Future<bool> _isCacheExpired() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getInt('subfay_last_sync');
    if (lastSync == null) return true;

    final elapsed = DateTime.now().millisecondsSinceEpoch - lastSync;
    return elapsed > _configuration!.options.cacheExpiration;
  }

  Future<void> _clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('subfay_customer');
    await prefs.remove('subfay_entitlements');
    await prefs.remove('subfay_last_sync');
  }

  void _log(String message, LogLevel level) {
    if (_configuration == null) return;
    if (level.index < _configuration!.options.logLevel.index) return;

    final prefix = {
      LogLevel.verbose: '💬',
      LogLevel.debug: '🔍',
      LogLevel.info: 'ℹ️',
      LogLevel.warning: '⚠️',
      LogLevel.error: '❌',
      LogLevel.none: '',
    }[level];

    print('$prefix [Subfay] $message');
  }
}

// Models
class Customer {
  final String id;
  final String externalId;
  final String? email;
  final String? displayName;

  Customer({
    required this.id,
    required this.externalId,
    this.email,
    this.displayName,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'externalId': externalId,
        'email': email,
        'displayName': displayName,
      };

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
        id: json['id'],
        externalId: json['externalId'],
        email: json['email'],
        displayName: json['displayName'],
      );
}

class Configuration {
  final String apiKey;
  final Environment environment;
  final ConfigOptions options;

  Configuration({
    required this.apiKey,
    required this.environment,
    required this.options,
  });
}

class ConfigOptions {
  final int cacheExpiration;
  final bool automaticSync;
  final LogLevel logLevel;
  final int timeout;
  final String? baseURL;

  const ConfigOptions({
    this.cacheExpiration = 3600000, // 1 hour
    this.automaticSync = true,
    this.logLevel = LogLevel.info,
    this.timeout = 30000,
    this.baseURL,
  });
}

enum Environment {
  production,
  sandbox;

  String get baseURL {
    switch (this) {
      case Environment.production:
        return 'https://api.subfay.com';
      case Environment.sandbox:
        return 'https://sandbox-api.subfay.com';
    }
  }
}

enum LogLevel {
  verbose,
  debug,
  info,
  warning,
  error,
  none,
}

// Exceptions
class SubfayException implements Exception {
  final String message;
  final SubfayExceptionType type;
  final int? statusCode;

  SubfayException._(this.message, this.type, [this.statusCode]);

  factory SubfayException.networkError(String message) =>
      SubfayException._(message, SubfayExceptionType.networkError);

  factory SubfayException.authenticationError(String message) =>
      SubfayException._(message, SubfayExceptionType.authenticationError);

  factory SubfayException.invalidConfiguration(String message) =>
      SubfayException._(message, SubfayExceptionType.invalidConfiguration);

  factory SubfayException.serverError(int statusCode, String message) =>
      SubfayException._(message, SubfayExceptionType.serverError, statusCode);

  factory SubfayException.cacheError(String message) =>
      SubfayException._(message, SubfayExceptionType.cacheError);

  @override
  String toString() => 'SubfayException: $message';
}

enum SubfayExceptionType {
  networkError,
  authenticationError,
  invalidConfiguration,
  serverError,
  cacheError,
}
