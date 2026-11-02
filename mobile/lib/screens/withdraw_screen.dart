import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

class WithdrawScreen extends StatefulWidget {
  const WithdrawScreen({super.key});

  @override
  State<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends State<WithdrawScreen> {
  final ApiService _apiService = ApiService();

  bool _isLoading = true;
  bool _isSubmitting = false;

  int _saldoPontos = 0;
  double _saldoReais = 0.0;
  int _totalSaquesRealizados = 0;

  final _pixController = TextEditingController();
  String _tipoChave = 'CPF';
  double? _valorSelecionado;

  List<dynamic> _historico = [];

  final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final NumberFormat _pointsFormat = NumberFormat.decimalPattern('pt_BR');
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    final balanceRes = await _apiService.getBalance();
    final history = await _apiService.getWithdrawHistory();

    if (balanceRes['success'] && mounted) {
      final data = balanceRes['data'];
      setState(() {
        _saldoPontos = data['saldo_pontos'] ?? 0;
        _saldoReais = (data['saldo_reais'] as num?)?.toDouble() ?? 0.0;
        _totalSaquesRealizados = data['total_saques_realizados'] ?? 0;
        if (data['pix_cadastrado'] != null && data['pix_cadastrado']['chave'] != null) {
          _pixController.text = data['pix_cadastrado']['chave'];
          _tipoChave = data['pix_cadastrado']['tipo'] ?? 'CPF';
        }
        _historico = history;
        _isLoading = false;
      });
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _solicitarSaque() async {
    if (_valorSelecionado == null) {
      _showMsg('Selecione um valor para saque.', Colors.orangeAccent);
      return;
    }

    if (_pixController.text.trim().isEmpty) {
      _showMsg('Informe a sua Chave PIX.', Colors.orangeAccent);
      return;
    }

    setState(() => _isSubmitting = true);

    final res = await _apiService.requestWithdraw(
      valorReais: _valorSelecionado!,
      chavePix: _pixController.text.trim(),
      tipoChave: _tipoChave,
    );

    if (res['success'] && mounted) {
      _showMsg('✅ Saque solicitado com sucesso!', const Color(0xFF10B981));
      _valorSelecionado = null;
      await _loadInitialData();
    } else {
      if (mounted) {
        _showMsg(res['error'] ?? 'Falha ao solicitar saque.', Colors.redAccent);
      }
    }

    if (mounted) setState(() => _isSubmitting = false);
  }

  void _showMsg(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPrimeiroSaque = _totalSaquesRealizados == 0;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Resgate via PIX', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Saldo Disponível
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Disponível para Saque', style: TextStyle(color: Colors.grey, fontSize: 13)),
                            const SizedBox(height: 4),
                            Text(
                              _currencyFormat.format(_saldoReais),
                              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.stars, color: Colors.amberAccent, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                '${_pointsFormat.format(_saldoPontos)} pts',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Dados do PIX
                  const Text('1. Informe sua Chave PIX', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          value: _tipoChave,
                          dropdownColor: const Color(0xFF1E293B),
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: _inputDec('Tipo'),
                          items: ['CPF', 'EMAIL', 'TELEFONE', 'ALEATORIA']
                              .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                              .toList(),
                          onChanged: (v) => setState(() => _tipoChave = v!),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _pixController,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDec('Chave PIX'),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // Escolha do Valor
                  const Text('2. Selecione a Meta de Saque', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),

                  // Card R$ 0,50 (1º Saque)
                  _buildOptionCard(
                    valor: 0.50,
                    pontos: 5000,
                    tag: 'Boas-Vindas (1º Saque)',
                    isDisponivel: isPrimeiroSaque && _saldoPontos >= 5000,
                    isBloqueadoDefinitivo: !isPrimeiroSaque,
                    motivoBloqueio: !isPrimeiroSaque ? 'Já utilizado no 1º resgate' : 'Necessário 5.000 pontos',
                  ),

                  const SizedBox(height: 12),

                  // Card R$ 2,00 (Saques Seguintes)
                  _buildOptionCard(
                    valor: 2.00,
                    pontos: 20000,
                    tag: 'Saque Regular',
                    isDisponivel: _saldoPontos >= 20000,
                    isBloqueadoDefinitivo: false,
                    motivoBloqueio: 'Necessário 20.000 pontos',
                  ),

                  const SizedBox(height: 12),

                  // Card R$ 5,00 (Saques Seguintes)
                  _buildOptionCard(
                    valor: 5.00,
                    pontos: 50000,
                    tag: 'Saque Turbo',
                    isDisponivel: _saldoPontos >= 50000,
                    isBloqueadoDefinitivo: false,
                    motivoBloqueio: 'Necessário 50.000 pontos',
                  ),

                  const SizedBox(height: 24),

                  // Botão Confirmar Saque
                  SizedBox(
                    height: 54,
                    child: ElevatedButton(
                      onPressed: (_isSubmitting || _valorSelecionado == null) ? null : _solicitarSaque,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        disabledBackgroundColor: const Color(0xFF334155),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _isSubmitting
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                              _valorSelecionado == null
                                  ? 'Selecione uma Meta de Saque'
                                  : 'Resgatar ${_currencyFormat.format(_valorSelecionado)} via PIX',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                    ),
                  ),

                  const SizedBox(height: 36),

                  // ================= HISTÓRICO DE SAQUES =================
                  const Text('Histórico de Resgates', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (_historico.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Center(
                        child: Text('Nenhum saque solicitado ainda.', style: TextStyle(color: Colors.grey)),
                      ),
                    )
                  else
                    ..._historico.map((s) => _buildHistoryItem(s)),
                ],
              ),
            ),
    );
  }

  Widget _buildOptionCard({
    required double valor,
    required int pontos,
    required String tag,
    required bool isDisponivel,
    required bool isBloqueadoDefinitivo,
    required String motivoBloqueio,
  }) {
    final isSelected = _valorSelecionado == valor;

    return InkWell(
      onTap: isDisponivel ? () => setState(() => _valorSelecionado = valor) : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF10B981).withOpacity(0.12)
              : const Color(0xFF1E293B),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF10B981)
                : isDisponivel
                    ? const Color(0xFF334155)
                    : Colors.white10,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.check_circle
                  : isDisponivel
                      ? Icons.radio_button_unchecked
                      : Icons.lock_outline,
              color: isSelected
                  ? const Color(0xFF10B981)
                  : isDisponivel
                      ? Colors.white54
                      : Colors.white24,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _currencyFormat.format(valor),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDisponivel ? Colors.white : Colors.white38,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isBloqueadoDefinitivo ? Colors.red.withOpacity(0.2) : Colors.blue.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(
                            fontSize: 10,
                            color: isBloqueadoDefinitivo ? Colors.redAccent : const Color(0xFF38BDF8),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isDisponivel
                        ? '${_pointsFormat.format(pontos)} pontos necessários'
                        : motivoBloqueio,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDisponivel ? Colors.grey.shade400 : Colors.redAccent.shade100,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryItem(dynamic saque) {
    final status = (saque['status'] ?? 'pendente').toString().toLowerCase();
    Color statusColor;
    String statusLabel;

    switch (status) {
      case 'pago':
        statusColor = const Color(0xFF10B981);
        statusLabel = 'PAGO';
        break;
      case 'rejeitado':
        statusColor = Colors.redAccent;
        statusLabel = 'REJEITADO';
        break;
      default:
        statusColor = Colors.amberAccent;
        statusLabel = 'PENDENTE';
    }

    DateTime? date;
    if (saque['created_at'] != null) {
      date = DateTime.tryParse(saque['created_at']);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _currencyFormat.format(double.tryParse(saque['valor_reais'].toString()) ?? 0.0),
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                'PIX: ${saque['chave_pix']}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              if (date != null)
                Text(
                  _dateFormat.format(date),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: statusColor.withOpacity(0.4)),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDec(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
      filled: true,
      fillColor: const Color(0xFF1E293B),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}
