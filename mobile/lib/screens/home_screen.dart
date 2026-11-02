import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/ad_service.dart';
import '../config/constants.dart';
import 'withdraw_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _apiService = ApiService();
  final AdService _adService = AdService();

  bool _isLoading = true;
  int _saldoPontos = 0;
  double _saldoReais = 0.0;
  String _userName = '';
  Map<String, dynamic>? _proximoSaque;

  // Controle de Cooldown e exibição do anúncio
  bool _isWatching = false;
  int _cooldownTimer = 0;
  Timer? _timer;

  final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final NumberFormat _pointsFormat = NumberFormat.decimalPattern('pt_BR');

  @override
  void initState() {
    super.initState();
    _loadData();
    _initAdNetwork();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _initAdNetwork() {
    _adService.initialize(onReady: () {
      if (mounted) setState(() {});
    });

    // Callback disparado quando o vídeo recompensado é finalizado com sucesso
    _adService.onRewardEarnedCallback = () {
      _onVideoCompleted();
    };

    _adService.onAdFailedCallback = (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.orangeAccent),
        );
      }
    };
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final res = await _apiService.getBalance();
    if (res['success'] && mounted) {
      final data = res['data'];
      setState(() {
        _saldoPontos = data['saldo_pontos'] ?? 0;
        _saldoReais = (data['saldo_reais'] as num?)?.toDouble() ?? 0.0;
        _userName = data['nome'] ?? 'Usuário';
        _proximoSaque = data['proximo_saque_minimo'];
        _isLoading = false;
      });
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Ação ao clicar no botão "Assistir Vídeo"
  Future<void> _watchRewardedAd() async {
    if (_cooldownTimer > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Aguarde $_cooldownTimer segundos para assistir ao próximo vídeo.'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final userId = _apiService.userId;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sessão expirada. Faça login novamente.')),
      );
      return;
    }

    setState(() => _isWatching = true);

    final displayed = await _adService.showRewardedAd(currentUserId: userId);

    if (!displayed) {
      if (mounted) {
        setState(() => _isWatching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Carregando anúncio... Tente novamente em alguns segundos.'),
            backgroundColor: Colors.blueGrey,
          ),
        );
      }
    }
  }

  // Chamado após término do anúncio
  void _onVideoCompleted() {
    if (!mounted) return;
    setState(() {
      _isWatching = false;
      // Inicia contador de cooldown para evitar automação/spam
      _startCooldown(AppConstants.cooldownBetweenAdsSeconds);
    });

    // Notificação visual de sucesso
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🎉 Parabéns! +100 Pontos validados e creditados!'),
        backgroundColor: Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
      ),
    );

    // Atualiza saldo sincronizado com o Backend SSV
    Future.delayed(const Duration(milliseconds: 1500), () {
      _loadData();
    });
  }

  void _startCooldown(int seconds) {
    _cooldownTimer = seconds;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_cooldownTimer > 1) {
        if (mounted) setState(() => _cooldownTimer--);
      } else {
        timer.cancel();
        if (mounted) setState(() => _cooldownTimer = 0);
      }
    });
  }

  void _logout() async {
    await _apiService.logout();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final metaPontos = _proximoSaque?['pontos'] ?? AppConstants.pointsFirstWithdraw;
    final progress = (_saldoPontos / metaPontos).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Olá, $_userName 👋', style: const TextStyle(fontSize: 16, color: Colors.white70)),
            const Text('Painel de Ganhos', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: _logout,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: const Color(0xFF10B981),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ================= CARD DE SALDO =================
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF059669), Color(0xFF10B981)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'SALDO ATUAL',
                          style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            '1.000 pts = R\$ 0,10',
                            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        )
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _currencyFormat.format(_saldoReais),
                      style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.stars_rounded, color: Colors.amberAccent, size: 20),
                        const SizedBox(width: 6),
                        Text(
                          '${_pointsFormat.format(_saldoPontos)} Pontos',
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Barra de progresso para a meta
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: Colors.black26,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _saldoPontos >= metaPontos
                          ? '🎉 Meta atingida! Você já pode realizar o saque!'
                          : 'Faltam ${_pointsFormat.format(metaPontos - _saldoPontos)} pontos para o próximo saque.',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // ================= BOTÃO ASSISTIR VÍDEO =================
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.play_circle_fill, size: 48, color: Color(0xFF38BDF8)),
                    const SizedBox(height: 8),
                    const Text(
                      'Ganhe Assistindo Anúncios',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Cada vídeo assistido até o fim rende +100 Pontos instantâneos.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: (_isWatching || _cooldownTimer > 0) ? null : _watchRewardedAd,
                        icon: _isWatching
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Icon(
                                _cooldownTimer > 0 ? Icons.timer_outlined : Icons.ondemand_video,
                                color: Colors.white,
                              ),
                        label: Text(
                          _cooldownTimer > 0
                              ? 'Aguarde ${_cooldownTimer}s'
                              : _isWatching
                                  ? 'Exibindo Anúncio...'
                                  : 'Assistir Vídeo (+100 Pontos)',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          disabledBackgroundColor: const Color(0xFF334155),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ================= ATALHO PARA SAQUE PIX =================
              InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const WithdrawScreen()),
                  ).then((_) => _loadData());
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.pix, color: Color(0xFF10B981), size: 28),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Resgatar via PIX',
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Saques a partir de R\$ 0,50',
                              style: TextStyle(color: Colors.grey, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
