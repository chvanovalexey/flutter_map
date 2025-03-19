import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Импортируем обе реализации
import 'mapbox_page_web.dart';
import 'mapbox_page_mobile.dart';

// Создаем страницу-оболочку, которая выбирает нужную реализацию в зависимости от платформы
class MapboxPage extends StatelessWidget {
  static const String route = '/mapbox_page';

  const MapboxPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Проверяем, запущено ли приложение в вебе
    if (kIsWeb) {
      return const MapboxPageWeb();
    } else {
      return const MapboxPageMobile();
    }
  }
}

// Остальной код удален 