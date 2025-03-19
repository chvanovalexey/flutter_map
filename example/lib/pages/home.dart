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
import 'dart:async';

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
  
  // Переменные для debouncing слоев
  double _markersDebounceMs = 0;
  double _linesDebounceMs = 0;
  bool _useMarkersDebounce = false;
  bool _useLinesDebounce = false;
  bool _applyMarkersDebounceOnZoom = false;
  bool _applyLinesDebounceOnZoom = false;
  List<Marker> _allMarkers = []; // Временное хранилище для всех маркеров
  List<Polyline> _allPolylines = []; // Временное хранилище для всех полилиний
  Timer? _markersDebounceTimer;
  Timer? _linesDebounceTimer;
  
  // Информация о загруженных маршрутах
  final Map<String, bool> _routeVisibility = {};
  final Map<String, List<Marker>> _routeMarkers = {};
  final Map<String, List<Polyline>> _routePolylines = {};
  final List<String> _routeNames = [];
  
  // Информация о прогрессе загрузки
  int _totalRoutes = 0;
  int _loadedRoutes = 0;
  String _currentLoadingRoute = '';
  
  // Переменные для отслеживания общего состояния маршрутов
  bool _allRoutesVisible = true;
  
  late final MapController _mapController;
  
  // Дополнительные переменные для управления отображением
  bool _sortRoutesReverseOrder = false;
  
  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    showIntroDialogIfNeeded();
    loadAllRoutes();
    
    // Инициализация тикера для отслеживания производительности
    _stopwatch.start();
    _ticker = createTicker(_onTick)..start();
    
    // Добавляем слушатель изменений камеры для применения debouncing
    _mapController.mapEventStream.listen(_handleMapEvent);
  }
  
  @override
  void dispose() {
    _ticker.dispose();
    _stopwatch.stop();
    _markersDebounceTimer?.cancel();
    _linesDebounceTimer?.cancel();
    super.dispose();
  }
  
  // Загрузка всех GeoJSON маршрутов из папки assets/sample-geojson/
  Future<void> loadAllRoutes() async {
    try {
      setState(() {
        isLoading = true;
        error = null;
      });
      
      // Загружаем список всех доступных файлов через AssetManifest
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent) as Map<String, dynamic>;
      
      // Фильтруем только geojson файлы из нужной директории
      final geoJsonFiles = manifestMap.keys
          .where((key) => key.startsWith('assets/sample-geojson/') && key.endsWith('.geojson'))
          .toList();
      
      // Сортируем файлы по имени для более предсказуемого порядка
      geoJsonFiles.sort();
      
      // Устанавливаем общее количество маршрутов для прогресса
      setState(() {
        _totalRoutes = geoJsonFiles.length;
        _loadedRoutes = 0;
      });
      
      // Размер пакета для загрузки маршрутов (сколько маршрутов обрабатывать параллельно)
      const batchSize = 5;
      
      // Загружаем файлы пакетами для улучшения производительности
      for (var i = 0; i < geoJsonFiles.length; i += batchSize) {
        final end = (i + batchSize < geoJsonFiles.length) ? i + batchSize : geoJsonFiles.length;
        final batch = geoJsonFiles.sublist(i, end);
        
        // Загружаем пакет файлов параллельно
        await Future.wait(
          batch.map((filePath) async {
            // Получаем имя файла без пути и расширения
            final fileName = filePath.split('/').last;
            final routeName = fileName.replaceAll('.geojson', '');
            
            setState(() {
              _routeNames.add(routeName);
              _routeVisibility[routeName] = true;
              _currentLoadingRoute = 'Маршрут $routeName';
            });
            
            await loadRouteFromFile(filePath, routeName);
            
            setState(() {
              _loadedRoutes++;
            });
          }),
        );
        
        // Обновляем видимые маркеры и полилинии после каждого пакета
        updateVisibleMarkersAndPolylines();
      }
      
      setState(() {
        isLoading = false;
        _currentLoadingRoute = '';
      });
    } catch (e) {
      setState(() {
        isLoading = false;
        error = 'Ошибка загрузки маршрутов: $e';
      });
      print('Error loading GeoJSON routes: $e');
    }
  }
  
  // Обработчик событий карты для debouncing
  void _handleMapEvent(MapEvent event) {
    // Обновляем маркеры с debouncing
    if (_useMarkersDebounce) {
      bool shouldApplyDebounce = false;
      
      // Проверяем тип события и соответствующие настройки
      if (event is MapEventMove) {
        shouldApplyDebounce = true;
      } else if (_applyMarkersDebounceOnZoom && 
                (event is MapEventDoubleTapZoomStart || 
                 event is MapEventScrollWheelZoom ||
                 event is MapEventFlingAnimation)) {
        shouldApplyDebounce = true;
      }
      
      if (shouldApplyDebounce) {
        _markersDebounceTimer?.cancel();
        _markersDebounceTimer = Timer(
          Duration(milliseconds: _markersDebounceMs.toInt()),
          () {
            if (mounted) setState(() => markers = _allMarkers);
          },
        );
        if (mounted && markers.isNotEmpty) setState(() => markers = []);
      }
    }
    
    // Обновляем линии с debouncing
    if (_useLinesDebounce) {
      bool shouldApplyDebounce = false;
      
      // Проверяем тип события и соответствующие настройки
      if (event is MapEventMove) {
        shouldApplyDebounce = true;
      } else if (_applyLinesDebounceOnZoom && 
                (event is MapEventDoubleTapZoomStart || 
                 event is MapEventScrollWheelZoom ||
                 event is MapEventFlingAnimation)) {
        shouldApplyDebounce = true;
      }
      
      if (shouldApplyDebounce) {
        _linesDebounceTimer?.cancel();
        _linesDebounceTimer = Timer(
          Duration(milliseconds: _linesDebounceMs.toInt()),
          () {
            if (mounted) setState(() => polylines = _allPolylines);
          },
        );
        if (mounted && polylines.isNotEmpty) setState(() => polylines = []);
      }
    }
  }
  
  // Обновление общих списков маркеров и линий на основе видимости маршрутов
  void updateVisibleMarkersAndPolylines() {
    final List<Marker> allMarkers = [];
    final List<Polyline> allPolylines = [];
    
    bool anyRouteVisible = false;
    
    for (final routeName in _routeNames) {
      if (_routeVisibility[routeName] == true) {
        allMarkers.addAll(_routeMarkers[routeName] ?? []);
        allPolylines.addAll(_routePolylines[routeName] ?? []);
        anyRouteVisible = true;
      }
    }
    
    // Обновляем состояние общей видимости
    _allRoutesVisible = anyRouteVisible;
    
    // Сохраняем полные списки для debouncing
    _allMarkers = allMarkers;
    _allPolylines = allPolylines;
    
    setState(() {
      // Применяем списки в зависимости от статуса debouncing
      markers = _useMarkersDebounce ? [] : allMarkers;
      polylines = _useLinesDebounce ? [] : allPolylines;
      
      // Запускаем таймеры для отложенной загрузки
      if (_useMarkersDebounce) {
        _markersDebounceTimer?.cancel();
        _markersDebounceTimer = Timer(
          Duration(milliseconds: _markersDebounceMs.toInt()),
          () {
            if (mounted) setState(() => markers = _allMarkers);
          },
        );
      }
      
      if (_useLinesDebounce) {
        _linesDebounceTimer?.cancel();
        _linesDebounceTimer = Timer(
          Duration(milliseconds: _linesDebounceMs.toInt()),
          () {
            if (mounted) setState(() => polylines = _allPolylines);
          },
        );
      }
    });
  }
  
  // Загрузка маршрута из конкретного файла
  Future<void> loadRouteFromFile(String filePath, String routeName) async {
    try {
      final geoJsonString = await rootBundle.loadString(filePath);
      final geoJson = jsonDecode(geoJsonString);
      
      final List<Marker> loadedMarkers = [];
      final List<Polyline> loadedPolylines = [];
      
      // Получаем цвет для этого маршрута
      final routeColor = _getRouteColor(routeName);
      
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
          
          // Используем цвет маршрута, если не указан другой цвет
          final markerColor = properties['marker-color'] != null 
              ? _colorFromHex(properties['marker-color'].toString()) 
              : routeColor;
          
          loadedMarkers.add(
            Marker(
              point: LatLng(lat.toDouble(), lng.toDouble()),
              width: 60,
              height: 70,
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 5,
                          spreadRadius: 1,
                        ),
                      ],
                      border: Border.all(
                        color: markerColor,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      properties['marker-symbol'] == 'harbor' 
                          ? Icons.anchor 
                          : Icons.directions_boat,
                      color: markerColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        properties['name']?.toString() ?? '',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
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
          
          // Определяем стиль линии по свойствам или используем цвет маршрута
          final strokeWidth = double.tryParse(properties['stroke-width']?.toString() ?? '3.0') ?? 3.0;
          final color = properties['stroke'] != null 
              ? _colorFromHex(properties['stroke'].toString()) 
              : routeColor;
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
      
      // Сохраняем загруженные данные под именем маршрута
      _routeMarkers[routeName] = loadedMarkers;
      _routePolylines[routeName] = loadedPolylines;
      
    } catch (e) {
      print('Error loading route $routeName: $e');
      // В случае ошибки просто создаём пустые списки для этого маршрута
      _routeMarkers[routeName] = [];
      _routePolylines[routeName] = [];
    }
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
  
  // Вспомогательный метод для парсинга hex-цвета
  Color _colorFromHex(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    // Сортируем список маршрутов при необходимости
    final displayedRoutes = List<String>.from(_routeNames)
      ..sort((a, b) => _sortRoutesReverseOrder ? b.compareTo(a) : a.compareTo(b));
      
    return Scaffold(
      drawer: const MenuDrawer(HomePage.route),
      body: Stack(
        children: [
          FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(10.0, 115.0),
              initialZoom: 4,
            ),
            mapController: _mapController,
            children: [
              openStreetMapTileLayer,
              // Отображаем индикатор загрузки или сообщение об ошибке
              if (isLoading)
                _buildLoadingIndicator()
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
          
          // Кнопка для показа/скрытия панели управления слоями
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
              width: 300, // Увеличиваем ширину для большего комфорта
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.7,
                  ),
                  child: _buildLayersPanel(displayedRoutes),
                ),
              ),
            ),
          
          const FloatingMenuButton()
        ],
      ),
    );
  }
  
  // Виджет для отображения прогресса загрузки
  Widget _buildLoadingIndicator() {
    final progress = _totalRoutes > 0 ? _loadedRoutes / _totalRoutes : 0.0;
    
    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Загрузка маршрутов',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_currentLoadingRoute.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Загружается: $_currentLoadingRoute',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey[700],
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
            const SizedBox(height: 8),
            Text(
              'Загружено $_loadedRoutes из $_totalRoutes',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Построение панели управления слоями
  Widget _buildLayersPanel(List<String> displayedRoutes) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Управление слоями',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(() => _showLayersPanel = false),
                ),
              ],
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
                      // Если слой включаем, и был активен debouncing, применяем его
                      if (value && _useMarkersDebounce) {
                        markers = [];
                        _markersDebounceTimer?.cancel();
                        _markersDebounceTimer = Timer(
                          Duration(milliseconds: _markersDebounceMs.toInt()),
                          () {
                            if (mounted) setState(() => markers = _allMarkers);
                          },
                        );
                      }
                    });
                  },
                ),
              ],
            ),
            
            // Добавляем настройки debouncing для маркеров
            if (_showMarkersLayer)
              Padding(
                padding: const EdgeInsets.only(left: 32, top: 4, bottom: 8, right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Tooltip(
                          message: 'Скрывает маркеры при перемещении карты и показывает их с заданной задержкой после остановки. Улучшает производительность.',
                          child: Row(
                            children: [
                              const Text(
                                'Debouncing маркеров',
                                style: TextStyle(fontSize: 13),
                              ),
                              Icon(
                                Icons.info_outline,
                                size: 16,
                                color: Colors.grey[600],
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _useMarkersDebounce,
                          activeColor: Colors.blue,
                          onChanged: (value) {
                            setState(() {
                              _useMarkersDebounce = value;
                            });
                            updateVisibleMarkersAndPolylines();
                          },
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                    if (_useMarkersDebounce)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Задержка обновления маркеров:',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: Slider(
                                  value: _markersDebounceMs,
                                  min: 0,
                                  max: 500,
                                  divisions: 50,
                                  onChanged: (value) {
                                    setState(() {
                                      _markersDebounceMs = value;
                                    });
                                  },
                                ),
                              ),
                              Text(
                                '${_markersDebounceMs.toInt()} мс',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                          
                          // Переключатель для применения debouncing при зуме
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Tooltip(
                                message: 'Активирует debouncing при масштабировании карты (колесо мыши, двойной тап, жесты масштабирования)',
                                child: Row(
                                  children: [
                                    const Text(
                                      'Применять при зуме',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.info_outline,
                                      size: 14,
                                      color: Colors.grey[600],
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _applyMarkersDebounceOnZoom,
                                onChanged: (value) {
                                  setState(() {
                                    _applyMarkersDebounceOnZoom = value;
                                  });
                                },
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ],
                          ),
                        ],
                      ),
                  ],
                ),
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
                      // Если слой включаем, и был активен debouncing, применяем его
                      if (value && _useLinesDebounce) {
                        polylines = [];
                        _linesDebounceTimer?.cancel();
                        _linesDebounceTimer = Timer(
                          Duration(milliseconds: _linesDebounceMs.toInt()),
                          () {
                            if (mounted) setState(() => polylines = _allPolylines);
                          },
                        );
                      }
                    });
                  },
                ),
              ],
            ),
            
            // Добавляем настройки debouncing для линий
            if (_showLinesLayer)
              Padding(
                padding: const EdgeInsets.only(left: 32, top: 4, bottom: 8, right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Tooltip(
                          message: 'Скрывает линии маршрутов при перемещении карты и показывает их с заданной задержкой после остановки. Улучшает производительность.',
                          child: Row(
                            children: [
                              const Text(
                                'Debouncing маршрутов',
                                style: TextStyle(fontSize: 13),
                              ),
                              Icon(
                                Icons.info_outline,
                                size: 16,
                                color: Colors.grey[600],
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _useLinesDebounce,
                          activeColor: Colors.blue,
                          onChanged: (value) {
                            setState(() {
                              _useLinesDebounce = value;
                            });
                            updateVisibleMarkersAndPolylines();
                          },
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                    if (_useLinesDebounce)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Задержка обновления маршрутов:',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: Slider(
                                  value: _linesDebounceMs,
                                  min: 0,
                                  max: 500,
                                  divisions: 50,
                                  onChanged: (value) {
                                    setState(() {
                                      _linesDebounceMs = value;
                                    });
                                  },
                                ),
                              ),
                              Text(
                                '${_linesDebounceMs.toInt()} мс',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                          
                          // Переключатель для применения debouncing при зуме
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Tooltip(
                                message: 'Активирует debouncing при масштабировании карты (колесо мыши, двойной тап, жесты масштабирования)',
                                child: Row(
                                  children: [
                                    const Text(
                                      'Применять при зуме',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.info_outline,
                                      size: 14,
                                      color: Colors.grey[600],
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _applyLinesDebounceOnZoom,
                                onChanged: (value) {
                                  setState(() {
                                    _applyLinesDebounceOnZoom = value;
                                  });
                                },
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ],
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            
            if (_routeNames.isNotEmpty) ...[
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Выбор маршрутов',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Кнопка сортировки
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _sortRoutesReverseOrder = !_sortRoutesReverseOrder;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Icon(
                            _sortRoutesReverseOrder 
                                ? Icons.sort : Icons.sort,
                            size: 16,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text('Все', style: TextStyle(fontSize: 12)),
                      Switch(
                        value: _allRoutesVisible,
                        onChanged: toggleAllRoutes,
                        activeColor: Colors.blue,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ],
                  ),
                ],
              ),
              
              // Кнопка для просмотра всех маршрутов
              GestureDetector(
                onTap: centerOnAllRoutes,
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: Colors.blue.withOpacity(0.5),
                      width: 1,
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.map,
                        size: 16,
                        color: Colors.blue,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Показать все маршруты',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Информация о количестве маршрутов
              Text(
                'Всего маршрутов: ${_routeNames.length}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              
              // Контейнер со скроллом для большого количества маршрутов
              Container(
                height: 150, // Фиксированная высота для списка маршрутов
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: displayedRoutes.length,
                  itemBuilder: (context, index) {
                    final routeName = displayedRoutes[index];
                    final routeColor = _getRouteColor(routeName);
                    
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: routeColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Маршрут $routeName',
                                    style: const TextStyle(fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _routeVisibility[routeName] ?? true,
                            activeColor: routeColor,
                            onChanged: (value) {
                              setState(() {
                                _routeVisibility[routeName] = value;
                              });
                              updateVisibleMarkersAndPolylines();
                            },
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  // Получение цвета для маршрута на основе его имени
  Color _getRouteColor(String routeName) {
    // Генерируем цвет на основе хеша имени маршрута для уникальности
    final hash = routeName.hashCode;
    final r = (hash & 0xFF0000) >> 16;
    final g = (hash & 0x00FF00) >> 8;
    final b = hash & 0x0000FF;
    
    // Обеспечиваем минимальную яркость цвета
    final minBrightness = 100; // Минимальная яркость 0-255
    final brightness = (r * 0.299 + g * 0.587 + b * 0.114).round();
    
    if (brightness < minBrightness) {
      // Если цвет слишком тёмный, осветляем
      const factor = 1.5;
      return Color.fromARGB(
        255,
        (r * factor).clamp(0, 255).round(),
        (g * factor).clamp(0, 255).round(),
        (b * factor).clamp(0, 255).round(),
      );
    }
    
    return Color.fromARGB(255, r, g, b);
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

  // Включение/выключение всех маршрутов
  void toggleAllRoutes(bool value) {
    setState(() {
      _allRoutesVisible = value;
      for (final routeName in _routeNames) {
        _routeVisibility[routeName] = value;
      }
    });
    updateVisibleMarkersAndPolylines();
  }

  // Вычисление границ маршрута
  LatLngBounds? calculateRouteBounds(String routeName) {
    final markers = _routeMarkers[routeName] ?? [];
    final polylines = _routePolylines[routeName] ?? [];
    
    if (markers.isEmpty && polylines.isEmpty) {
      return null;
    }
    
    List<LatLng> points = [];
    
    // Добавляем точки из маркеров
    for (final marker in markers) {
      points.add(marker.point);
    }
    
    // Добавляем точки из полилиний
    for (final polyline in polylines) {
      points.addAll(polyline.points);
    }
    
    if (points.isEmpty) {
      return null;
    }
    
    // Находим крайние точки для определения границ
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    
    for (var i = 1; i < points.length; i++) {
      final point = points[i];
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }
    
    return LatLngBounds(
      LatLng(minLat, minLng),
      LatLng(maxLat, maxLng),
    );
  }
  
  // Центрирование карты на маршруте
  void centerOnRoute(String routeName) {
    final bounds = calculateRouteBounds(routeName);
    if (bounds != null) {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(50),
        ),
      );
    }
  }

  // Центрирование карты на всех маршрутах
  void centerOnAllRoutes() {
    // Собираем все точки из всех видимых маршрутов
    List<LatLng> allPoints = [];
    
    for (final routeName in _routeNames) {
      if (_routeVisibility[routeName] == true) {
        final markers = _routeMarkers[routeName] ?? [];
        final polylines = _routePolylines[routeName] ?? [];
        
        // Добавляем точки из маркеров
        for (final marker in markers) {
          allPoints.add(marker.point);
        }
        
        // Добавляем точки из полилиний
        for (final polyline in polylines) {
          allPoints.addAll(polyline.points);
        }
      }
    }
    
    if (allPoints.isEmpty) {
      return;
    }
    
    // Находим крайние точки для определения границ
    double minLat = allPoints.first.latitude;
    double maxLat = allPoints.first.latitude;
    double minLng = allPoints.first.longitude;
    double maxLng = allPoints.first.longitude;
    
    for (var i = 1; i < allPoints.length; i++) {
      final point = allPoints[i];
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }
    
    final bounds = LatLngBounds(
      LatLng(minLat, minLng),
      LatLng(maxLat, maxLng),
    );
    
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(50),
      ),
    );
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
