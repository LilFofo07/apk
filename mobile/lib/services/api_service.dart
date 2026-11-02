import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../config/constants.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  String? _token;
  String? _userId;

  String? get userId => _userId;
  String? get token => _token;

  // Inicializa recuperando dados em cache
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('auth_token');
    _userId = prefs.getString('user_id');
  }

  // Obtém identificador único e persistente do aparelho para Anti-Fraude
  Future<String> getDeviceId() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        return androidInfo.id; // ID único do hardware Android
      } else if (Platform.isIOS) {
        final IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        return iosInfo.identifierForVendor ?? 'ios_unknown_device';
      }
    } catch (e) {
      print('Erro ao obter deviceId: $e');
    }
    return 'fallback_device_id_${DateTime.now().millisecondsSinceEpoch}';
  }

  Map<String, String> _headers() {
    return {
      'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
    };
  }

  // Cadastro
  Future<Map<String, dynamic>> register({
    required String nome,
    required String email,
    required String senha,
    String? chavePix,
    String? tipoChave,
  }) async {
    final deviceId = await getDeviceId();
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/auth/register'),
      headers: _headers(),
      body: jsonEncode({
        'nome': nome,
        'email': email,
        'senha': senha,
        'device_id': deviceId,
        'chave_pix': chavePix,
        'tipo_chave': tipoChave,
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 201) {
      await _saveSession(data['token'], data['user']['id']);
      return {'success': true, 'data': data};
    } else {
      return {'success': false, 'error': data['error'] ?? 'Falha ao registrar.'};
    }
  }

  // Login
  Future<Map<String, dynamic>> login({
    required String email,
    required String senha,
  }) async {
    final deviceId = await getDeviceId();
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/auth/login'),
      headers: _headers(),
      body: jsonEncode({
        'email': email,
        'senha': senha,
        'device_id': deviceId,
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      await _saveSession(data['token'], data['user']['id']);
      return {'success': true, 'data': data};
    } else {
      return {'success': false, 'error': data['error'] ?? 'Falha no login.'};
    }
  }

  // Consulta de Saldo
  Future<Map<String, dynamic>> getBalance() async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/user/balance'),
      headers: _headers(),
    );

    if (response.statusCode == 200) {
      return {'success': true, 'data': jsonDecode(response.body)};
    } else {
      return {'success': false, 'error': 'Não foi possível carregar o saldo.'};
    }
  }

  // Solicitar Saque
  Future<Map<String, dynamic>> requestWithdraw({
    required double valorReais,
    required String chavePix,
    required String tipoChave,
  }) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/withdraw'),
      headers: _headers(),
      body: jsonEncode({
        'valor_reais': valorReais,
        'chave_pix': chavePix,
        'tipo_chave': tipoChave,
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 201) {
      return {'success': true, 'data': data};
    } else {
      return {'success': false, 'error': data['error'] ?? 'Erro ao processar saque.'};
    }
  }

  // Histórico de Saques
  Future<List<dynamic>> getWithdrawHistory() async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/withdraw/history'),
      headers: _headers(),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['saques'] ?? [];
    }
    return [];
  }

  Future<void> _saveSession(String token, String userId) async {
    _token = token;
    _userId = userId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    await prefs.setString('user_id', userId);
  }

  Future<void> logout() async {
    _token = null;
    _userId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
