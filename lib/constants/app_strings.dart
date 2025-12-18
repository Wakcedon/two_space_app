/// Centralized string constants for the app
/// Helps with localization and maintainability
class AppStrings {
  AppStrings._();

  // App
  static const appTitle = 'TwoSpace';

  // Loading
  static const loading = 'Загрузка...';
  static const initializing = 'Инициализация...';

  // Errors
  static const errorGeneric = 'Произошла ошибка';
  static const errorInitialization = 'Ошибка при инициализации';
  static const errorInitializationFull = 'Ошибка инициализации';
  static const errorNetwork = 'Ошибка сети';
  static const errorAuth = 'Ошибка аутентификации';
  static const errorInvalidArguments = 'Неверные аргументы';
  static const errorInvalidArgumentsProfile = 'Неверные аргументы для профиля';
  static const errorInvalidArgumentsChat = 'Неверные аргументы для чата';

  // Actions
  static const retry = 'Повторить';
  static const cancel = 'Отмена';
  static const save = 'Сохранить';
  static const delete = 'Удалить';
  static const edit = 'Редактировать';
  static const send = 'Отправить';
  static const close = 'Закрыть';

  // Routes
  static const routeLogin = '/login';
  static const routeHome = '/home';
  static const routeRegister = '/register';
  static const routeForgot = '/forgot';
  static const routeCustomization = '/customization';
  static const routePrivacy = '/privacy';
  static const routeProfile = '/profile';
  static const routeChangeEmail = '/change_email';
  static const routeChat = '/chat';
}
