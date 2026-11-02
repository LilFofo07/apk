class AppConstants {
  // Altere para o IP local da sua máquina ou domínio de produção
  // No emulador Android, '10.0.2.2' aponta para o localhost da máquina host
  static const String baseUrl = 'http://10.0.2.2:3000/api';

  // Configuração das Ad Networks (AppLovin MAX / AdMob)
  static const String appLovinSdkKey = 'SUA_SDK_KEY_DO_APPLOVIN';
  static const String rewardedAdUnitIdAndroid = 'SEU_AD_UNIT_ID_REWARDED_ANDROID';
  static const String rewardedAdUnitIdIOS = 'SEU_AD_UNIT_ID_REWARDED_IOS';

  // Economia do App
  static const int pointsPerVideo = 100;
  static const double reaisPer1000Points = 0.10; // 1.000 pontos = R$ 0,10

  // Metas de Saque
  static const int pointsFirstWithdraw = 5000;    // R$ 0,50
  static const int pointsSecondWithdraw = 20000;  // R$ 2,00
  static const int pointsThirdWithdraw = 50000;   // R$ 5,00

  static const int cooldownBetweenAdsSeconds = 25;
}
