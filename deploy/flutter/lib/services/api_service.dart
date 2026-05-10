import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ApiService {
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const String _rawBaseUrl = String.fromEnvironment(
    'PHAROS_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );
  static const Duration _requestTimeout = Duration(seconds: 25);

  late final Uri _baseUri = _normalizeBaseUri(Uri.parse(_rawBaseUrl));

  Uri _normalizeBaseUri(Uri uri) {
    final String host = uri.host.toLowerCase();
    final bool localHost = host == '10.0.2.2' || host == '127.0.0.1' || host == 'localhost';
    final String scheme = localHost && uri.scheme == 'https'
        ? 'http'
        : (uri.scheme.isEmpty ? 'http' : uri.scheme);
    return uri.replace(scheme: scheme, path: '', query: null, fragment: null);
  }

  Uri _buildUri(String path, [Map<String, String>? queryParams]) {
    final String cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return Uri(
      scheme: _baseUri.scheme,
      host: _baseUri.host,
      port: _baseUri.hasPort ? _baseUri.port : null,
      path: '/$cleanPath',
      queryParameters: queryParams == null || queryParams.isEmpty ? null : queryParams,
    );
  }

  Exception _networkException(Object error, Uri uri) {
    final bool emulatorLoopback = uri.host == '10.0.2.2';
    final String emulatorHint = emulatorLoopback
        ? ' If you are on a physical Android device, set PHAROS_API_BASE_URL to your PC LAN IP '
          '(for example http://192.168.1.10:8000).'
        : '';
    if (error is TimeoutException) {
      return Exception(
        'Request timed out for $uri. Make sure FastAPI is running and reachable from this device.$emulatorHint',
      );
    }
    if (error is SocketException) {
      return Exception(
        'Cannot connect to $uri (${error.osError?.message ?? error.message}). '
        'Check API URL and server availability.$emulatorHint',
      );
    }
    return Exception('Network request failed for $uri: $error');
  }

  Future<Map<String, dynamic>> analyzePackage({
    required List<int> imageBytes,
    String fileName = 'scan.jpg',
  }) async {
    final uri = _buildUri('/api/v1/analyze');
    final request = http.MultipartRequest('POST', uri)
      ..files.add(
        http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: fileName,
        ),
      );

    late final http.StreamedResponse streamed;
    late final http.Response response;
    try {
      streamed = await _client.send(request).timeout(_requestTimeout);
      response = await http.Response.fromStream(streamed);
    } catch (error) {
      throw _networkException(error, uri);
    }
    if (response.statusCode != 200) {
      throw Exception('Analyze request failed (${response.statusCode}): ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected analyze response format');
    }
    return decoded;
  }

  Future<void> saveReport({
    required Map<String, dynamic> result,
    String deviceId = 'pharos-android',
    String publicKey = 'android-client',
    String signature = 'android-client',
    String? location,
  }) async {
    final uri = _buildUri('/api/v1/reports');
    final payload = {
      'device_id': deviceId,
      'public_key': publicKey,
      'signature': signature,
      'scan_results': [
        {
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'location': location,
          'medicine_name': result['medicine_name'],
          'batch_code': _extractBatchCode(result),
          'risk_level': result['risk_level'],
          'risk_score': result['risk_score'],
          'flags': _extractFlags(result),
        }
      ],
    };

    late final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(_requestTimeout);
    } catch (error) {
      throw _networkException(error, uri);
    }
    if (response.statusCode != 200) {
      throw Exception('Save report failed (${response.statusCode}): ${response.body}');
    }
  }

  Future<Map<String, dynamic>> getStats() async {
    final Uri uri = _buildUri('/api/v1/stats');
    late final http.Response response;
    try {
      response = await _client.get(uri).timeout(_requestTimeout);
    } catch (error) {
      throw _networkException(error, uri);
    }
    if (response.statusCode != 200) {
      throw Exception('Stats request failed (${response.statusCode}): ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected stats response format');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> getHistory({
    int limit = 20,
    int offset = 0,
    String? riskLevel,
    String? search,
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
    };
    if (riskLevel != null && riskLevel.isNotEmpty) {
      params['risk_level'] = riskLevel;
    }
    if (search != null && search.trim().isNotEmpty) {
      params['search'] = search.trim();
    }

    final Uri uri = _buildUri('/api/v1/history', params);
    late final http.Response response;
    try {
      response = await _client.get(uri).timeout(_requestTimeout);
    } catch (error) {
      throw _networkException(error, uri);
    }
    if (response.statusCode != 200) {
      throw Exception('History request failed (${response.statusCode}): ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected history response format');
    }
    return decoded;
  }

  String _extractBatchCode(Map<String, dynamic> result) {
    final batch = result['batch_code'];
    if (batch is Map<String, dynamic>) {
      final extracted = batch['extracted'];
      if (extracted is String) {
        return extracted;
      }
    }
    if (batch is String) {
      return batch;
    }
    return '';
  }

  List<String> _extractFlags(Map<String, dynamic> result) {
    final flags = result['flags'];
    if (flags is List) {
      return flags.map((item) => item.toString()).toList();
    }
    return <String>[];
  }

  void dispose() {
    _client.close();
  }
}
