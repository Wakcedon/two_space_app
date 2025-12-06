/// Константы для приветственного экрана
class GreetingConstants {
  // Доступные приветствия
  static const List<String> greetings = [
    'Приветствуем!',
    'Ку-ку!',
    'Здарова!',
    'Привет!',
    'Хэллоу!',
    'Йоу!',
    'Альфа-тест!',
  ];

  // Длительность анимации
  static const Duration animationDuration = Duration(milliseconds: 900);

  // Длительность отображения экрана приветствия
  static const Duration welcomeScreenDuration = Duration(seconds: 3);

  // Длительность обратной анимации перед переходом
  static const Duration reverseDuration = Duration(milliseconds: 900);

  // Параметры масштабирования
  static const double scaleStart = 0.95;
  static const double scaleEnd = 1.0;

  // Радиус аватара на экране приветствия
  static const double avatarRadius = 48.0;

  // Отступы карточки
  static const double cardPadding = 20.0;

  // Расстояния между элементами
  static const double spacingSmall = 6.0;
  static const double spacingMedium = 8.0;
  static const double spacingLarge = 12.0;

  // Радиус карточки
  static const double cardBorderRadius = 16.0;

  // Тень карточки
  static const double cardElevation = 8.0;

  // Opacity для небольших текстов
  static const double subtleTextOpacity = 0.8;
}
