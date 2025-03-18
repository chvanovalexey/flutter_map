import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_example/misc/tile_providers.dart';
import 'package:flutter_map_example/widgets/drawer/floating_menu_button.dart';
import 'package:flutter_map_example/widgets/drawer/menu_drawer.dart';
import 'package:flutter_map_example/widgets/first_start_dialog.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';

class HomePage extends StatefulWidget {
  static const String route = '/';

  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  List<Marker> markers = [];
  List<Polyline> polylines = [];
  bool isLoading = true;
  String? error;
  
  // Переменные для отслеживания производительности
  late Ticker _ticker;
  int _fps = 0;
  double _frameTime = 0.0;
  int _jankScore = 0;
  int _frameCount = 0;
  int _jankCount = 0;
  Stopwatch _stopwatch = Stopwatch();
  DateTime _lastUpdate = DateTime.now();
  
  // Настройки отображения слоёв
  bool _showMarkersLayer = true;
  bool _showLinesLayer = true;
  bool _showLayersPanel = false;
  
  @override
  void initState() {
    super.initState();
    showIntroDialogIfNeeded();
    loadContainerRoute();
    
    // Инициализация тикера для отслеживания производительности
    _stopwatch.start();
    _ticker = createTicker(_onTick)..start();
  }
  
  @override
  void dispose() {
    _ticker.dispose();
    _stopwatch.stop();
    super.dispose();
  }
  
  // Обработчик тика для расчета FPS и времени кадра
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
  
  // Загрузка GeoJSON данных вручную
  Future<void> loadContainerRoute() async {
    try {
      // Загружаем GeoJSON файл
      const filePath = 'assets/sample-geojson/1.geojson';
      final geoJsonString = await rootBundle.loadString(filePath);
      final geoJson = jsonDecode(geoJsonString);
      
      // Временные списки для маркеров и линий
      final List<Marker> loadedMarkers = [];
      final List<Polyline> loadedPolylines = [];
      
      // Обрабатываем "features" из GeoJSON
      final features = geoJson['features'] as List;
      
      for (final feature in features) {
        final geometry = feature['geometry'] as Map<String, dynamic>;
        final properties = feature['properties'] as Map<String, dynamic>;
        final type = geometry['type'] as String;
        
        // Обрабатываем точки для создания маркеров
        if (type == 'Point') {
          final coordinates = geometry['coordinates'] as List;
          final lng = coordinates[0] as num;
          final lat = coordinates[1] as num;
          
          loadedMarkers.add(
            Marker(
              point: LatLng(lat.toDouble(), lng.toDouble()),
              width: 60,
              height: 70,
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    properties['marker-symbol'] == 'harbor' 
                        ? Icons.anchor 
                        : Icons.directions_boat,
                    color: _colorFromHex(properties['marker-color']?.toString() ?? '#3bb2d0'),
                    size: 25,
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      properties['name']?.toString() ?? '',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        
        // Обрабатываем линии
        else if (type == 'LineString') {
          final coordinates = geometry['coordinates'] as List;
          final List<LatLng> points = [];
          
          for (final coord in coordinates) {
            final lng = (coord[0] as num).toDouble();
            final lat = (coord[1] as num).toDouble();
            points.add(LatLng(lat, lng));
          }
          
          // Определяем стиль линии по свойствам
          final strokeWidth = double.tryParse(properties['stroke-width']?.toString() ?? '2.0') ?? 2.0;
          final color = _colorFromHex(properties['stroke']?.toString() ?? '#3388ff');
          final bool isDashed = properties['dash-array'] != null;
          
          // Создаем полилинию с или без паттерна в зависимости от isDashed
          if (isDashed) {
            loadedPolylines.add(
              Polyline(
                points: points,
                strokeWidth: strokeWidth,
                color: color,
                pattern: const StrokePattern.dotted(),
              ),
            );
          } else {
            loadedPolylines.add(
              Polyline(
                points: points,
                strokeWidth: strokeWidth,
                color: color,
              ),
            );
          }
        }
      }
      
      // Обновляем state с загруженными данными
      setState(() {
        markers = loadedMarkers;
        polylines = loadedPolylines;
        isLoading = false;
        error = null;
      });
      
    } catch (e) {
      setState(() {
        isLoading = false;
        error = 'Ошибка загрузки данных: $e';
      });
      print('Error loading GeoJSON: $e');
    }
  }
  
  // Вспомогательный метод для парсинга hex-цвета
  Color _colorFromHex(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const MenuDrawer(HomePage.route),
      body: Stack(
        children: [
          FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(10.0, 115.0),
              initialZoom: 4,
            ),
            children: [
              openStreetMapTileLayer,
              // Отображаем индикатор загрузки или сообщение об ошибке
              if (isLoading)
                const Center(child: CircularProgressIndicator())
              else if (error != null)
                Center(child: Text(error!))
              else ...[
                // Слой с линиями (отображаем только если _showLinesLayer = true)
                if (_showLinesLayer)
                  PolylineLayer(polylines: polylines),
                
                // Слой с маркерами (отображаем только если _showMarkersLayer = true)
                if (_showMarkersLayer)
                  MarkerLayer(markers: markers),
              ],
              RichAttributionWidget(
                popupInitialDisplayDuration: const Duration(seconds: 5),
                animationConfig: const ScaleRAWA(),
                showFlutterMapAttribution: false,
                attributions: [
                  TextSourceAttribution(
                    'OpenStreetMap contributors',
                    onTap: () async => launchUrl(
                      Uri.parse('https://openstreetmap.org/copyright'),
                    ),
                  ),
                  const TextSourceAttribution(
                    'This attribution is the same throughout this app, except '
                    'where otherwise specified',
                    prependCopyright: false,
                  ),
                ],
              ),
            ],
          ),
          
          // Виджет производительности в правом верхнем углу
          Positioned(
            top: 16,
            right: 16,
            child: _buildPerformanceOverlay(),
          ),
          
          // Кнопка для показа/скрытия панели управления слоями (переносим в нижний левый угол)
          Positioned(
            left: 16,
            bottom: 16,
            child: Material(
              color: Colors.blue,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              elevation: 3,
              child: InkWell(
                onTap: () {
                  setState(() {
                    _showLayersPanel = !_showLayersPanel;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    _showLayersPanel ? Icons.layers_clear : Icons.layers,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          
          // Панель управления слоями (показываем только когда _showLayersPanel = true)
          if (_showLayersPanel)
            Positioned(
              left: 16,
              bottom: 70,
              width: 280, // Фиксированная ширина для панели
              child: SafeArea(
                child: _buildLayersPanel(),
              ),
            ),
          
          const FloatingMenuButton()
        ],
      ),
    );
  }
  
  // Построение панели управления слоями
  Widget _buildLayersPanel() {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Управление слоями',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const Divider(),
            
            // Переключатель слоя маркеров
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.place,
                      color: _showMarkersLayer ? Colors.blue : Colors.grey,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Маркеры', style: TextStyle(fontSize: 14)),
                        const Text(
                          'Порты и суда',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
                Switch(
                  value: _showMarkersLayer,
                  onChanged: (value) {
                    setState(() {
                      _showMarkersLayer = value;
                    });
                  },
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // Переключатель слоя линий
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.timeline,
                      color: _showLinesLayer ? Colors.blue : Colors.grey,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Маршруты', style: TextStyle(fontSize: 14)),
                        const Text(
                          'Линии морских путей',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
                Switch(
                  value: _showLinesLayer,
                  onChanged: (value) {
                    setState(() {
                      _showLinesLayer = value;
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  // Построение виджета с информацией о производительности
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

  void showIntroDialogIfNeeded() {
    const seenIntroBoxKey = 'seenIntroBox(a)';
    if (kIsWeb && Uri.base.host.trim() == 'demo.fleaflet.dev') {
      SchedulerBinding.instance.addPostFrameCallback(
        (_) async {
          final prefs = await SharedPreferences.getInstance();
          if (prefs.getBool(seenIntroBoxKey) ?? false) return;

          if (!mounted) return;

          await showDialog<void>(
            context: context,
            builder: (context) => const FirstStartDialog(),
          );
          await prefs.setBool(seenIntroBoxKey, true);
        },
      );
    }
  }
}

// Helper extension for converting hex color strings to Color objects
extension HexColor on Color {
  static Color fromHex(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }
}
