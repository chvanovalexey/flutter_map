import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
// Импортируем пакет Mapbox только на мобильных платформах
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' if (kIsWeb) 'package:flutter_map_example/pages/mapbox_stub.dart';
import 'package:flutter_map_example/widgets/drawer/floating_menu_button.dart';
import 'package:flutter_map_example/widgets/drawer/menu_drawer.dart';

class MapboxPageMobile extends StatefulWidget {
  static const String route = '/mapbox_page';

  const MapboxPageMobile({super.key});

  @override
  State<MapboxPageMobile> createState() => _MapboxPageMobileState();
}

class _MapboxPageMobileState extends State<MapboxPageMobile> with SingleTickerProviderStateMixin {
  // Mapbox token
  static const String mapboxAccessToken = 'pk.eyJ1IjoiY2h2YW5vdmFsZXhleSIsImEiOiJjbThlaGR5YXgwMWdpMmpzZG1hZm9weHFjIn0.y9kFEPItcETr0or609EYhg';
  
  // Для контроллера карты
  MapboxMap? _mapboxMap;
  
  // Переменные для отслеживания производительности
  late Ticker _ticker;
  int _fps = 0;
  double _frameTime = 0.0;
  int _jankScore = 0;
  int _frameCount = 0;
  int _jankCount = 0;
  Stopwatch _stopwatch = Stopwatch();
  DateTime _lastUpdate = DateTime.now();

  @override
  void initState() {
    super.initState();
    
    // Устанавливаем токен доступа Mapbox
    MapboxOptions.setAccessToken(mapboxAccessToken);
    
    // Инициализируем отслеживание производительности
    _stopwatch.start();
    _ticker = createTicker(_onTick)..start();
  }
  
  @override
  void dispose() {
    _ticker.dispose();
    _stopwatch.stop();
    super.dispose();
  }
  
  // Обработчик для тикера производительности
  void _onTick(Duration elapsed) {
    _frameCount++;
    
    final now = DateTime.now();
    final frameTimeMs = _stopwatch.elapsedMicroseconds / 1000.0;
    _stopwatch.reset();
    _stopwatch.start();
    
    // Обнаружение "jank" (задержек) при рендеринге
    if (frameTimeMs > 16.667) { // больше 60 FPS
      _jankCount++;
    }
    
    // Обновляем метрики каждую секунду
    if (now.difference(_lastUpdate).inMilliseconds >= 1000) {
      setState(() {
        _fps = _frameCount;
        _frameTime = frameTimeMs;
        _jankScore = (_jankCount / _frameCount * 100).round();
        
        // Сброс счетчиков
        _frameCount = 0;
        _jankCount = 0;
        _lastUpdate = now;
      });
    }
  }
  
  // Виджет с информацией о производительности
  Widget _buildPerformanceOverlay() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'FPS: $_fps', 
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          Text(
            'Frame Time: ${_frameTime.toStringAsFixed(2)} ms',
            style: const TextStyle(color: Colors.white),
          ),
          Text(
            'Jank Score: $_jankScore%',
            style: TextStyle(
              color: _jankScore < 10 
                  ? Colors.green 
                  : _jankScore < 30 
                      ? Colors.yellow 
                      : Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapbox (Мобильная версия)'),
      ),
      drawer: const MenuDrawer(MapboxPageMobile.route),
      body: Stack(
        children: [
          // Mapbox карта
          MapWidget(
            key: const ValueKey('mapWidget'),
            onMapCreated: _onMapCreated,
          ),
          
          // Панель производительности в правом верхнем углу
          Positioned(
            top: 16,
            right: 16,
            child: _buildPerformanceOverlay(),
          ),
          
          // Кнопка меню
          const FloatingMenuButton(),
        ],
      ),
    );
  }
  
  // Обработчик создания карты
  void _onMapCreated(MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
    
    // Устанавливаем стиль карты
    mapboxMap.loadStyleURI(MapboxStyles.MAPBOX_STREETS);
    
    // Настраиваем начальную позицию
    mapboxMap.setCamera(
      CameraOptions(
        center: Point(
          coordinates: Position(-74.5, 40.0),
        ).toJson(),
        zoom: 9.0,
      ),
    );
    
    print('Mapbox map created successfully');
  }
} 