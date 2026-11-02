import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:applovin_max/applovin_max.dart';
import '../config/constants.dart';
import 'api_service.dart';

class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  bool _isInitialized = false;
  bool _isAdLoaded = false;
  bool _isLoadingAd = false;
  int _retryAttempt = 0;

  bool get isAdLoaded => _isAdLoaded;
  bool get isLoadingAd => _isLoadingAd;

  Function()? onRewardEarnedCallback;
  Function(String error)? onAdFailedCallback;

  String get _adUnitId {
    return Platform.isAndroid
        ? AppConstants.rewardedAdUnitIdAndroid
        : AppConstants.rewardedAdUnitIdIOS;
  }

  // Inicializa o SDK do AppLovin MAX
  Future<void> initialize({required Function onReady}) async {
    if (_isInitialized) {
      onReady();
      return;
    }

    // Configuração inicial do SDK
    AppLovinMAX.setTestDeviceAdvertisingIds([]);
    await AppLovinMAX.initialize(AppConstants.appLovinSdkKey);
    _isInitialized = true;

    // Configura os ouvintes do Rewarded Ad
    _setupRewardedAdListeners();

    // Carrega o primeiro anúncio
    loadRewardedAd();
    onReady();
  }

  void _setupRewardedAdListeners() {
    AppLovinMAX.setRewardedAdListener(RewardedAdListener(
      onAdLoadedCallback: (ad) {
        _isAdLoaded = true;
        _isLoadingAd = false;
        _retryAttempt = 0;
        print('[AdService] Anúncio recompensado carregado com sucesso!');
      },
      onAdLoadFailedCallback: (adUnitId, error) {
        _isAdLoaded = false;
        _isLoadingAd = false;
        _retryAttempt++;
        print('[AdService] Falha ao carregar anúncio: ${error.message}. Tentativa $_retryAttempt');
        // Tenta carregar novamente com backoff exponencial
        Future.delayed(Duration(seconds: _retryAttempt * 3), () {
          loadRewardedAd();
        });
      },
      onAdDisplayedCallback: (ad) {
        print('[AdService] Anúncio sendo exibido ao usuário');
      },
      onAdDisplayFailedCallback: (ad, error) {
        _isAdLoaded = false;
        loadRewardedAd();
        if (onAdFailedCallback != null) {
          onAdFailedCallback!('Erro na exibição do anúncio: ${error.message}');
        }
      },
      onAdClickedCallback: (ad) {},
      onAdHiddenCallback: (ad) {
        // Anúncio fechado: carrega imediatamente o próximo em segundo plano
        _isAdLoaded = false;
        loadRewardedAd();
      },
      onAdReceivedRewardCallback: (ad, reward) {
        // RECOMPENSA CONCLUÍDA NO CLIENTE:
        // O saldo definitivo é atualizado via Server-Side Verification (SSV) no Backend.
        print('[AdService] Usuário assistiu o vídeo completo! Aguardando SSV.');
        if (onRewardEarnedCallback != null) {
          onRewardEarnedCallback!();
        }
      },
    ));
  }

  // Carrega o anúncio em segundo plano
  void loadRewardedAd() {
    if (_isLoadingAd || _isAdLoaded) return;
    _isLoadingAd = true;
    AppLovinMAX.loadRewardedAd(_adUnitId);
  }

  // Exibe o anúncio para o usuário
  Future<bool> showRewardedAd({required String currentUserId}) async {
    final isReady = await AppLovinMAX.isRewardedAdReady(_adUnitId);
    if (isReady == true) {
      // CRUCIAL: Passa o user_id cadastrado para o Server-Side Verification (SSV)
      // O servidor da rede de anúncios repassará esse valor para o nosso Webhook seguro
      AppLovinMAX.setRewardedAdExtraParameter(_adUnitId, 'custom_data', currentUserId);

      await AppLovinMAX.showRewardedAd(_adUnitId);
      return true;
    } else {
      loadRewardedAd();
      return false;
    }
  }
}
