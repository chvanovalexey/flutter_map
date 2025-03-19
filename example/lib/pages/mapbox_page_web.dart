// ignore_for_file: avoid_web_libraries_in_flutter
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'dart:ui_web' as ui_web;
import 'dart:html';
import 'dart:js' as js;
import 'package:flutter_map_example/widgets/drawer/floating_menu_button.dart';
import 'package:flutter_map_example/widgets/drawer/menu_drawer.dart';
import 'package:flutter/services.dart'; // Импорт для работы с AssetBundle
import 'dart:convert'; // Импорт для работы с JSON
import 'dart:async'; // Импорт для работы с таймерами

class MapboxPageWeb extends StatefulWidget {
  static const String route = '/mapbox_page';

  const MapboxPageWeb({super.key});

  @override
  State<MapboxPageWeb> createState() => _MapboxPageWebState();
}

class _MapboxPageWebState extends State<MapboxPageWeb> with SingleTickerProviderStateMixin {
  // Mapbox token
  static const String mapboxAccessToken = 'pk.eyJ1IjoiY2h2YW5vdmFsZXhleSIsImEiOiJjbThlaGR5YXgwMWdpMmpzZG1hZm9weHFjIn0.y9kFEPItcETr0or609EYhg';
  
  // Переменные для загрузки маршрутов
  bool isLoading = false;
  String? error;
  final Map<String, bool> _routeVisibility = {};
  final List<String> _routeNames = [];
  bool _showRoutesPanel = false;
  bool _allRoutesVisible = true;
  
  // Режим загрузки маршрутов
  bool _loadByLayers = true; // По умолчанию загружаем по слоям, как сейчас
  
  // Информация о прогрессе загрузки
  int _totalRoutes = 0;
  int _loadedRoutes = 0;
  String _currentLoadingRoute = '';
  bool _sortRoutesReverseOrder = false;
  
  // Переменные для отслеживания производительности
  late Ticker _ticker;
  int _fps = 0;
  double _frameTime = 0.0;
  int _jankScore = 0;
  int _frameCount = 0;
  int _jankCount = 0;
  Stopwatch _stopwatch = Stopwatch();
  DateTime _lastUpdate = DateTime.now();
  
  // ID элемента для внедрения Mapbox
  final String _mapElementId = 'mapbox-container';
  
  @override
  void initState() {
    super.initState();
    
    // Инициализация отслеживания производительности
    _stopwatch.start();
    _ticker = createTicker(_onTick)..start();
    
    // Инициализация карты после построения дерева виджетов
    // и после небольшой задержки, чтобы DOM успел обновиться
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 500), () {
        _initMapboxGlJs();
        // Маршруты загружаем только после полной инициализации карты
        // Это произойдет в обработчике события 'load' в JS
      });
    });
  }
  
  void _initMapboxGlJs() {
    // Добавляем отладочное сообщение
    print('Начало инициализации Mapbox GL JS');
    
    try {
      // Проверка доступности Mapbox GL JS
      final jsCheck = js.context.hasProperty('mapboxgl');
      print('mapboxgl доступен в JS: $jsCheck');
      
      if (!jsCheck) {
        print('ОШИБКА: Mapbox GL JS не загружен! Проверьте скрипты в index.html');
        setState(() {
          error = 'Mapbox GL JS не загружен. Проверьте подключение скриптов.';
        });
        return;
      }
      
      // Инициализация Mapbox GL JS
      js.context.callMethod('eval', ['''
        (function() {
          try {
            console.log('Инициализация карты Mapbox...');
            
            // Очищаем контейнер, если там уже есть карта
            if (window.mapboxMap) {
              window.mapboxMap.remove();
              window.mapboxMap = null;
            }
            
            mapboxgl.accessToken = '$mapboxAccessToken';
            
            // Получаем контейнер по ID
            var container = document.getElementById('$_mapElementId');
            
            // Проверяем, существует ли контейнер
            if (!container) {
              console.error('Контейнер $_mapElementId не найден!');
              return;
            }
            
            // Очищаем контейнер от всех дочерних элементов, кроме стилей
            // Сохраняем стили
            var styles = container.querySelector('style');
            container.innerHTML = '';
            if (styles) {
              container.appendChild(styles);
            }
            
            console.log('Создание карты Mapbox в контейнере:', container);
            
            // Создаем карту
            var map = new mapboxgl.Map({
              container: container,
              style: 'mapbox://styles/mapbox/streets-v12',
              center: [-74.5, 40.0],
              zoom: 9,
              attributionControl: true
            });
            
            // Добавляем обработку событий
            map.on('error', function(e) {
              console.error('Ошибка карты Mapbox:', e);
            });
            
            // Добавляем событие, которое скрывает индикатор загрузки, когда карта загружена
            map.on('load', function() {
              console.log('Карта загружена успешно');
              
              // Скрываем индикатор загрузки, если он есть
              var loadingIndicator = container.querySelector('div[style*="z-index: 100"]');
              if (loadingIndicator) {
                loadingIndicator.style.display = 'none';
              }
              
              // Создаем глобальный объект для хранения информации о маршрутах
              window.routeLayers = {};
              
              // Инициализируем маршруты только после полной загрузки карты
              try {
                console.log('Вызываем Flutter метод для загрузки маршрутов');
                if (window.flutterMapboxReady) {
                  // Даем карте время полностью загрузиться
                  setTimeout(function() {
                    window.flutterMapboxReady();
                  }, 500);
                } else {
                  console.error('Flutter колбэк не найден!');
                }
              } catch (callbackError) {
                console.error('Ошибка при вызове колбэка Flutter:', callbackError);
              }
              
              // Добавление источника 3D зданий
              try {
                map.addSource('composite', {
                  'type': 'vector',
                  'url': 'mapbox://mapbox.mapbox-streets-v8'
                });
                
                // Добавление слоя с 3D зданиями
                map.addLayer({
                  'id': '3d-buildings',
                  'source': 'composite',
                  'source-layer': 'building',
                  'filter': ['==', 'extrude', 'true'],
                  'type': 'fill-extrusion',
                  'minzoom': 15,
                  'paint': {
                    'fill-extrusion-color': '#aaa',
                    'fill-extrusion-height': [
                      'interpolate', ['linear'], ['zoom'],
                      15, 0,
                      15.05, ['get', 'height']
                    ],
                    'fill-extrusion-base': [
                      'interpolate', ['linear'], ['zoom'],
                      15, 0,
                      15.05, ['get', 'min_height']
                    ],
                    'fill-extrusion-opacity': 0.6
                  }
                });
              } catch (sourceError) {
                console.warn('Не удалось добавить 3D здания:', sourceError);
              }
              
              // Обработка кликов на карте
              map.on('click', function(e) {
                console.log('Клик по карте в координатах:', e.lngLat);
              });
            });
            
            // Отслеживаем событие стиля
            map.on('style.load', function() {
              console.log('Стиль карты загружен - готов к добавлению GeoJSON данных');
            });
            
            // Добавление элементов управления
            map.addControl(new mapboxgl.NavigationControl());
            map.addControl(new mapboxgl.FullscreenControl());
            
            // Добавление масштабной линейки
            map.addControl(new mapboxgl.ScaleControl({
              maxWidth: 100,
              unit: 'metric'
            }));
            
            // Глобальная переменная для доступа из Flutter
            window.mapboxMap = map;
            
            // Функция для проверки готовности карты
            window.isMapReady = function() {
              return window.mapboxMap && window.mapboxMap.isStyleLoaded();
            };
            
            console.log('Инициализация карты завершена');
          } catch (error) {
            console.error('Ошибка инициализации карты:', error);
          }
        })();
      ''']);
      
      print('JS код для инициализации Mapbox выполнен');
      
      // Настраиваем JS колбэк для загрузки маршрутов после инициализации карты
      js.context['flutterMapboxReady'] = js.allowInterop(() {
        print('JS сообщил о готовности карты Mapbox');
        
        // Проверяем, действительно ли карта готова
        final isMapReady = js.context.callMethod('eval', ['(function() { return window.isMapReady ? window.isMapReady() : false; })()']);
        if (isMapReady == true) {
          print('Карта действительно готова, загружаем маршруты');
          loadAllRoutes();
        } else {
          print('Карта еще не полностью готова, ждем еще 1 секунду');
          Future.delayed(const Duration(seconds: 1), () {
            print('Повторная проверка готовности карты');
            loadAllRoutes();
          });
        }
      });
      
    } catch (e) {
      print('Ошибка при инициализации Mapbox GL JS: $e');
      setState(() {
        error = 'Ошибка инициализации карты: $e';
      });
    }
  }
  
  @override
  void dispose() {
    _ticker.dispose();
    _stopwatch.stop();
    // Очистка JS ресурсов
    js.context.callMethod('eval', ['(function() { if (window.mapboxMap) { window.mapboxMap.remove(); } })();']);
    super.dispose();
  }
  
  // Загрузка всех GeoJSON маршрутов из папки assets/sample-geojson/
  Future<void> loadAllRoutes() async {
    try {
      setState(() {
        isLoading = true;
        error = null;
      });
      
      print('Начинаем загрузку GeoJSON маршрутов...');
      print('Режим загрузки: ${_loadByLayers ? "по слоям" : "целиком"}');
      
      // Проверка, что Mapbox карта инициализирована
      final mapInitialized = js.context.callMethod('eval', ['(function() { return window.mapboxMap && window.mapboxMap.isStyleLoaded(); })()']);
      if (mapInitialized != true) {
        print('ПРЕДУПРЕЖДЕНИЕ: Карта Mapbox еще не полностью инициализирована. Маршруты могут не отобразиться.');
      }
      
      // Сначала добавляем тестовый маршрут, чтобы гарантировать, что хотя бы один маршрут отобразится
      print('Добавляем тестовый маршрут перед загрузкой GeoJSON файлов...');
      await _addTestRoute();
      
      // Загружаем список всех доступных файлов через AssetManifest
      try {
        final manifestContent = await rootBundle.loadString('AssetManifest.json');
        print('AssetManifest успешно загружен, размер: ${manifestContent.length}');
        final Map<String, dynamic> manifestMap = json.decode(manifestContent) as Map<String, dynamic>;
        
        // Добавляем отладочные сообщения - выводим ПОЛНЫЙ список ассетов для диагностики
        print('====================== СПИСОК ВСЕХ АССЕТОВ ======================');
        manifestMap.keys.forEach((key) => print(key));
        print('===================================================================');
        
        // Проверяем разные варианты путей для GeoJSON файлов
        final geoJsonFiles1 = manifestMap.keys
            .where((key) => key.startsWith('assets/sample-geojson/') && key.endsWith('.geojson'))
            .toList();
            
        final geoJsonFiles2 = manifestMap.keys
            .where((key) => key.contains('sample-geojson') && key.endsWith('.geojson'))
            .toList();
        
        final geoJsonFiles3 = manifestMap.keys
            .where((key) => key.endsWith('.geojson'))
            .toList();
            
        print('GeoJSON файлы с путем assets/sample-geojson/: ${geoJsonFiles1.length}');
        print('GeoJSON файлы с подстрокой sample-geojson: ${geoJsonFiles2.length}');
        print('Все GeoJSON файлы: ${geoJsonFiles3.length}');
        
        // Выбираем наиболее подходящий вариант
        List<String> geoJsonFiles = geoJsonFiles1;
        if (geoJsonFiles.isEmpty) {
          geoJsonFiles = geoJsonFiles2;
          if (geoJsonFiles.isEmpty) {
            geoJsonFiles = geoJsonFiles3;
          }
        }
        
        if (geoJsonFiles.isEmpty) {
          print('ПРЕДУПРЕЖДЕНИЕ: GeoJSON файлы не найдены в директории assets/sample-geojson/.');
          print('Проверьте, что GeoJSON файлы добавлены в pubspec.yaml в секцию assets.');
          
          // Попробуем найти все geojson файлы в assets
          final allGeoJsonFiles = manifestMap.keys
              .where((key) => key.endsWith('.geojson'))
              .toList();
          
          if (allGeoJsonFiles.isNotEmpty) {
            print('Найдены другие GeoJSON файлы вне директории sample-geojson: ${allGeoJsonFiles.join(", ")}');
          } else {
            print('В манифесте вообще нет GeoJSON файлов.');
          }
          
          setState(() {
            isLoading = false;
            // Не устанавливаем ошибку, т.к. уже добавили тестовый маршрут
          });
          return;
        }
        
        print('Найдено ${geoJsonFiles.length} GeoJSON файлов: ${geoJsonFiles.join(', ')}');
        
        // Сортируем файлы по имени для более предсказуемого порядка
        geoJsonFiles.sort();
        
        // Устанавливаем общее количество маршрутов для прогресса
        setState(() {
          _totalRoutes = geoJsonFiles.length;
          _loadedRoutes = 0;
        });
        
        if (_loadByLayers) {
          // Загружаем по слоям (текущий режим)
          // Размер пакета для загрузки маршрутов (сколько маршрутов обрабатывать параллельно)
          const batchSize = 3; // Уменьшаем размер пакета для более стабильной загрузки
          
          // Загружаем файлы пакетами для улучшения производительности
          for (var i = 0; i < geoJsonFiles.length; i += batchSize) {
            final end = (i + batchSize < geoJsonFiles.length) ? i + batchSize : geoJsonFiles.length;
            final batch = geoJsonFiles.sublist(i, end);
            
            print('Загрузка пакета маршрутов ${i ~/ batchSize + 1}/${(geoJsonFiles.length / batchSize).ceil()}: ${batch.join(', ')}');
            
            // Загружаем пакет файлов последовательно для большей стабильности
            for (final filePath in batch) {
              // Получаем имя файла без пути и расширения
              final fileName = filePath.split('/').last;
              final routeName = fileName.replaceAll('.geojson', '');
              
              setState(() {
                if (!_routeNames.contains(routeName)) {
                  _routeNames.add(routeName);
                  _routeVisibility[routeName] = true;
                }
                _currentLoadingRoute = 'Маршрут $routeName';
              });
              
              try {
                await loadRouteFromFile(filePath, routeName);
                print('Маршрут $routeName успешно загружен');
              } catch (e) {
                print('Ошибка при загрузке маршрута $routeName: $e');
              }
              
              setState(() {
                _loadedRoutes++;
              });
              
              // Даем небольшую паузу между загрузкой маршрутов, чтобы браузер мог обработать данные
              await Future.delayed(const Duration(milliseconds: 100));
            }
          }
        } else {
          // Загружаем GeoJSON целиком
          print('Загрузка всех маршрутов целиком...');
          await _loadAllRoutesAsOneLayer(geoJsonFiles);
        }
        
        // Центрируем карту на всех маршрутах
        _centerOnAllRoutes();
        
        setState(() {
          isLoading = false;
          _currentLoadingRoute = '';
        });
        
        print('Загрузка маршрутов завершена: загружено $_loadedRoutes из $_totalRoutes');
      } catch (e) {
        setState(() {
          isLoading = false;
          error = 'Ошибка загрузки маршрутов: $e';
        });
        print('Ошибка при загрузке GeoJSON маршрутов: $e');
        
        // Если произошла ошибка, добавляем тестовый маршрут
        try {
          await _addTestRoute();
        } catch (e) {
          print('Не удалось добавить тестовый маршрут после ошибки: $e');
        }
      }
    } catch (e) {
      setState(() {
        isLoading = false;
        error = 'Ошибка загрузки маршрутов: $e';
      });
      print('Ошибка при загрузке GeoJSON маршрутов: $e');
      
      // Если произошла ошибка, добавляем тестовый маршрут
      try {
        await _addTestRoute();
      } catch (e) {
        print('Не удалось добавить тестовый маршрут после ошибки: $e');
      }
    }
  }
  
  // Загрузка и добавление маршрута из файла
  Future<void> loadRouteFromFile(String filePath, String routeName) async {
    try {
      print('Загружаю маршрут из файла: $filePath');
      
      // Загружаем JSON-данные из файла
      try {
        final geoJsonString = await rootBundle.loadString(filePath);
        print('GeoJSON строка загружена, длина: ${geoJsonString.length}');
        print('Первые 100 символов GeoJSON: ${geoJsonString.substring(0, geoJsonString.length > 100 ? 100 : geoJsonString.length)}...');
        
        // Проверяем, можно ли распарсить JSON
        try {
          final geoJsonData = json.decode(geoJsonString);
          print('JSON успешно декодирован: ${geoJsonData.runtimeType}');
          
          if (geoJsonData is Map && !(geoJsonData as Map).containsKey('features')) {
            print('ПРЕДУПРЕЖДЕНИЕ: GeoJSON не содержит ключ "features": $geoJsonData');
          } else {
            print('Количество features: ${geoJsonData['features'].length}');
          }
          
          // Получаем цвет для маршрута
          final routeColor = _getRouteColor(routeName);
          final routeColorHex = _colorToHex(routeColor);
          
          // Проверяем, видим ли этот маршрут
          final isVisible = _routeVisibility[routeName] ?? true;
          
          // Преобразуем GeoJSON в строку JSON без экранирования для JavaScript
          final jsonString = json.encode(geoJsonData).replaceAll("'", "\\'").replaceAll(r"$", r"\$");
          
          print('Экранированная JSON строка подготовлена для JS');
          
          // Добавляем маршрут на карту с помощью Mapbox GL JS
          js.context.callMethod('eval', ['''
            (function() {
              try {
                console.log('Начало добавления маршрута $routeName на карту Mapbox');
                
                if (!window.mapboxMap) {
                  console.error('Карта Mapbox не инициализирована!');
                  return;
                }
                
                // Проверяем, готова ли карта принимать источники
                if (!window.mapboxMap.isStyleLoaded()) {
                  console.error('Стиль карты еще не загружен для маршрута $routeName. Ожидаем загрузки...');
                  
                  // Если стиль не загружен, откладываем добавление маршрута
                  // до события загрузки стиля
                  var routeName = '$routeName';
                  var jsonData = '$jsonString';
                  var routeColor = '$routeColorHex';
                  var isVisible = $isVisible;
                  
                  window.mapboxMap.once('styledata', function() {
                    console.log('Стиль карты загружен, добавляем отложенный маршрут ' + routeName);
                    tryAddRoute(routeName, jsonData, routeColor, isVisible);
                  });
                  
                  return;
                }
                
                tryAddRoute('$routeName', '$jsonString', '$routeColorHex', $isVisible);
                
                function tryAddRoute(routeName, jsonDataString, routeColor, isVisible) {
                  try {
                    // Удаляем предыдущий источник и слой с таким же именем, если они существуют
                    var sourceId = 'source-' + routeName;
                    var layerId = 'layer-' + routeName;
                    var markerLayerId = 'markers-' + routeName;
                    
                    try {
                      // Проверяем существование слоев перед удалением
                      if (window.mapboxMap.getLayer(layerId)) {
                        window.mapboxMap.removeLayer(layerId);
                        console.log('Удален существующий слой линий:', layerId);
                      }
                      if (window.mapboxMap.getLayer(markerLayerId)) {
                        window.mapboxMap.removeLayer(markerLayerId);
                        console.log('Удален существующий слой маркеров:', markerLayerId);
                      }
                      if (window.mapboxMap.getSource(sourceId)) {
                        window.mapboxMap.removeSource(sourceId);
                        console.log('Удален существующий источник:', sourceId);
                      }
                    } catch (removeError) {
                      console.warn('Ошибка при удалении предыдущих слоев:', removeError);
                    }
                    
                    // Парсим JSON данные из строки
                    var geojsonData;
                    try {
                      geojsonData = JSON.parse(jsonDataString);
                      console.log('GeoJSON данные успешно распарсены');
                    } catch (parseError) {
                      console.error('Ошибка при парсинге JSON данных:', parseError);
                      console.log('Первые 100 символов JSON строки:', jsonDataString.substring(0, 100));
                      return;
                    }
                    
                    // Проверяем полученные данные
                    if (typeof geojsonData !== 'object' || !geojsonData.features || !Array.isArray(geojsonData.features)) {
                      console.error('Некорректный формат GeoJSON: отсутствует массив features');
                      return;
                    }
                    
                    // Создаем источник из GeoJSON данных
                    try {
                      window.mapboxMap.addSource(sourceId, {
                        type: 'geojson',
                        data: geojsonData
                      });
                      console.log('Добавлен источник для маршрута ' + routeName, sourceId);
                    } catch (sourceError) {
                      console.error('Ошибка при добавлении источника:', sourceError);
                      return;
                    }
                    
                    // Отслеживаем маркеры, которые нужно создать
                    var markerFeatures = [];
                    var lineFeatures = [];
                    
                    // Разделяем данные на маркеры и линии
                    geojsonData.features.forEach(function(feature) {
                      if (feature.geometry.type === 'Point') {
                        markerFeatures.push(feature);
                      } else if (feature.geometry.type === 'LineString') {
                        lineFeatures.push(feature);
                      }
                    });
                    
                    console.log('Найдено точек:', markerFeatures.length, 'и линий:', lineFeatures.length);
                    
                    // Добавляем линии как слой
                    if (lineFeatures.length > 0) {
                      try {
                        window.mapboxMap.addLayer({
                          id: layerId,
                          type: 'line',
                          source: sourceId,
                          layout: {
                            'line-join': 'round',
                            'line-cap': 'round',
                            'visibility': isVisible ? 'visible' : 'none'
                          },
                          paint: {
                            'line-color': ['coalesce', ['get', 'stroke'], routeColor],
                            'line-width': ['coalesce', ['get', 'stroke-width'], 3],
                            'line-opacity': 0.8
                          },
                          filter: ['==', ['geometry-type'], 'LineString']
                        });
                        console.log('Добавлен слой линий для маршрута ' + routeName, layerId);
                      } catch (lineError) {
                        console.error('Ошибка при добавлении слоя линий:', lineError);
                      }
                    }
                    
                    // Для точек добавляем кружки вместо символьного слоя
                    if (markerFeatures.length > 0) {
                      try {
                        window.mapboxMap.addLayer({
                          id: markerLayerId,
                          type: 'circle', // Используем circle вместо symbol
                          source: sourceId,
                          layout: {
                            'visibility': isVisible ? 'visible' : 'none'
                          },
                          paint: {
                            'circle-radius': 6,
                            'circle-color': routeColor,
                            'circle-stroke-width': 2,
                            'circle-stroke-color': '#ffffff'
                          },
                          filter: ['==', ['geometry-type'], 'Point']
                        });
                        console.log('Добавлен слой маркеров для маршрута ' + routeName, markerLayerId);
                        
                        // Добавляем слой с подписями
                        var labelLayerId = 'labels-' + routeName;
                        window.mapboxMap.addLayer({
                          id: labelLayerId,
                          type: 'symbol',
                          source: sourceId,
                          layout: {
                            'text-field': ['get', 'name'],
                            'text-font': ['Open Sans Semibold', 'Arial Unicode MS Bold'],
                            'text-offset': [0, 1.5],
                            'text-anchor': 'top',
                            'visibility': isVisible ? 'visible' : 'none'
                          },
                          paint: {
                            'text-color': '#ffffff',
                            'text-halo-color': '#000000',
                            'text-halo-width': 1
                          },
                          filter: ['==', ['geometry-type'], 'Point']
                        });
                        
                        // Добавляем ID слоя подписей
                        routeInfo.layerIds.push(labelLayerId);
                      } catch (markerError) {
                        console.error('Ошибка при добавлении слоя маркеров:', markerError);
                      }
                    }
                    
                    // Сохраняем информацию о маршрутах в глобальный объект для удобного управления
                    if (!window.routeLayers) {
                      window.routeLayers = {};
                    }
                    
                    window.routeLayers[routeName] = {
                      sourceId: sourceId,
                      layerIds: [layerId, markerLayerId, labelLayerId],
                      visible: isVisible
                    };
                    
                    console.log('Маршрут ' + routeName + ' успешно загружен');
                  } catch (error) {
                    console.error('Общая ошибка при добавлении маршрута ' + routeName + ':', error);
                  }
                }
              } catch (error) {
                console.error('Ошибка при загрузке маршрута $routeName:', error);
              }
            })();
          ''']);
          
          print('JavaScript код для добавления маршрута $routeName выполнен');
        } catch (parseError) {
          print('Ошибка при парсинге JSON: $parseError');
          
          // Если не удалось распарсить JSON, добавляем тестовый маршрут
          if (routeName == 'sample-route') {
            print('Пропускаем добавление тестового маршрута, так как он уже загружается');
          } else {
            print('Пробуем добавить тестовый маршрут вместо $routeName');
            await _addTestRoute();
          }
        }
      } catch (e) {
        print('Ошибка при загрузке маршрута $routeName: $e');
        
        // В случае общей ошибки добавляем тестовый маршрут
        if (routeName != 'sample-route') {
          print('Пробуем добавить тестовый маршрут вместо $routeName после ошибки');
          await _addTestRoute();
        }
      }
    } catch (e) {
      print('Ошибка при загрузке маршрута $routeName: $e');
      
      // В случае общей ошибки добавляем тестовый маршрут
      if (routeName != 'sample-route') {
        print('Пробуем добавить тестовый маршрут вместо $routeName после ошибки');
        await _addTestRoute();
      }
    }
  }
  
  // Добавление тестового маршрута для отладки
  Future<void> _addTestRoute() async {
    try {
      final routeName = 'sample-route';
      final routeColor = _getRouteColor(routeName);
      final routeColorHex = _colorToHex(routeColor);
      
      // Тестовый GeoJSON с простой линией и точкой
      final testGeoJson = {
        "type": "FeatureCollection",
        "features": [
          {
            "type": "Feature",
            "properties": {
              "name": "Тестовая точка",
              "marker-color": "#7e7e7e",
              "marker-symbol": "harbor"
            },
            "geometry": {
              "type": "Point",
              "coordinates": [-74.5, 40.0]
            }
          },
          {
            "type": "Feature",
            "properties": {
              "name": "Тестовая линия",
              "stroke": "#ff0000",
              "stroke-width": 3
            },
            "geometry": {
              "type": "LineString",
              "coordinates": [
                [-74.5, 40.0],
                [-74.6, 40.1],
                [-74.7, 40.05],
                [-74.8, 40.15]
              ]
            }
          }
        ]
      };
      
      // Добавляем имя маршрута в список, если его там еще нет
      setState(() {
        if (!_routeNames.contains(routeName)) {
          _routeNames.add(routeName);
          _routeVisibility[routeName] = true;
        }
      });
      
      // Конвертируем в строку
      final jsonString = json.encode(testGeoJson).replaceAll("'", "\\'").replaceAll(r"$", r"\$");
      
      print('Добавляю тестовый маршрут с данными: ${jsonString.substring(0, 100)}...');
      
      // Выполняем JavaScript код для добавления маршрута
      js.context.callMethod('eval', ['''
        (function() {
          try {
            console.log('Добавление тестового маршрута');
            
            if (!window.mapboxMap) {
              console.error('Карта Mapbox не инициализирована!');
              return;
            }
            
            // Проверяем, готова ли карта принимать источники
            if (!window.mapboxMap.isStyleLoaded()) {
              console.error('Стиль карты еще не загружен. Ожидаем загрузки...');
              
              window.mapboxMap.once('styledata', function() {
                console.log('Стиль карты загружен, добавляем тестовый маршрут');
                addTestRoute();
              });
              
              return;
            }
            
            addTestRoute();
            
            function addTestRoute() {
              try {
                var routeName = '$routeName';
                var sourceId = 'source-test-route';
                var layerId = 'layer-test-route';
                var markerLayerId = 'markers-test-route';
                
                // Удаляем предыдущие слои, если они существуют
                try {
                  if (window.mapboxMap.getLayer(layerId)) {
                    window.mapboxMap.removeLayer(layerId);
                  }
                  if (window.mapboxMap.getLayer(markerLayerId)) {
                    window.mapboxMap.removeLayer(markerLayerId);
                  }
                  if (window.mapboxMap.getSource(sourceId)) {
                    window.mapboxMap.removeSource(sourceId);
                  }
                } catch (e) {
                  console.warn('Ошибка при удалении предыдущих слоев:', e);
                }
                
                // Парсим тестовые данные
                var testData = JSON.parse('$jsonString');
                
                // Добавляем источник
                window.mapboxMap.addSource(sourceId, {
                  type: 'geojson',
                  data: testData
                });
                
                // Добавляем слой линий
                window.mapboxMap.addLayer({
                  id: layerId,
                  type: 'line',
                  source: sourceId,
                  layout: {
                    'line-join': 'round',
                    'line-cap': 'round',
                    'visibility': 'visible'
                  },
                  paint: {
                    'line-color': ['coalesce', ['get', 'stroke'], '$routeColorHex'],
                    'line-width': ['coalesce', ['get', 'stroke-width'], 3],
                    'line-opacity': 0.8
                  },
                  filter: ['==', ['geometry-type'], 'LineString']
                });
                
                // Добавляем слой маркеров
                window.mapboxMap.addLayer({
                  id: markerLayerId,
                  type: 'circle', // Используем circle вместо symbol
                  source: sourceId,
                  layout: {
                    'visibility': 'visible'
                  },
                  paint: {
                    'circle-radius': 6,
                    'circle-color': '$routeColorHex',
                    'circle-stroke-width': 2,
                    'circle-stroke-color': '#ffffff'
                  },
                  filter: ['==', ['geometry-type'], 'Point']
                });
                
                // Добавляем слой с подписями
                var labelLayerId = 'labels-test-route';
                window.mapboxMap.addLayer({
                  id: labelLayerId,
                  type: 'symbol',
                  source: sourceId,
                  layout: {
                    'text-field': ['get', 'name'],
                    'text-font': ['Open Sans Semibold', 'Arial Unicode MS Bold'],
                    'text-offset': [0, 1.5],
                    'text-anchor': 'top',
                    'visibility': 'visible'
                  },
                  paint: {
                    'text-color': '#ffffff',
                    'text-halo-color': '#000000',
                    'text-halo-width': 1
                  },
                  filter: ['==', ['geometry-type'], 'Point']
                });
                
                // Сохраняем информацию о маршруте
                if (!window.routeLayers) {
                  window.routeLayers = {};
                }
                
                window.routeLayers[routeName] = {
                  sourceId: sourceId,
                  layerIds: [layerId, markerLayerId, labelLayerId],
                  visible: true
                };
                
                // Центрируем карту на тестовом маршруте
                window.mapboxMap.flyTo({
                  center: [-74.65, 40.05],
                  zoom: 10,
                  duration: 2000
                });
                
                console.log('Тестовый маршрут успешно добавлен');
              } catch (error) {
                console.error('Ошибка при добавлении тестового маршрута:', error);
              }
            }
          } catch (error) {
            console.error('Общая ошибка при добавлении тестового маршрута:', error);
          }
        })();
      ''']);
      
      print('JavaScript код для добавления тестового маршрута выполнен');
    } catch (e) {
      print('Ошибка при добавлении тестового маршрута: $e');
    }
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
  
  // Конвертация Flutter Color в строку HEX для JavaScript
  String _colorToHex(Color color) {
    return '#${color.value.toRadixString(16).padLeft(8, '0').substring(2)}';
  }
  
  // Переключение видимости маршрута
  void _toggleRouteVisibility(String routeName, bool visible) {
    // Обновляем видимость в Flutter
    setState(() {
      _routeVisibility[routeName] = visible;
    });
    
    // Обновляем видимость в Mapbox через JavaScript
    js.context.callMethod('eval', ['''
      (function() {
        try {
          if (!window.mapboxMap || !window.routeLayers || !window.routeLayers['$routeName']) {
            console.error('Карта Mapbox или маршрут $routeName не инициализированы!');
            return;
          }
          
          var routeInfo = window.routeLayers['$routeName'];
          var visibility = ${visible ? "'visible'" : "'none'"};
          
          // Обновляем видимость всех слоев маршрута
          routeInfo.layerIds.forEach(function(layerId) {
            window.mapboxMap.setLayoutProperty(layerId, 'visibility', visibility);
          });
          
          routeInfo.visible = ${visible};
          console.log('Видимость маршрута $routeName изменена на: ' + ${visible});
        } catch (error) {
          console.error('Ошибка при изменении видимости маршрута $routeName:', error);
        }
      })();
    ''']);
  }
  
  // Включение/выключение всех маршрутов
  void _toggleAllRoutes(bool visible) {
    setState(() {
      _allRoutesVisible = visible;
      for (final routeName in _routeNames) {
        _routeVisibility[routeName] = visible;
      }
    });
    
    // Обновляем видимость всех маршрутов в Mapbox через JavaScript
    js.context.callMethod('eval', ['''
      (function() {
        try {
          if (!window.mapboxMap || !window.routeLayers) {
            console.error('Карта Mapbox или маршруты не инициализированы!');
            return;
          }
          
          var visibility = ${visible ? "'visible'" : "'none'"};
          
          // Проходим по всем маршрутам и обновляем их видимость
          Object.keys(window.routeLayers).forEach(function(routeName) {
            var routeInfo = window.routeLayers[routeName];
            routeInfo.layerIds.forEach(function(layerId) {
              window.mapboxMap.setLayoutProperty(layerId, 'visibility', visibility);
            });
            routeInfo.visible = ${visible};
          });
          
          console.log('Видимость всех маршрутов изменена на: ' + ${visible});
        } catch (error) {
          console.error('Ошибка при изменении видимости всех маршрутов:', error);
        }
      })();
    ''']);
  }
  
  // Добавление маркера на карту (пример вызова JS функций из Dart)
  void _addMarker() {
    print('Добавление маркера на карту');
    try {
      js.context.callMethod('eval', ['''
        (function() {
          try {
            console.log('Попытка добавить маркер на карту');
            if (window.mapboxMap) {
              new mapboxgl.Marker({color: "#FF0000"})
                .setLngLat([-74.5, 40.0])
                .setPopup(new mapboxgl.Popup({ offset: 25 })
                  .setHTML('<h3>Новый маркер</h3><p>Создан из Flutter</p>'))
                .addTo(window.mapboxMap);
              console.log('Маркер добавлен успешно');
            } else {
              console.error('Карта не инициализирована!');
            }
          } catch (error) {
            console.error('Ошибка при добавлении маркера:', error);
          }
        })();
      ''']);
    } catch (e) {
      print('Ошибка при вызове JS для добавления маркера: $e');
    }
  }
  
  // Включение/выключение 3D режима
  void _toggle3DMode() {
    print('Переключение 3D режима');
    try {
      js.context.callMethod('eval', ['''
        (function() {
          try {
            console.log('Попытка переключить 3D режим');
            if (window.mapboxMap) {
              var currentPitch = window.mapboxMap.getPitch();
              var newPitch = currentPitch > 0 ? 0 : 45;
              console.log('Изменение наклона с ' + currentPitch + ' на ' + newPitch);
              window.mapboxMap.easeTo({
                pitch: newPitch,
                bearing: newPitch > 0 ? 45 : 0,
                duration: 1000
              });
              console.log('3D режим переключен');
            } else {
              console.error('Карта не инициализирована!');
            }
          } catch (error) {
            console.error('Ошибка при переключении 3D режима:', error);
          }
        })();
      ''']);
    } catch (e) {
      print('Ошибка при вызове JS для переключения 3D режима: $e');
    }
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
  
  // Построение панели управления маршрутами
  Widget _buildRoutesPanel() {
    // Сортируем список маршрутов при необходимости
    final displayedRoutes = List<String>.from(_routeNames)
      ..sort((a, b) => _sortRoutesReverseOrder ? b.compareTo(a) : a.compareTo(b));
      
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
                  'Управление маршрутами',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(() => _showRoutesPanel = false),
                ),
              ],
            ),
            const Divider(),
            
            // Кнопка для просмотра всех маршрутов
            GestureDetector(
              onTap: _centerOnAllRoutes,
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
            
            // Индикатор общего управления маршрутами
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Всего маршрутов: ${_routeNames.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                Row(
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
                          _sortRoutesReverseOrder ? Icons.sort : Icons.sort,
                          size: 16,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text('Все', style: TextStyle(fontSize: 12)),
                    Switch(
                      value: _allRoutesVisible,
                      onChanged: _toggleAllRoutes,
                      activeColor: Colors.blue,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            if (_routeNames.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Нет загруженных маршрутов',
                    style: TextStyle(
                      color: Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              )
            else
              // Контейнер со скроллом для списка маршрутов
              Container(
                height: 200, // Фиксированная высота для списка маршрутов
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
                      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _centerOnRoute(routeName),
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
                          ),
                          Switch(
                            value: _routeVisibility[routeName] ?? true,
                            activeColor: routeColor,
                            onChanged: (value) => _toggleRouteVisibility(routeName, value),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  // Метод для центрирования на всех маршрутах
  void _centerOnAllRoutes() {
    try {
      js.context.callMethod('eval', ['''
        (function() {
          try {
            console.log('Отображение всех маршрутов');
            if (!window.mapboxMap || !window.routeLayers) {
              console.error('Карта Mapbox или маршруты не инициализированы!');
              return;
            }
            
            // Собираем все координаты из всех видимых маршрутов
            var bounds = new mapboxgl.LngLatBounds();
            var foundCoordinates = false;
            
            Object.keys(window.routeLayers).forEach(function(routeName) {
              var routeInfo = window.routeLayers[routeName];
              if (routeInfo.visible) {
                var source = window.mapboxMap.getSource(routeInfo.sourceId);
                if (source) {
                  var features = source._data.features;
                  features.forEach(function(feature) {
                    if (feature.geometry.type === 'Point') {
                      bounds.extend(feature.geometry.coordinates);
                      foundCoordinates = true;
                    } else if (feature.geometry.type === 'LineString') {
                      feature.geometry.coordinates.forEach(function(coord) {
                        bounds.extend(coord);
                        foundCoordinates = true;
                      });
                    }
                  });
                }
              }
            });
            
            if (foundCoordinates) {
              window.mapboxMap.fitBounds(bounds, {
                padding: 50,
                duration: 1000
              });
              console.log('Карта центрирована на всех маршрутах');
            } else {
              console.log('Нет видимых маршрутов для центрирования');
            }
          } catch (error) {
            console.error('Ошибка при центрировании на всех маршрутах:', error);
          }
        })();
      ''']);
    } catch (e) {
      print('Ошибка при вызове JS для центрирования на всех маршрутах: $e');
    }
  }
  
  // Метод для центрирования на конкретном маршруте
  void _centerOnRoute(String routeName) {
    try {
      js.context.callMethod('eval', ['''
        (function() {
          try {
            console.log('Отображение маршрута $routeName');
            if (!window.mapboxMap || !window.routeLayers || !window.routeLayers['$routeName']) {
              console.error('Карта Mapbox или маршрут $routeName не инициализирован!');
              return;
            }
            
            var routeInfo = window.routeLayers['$routeName'];
            var source = window.mapboxMap.getSource(routeInfo.sourceId);
            
            if (source) {
              var bounds = new mapboxgl.LngLatBounds();
              var foundCoordinates = false;
              
              var features = source._data.features;
              features.forEach(function(feature) {
                if (feature.geometry.type === 'Point') {
                  bounds.extend(feature.geometry.coordinates);
                  foundCoordinates = true;
                } else if (feature.geometry.type === 'LineString') {
                  feature.geometry.coordinates.forEach(function(coord) {
                    bounds.extend(coord);
                    foundCoordinates = true;
                  });
                }
              });
              
              if (foundCoordinates) {
                window.mapboxMap.fitBounds(bounds, {
                  padding: 50,
                  duration: 1000
                });
                console.log('Карта центрирована на маршруте $routeName');
              } else {
                console.log('Маршрут $routeName не содержит координат');
              }
            } else {
              console.error('Источник для маршрута $routeName не найден');
            }
          } catch (error) {
            console.error('Ошибка при центрировании на маршруте $routeName:', error);
          }
        })();
      ''']);
    } catch (e) {
      print('Ошибка при вызове JS для центрирования на маршруте $routeName: $e');
    }
  }

  // Удаляет все маршруты с карты
  void _clearAllRoutes() {
    print('Удаление всех маршрутов с карты');
    try {
      // Очищаем списки маршрутов в Dart
      setState(() {
        _routeNames.clear();
        _routeVisibility.clear();
      });
      
      // Удаляем все маршруты в JavaScript
      js.context.callMethod('eval', ['''
        (function() {
          try {
            console.log('Удаление всех маршрутов');
            if (!window.mapboxMap || !window.routeLayers) {
              console.error('Карта Mapbox или маршруты не инициализированы!');
              return;
            }
            
            // Проходим по всем маршрутам и удаляем их слои и источники
            Object.keys(window.routeLayers).forEach(function(routeName) {
              var routeInfo = window.routeLayers[routeName];
              
              // Удаляем все слои
              routeInfo.layerIds.forEach(function(layerId) {
                if (window.mapboxMap.getLayer(layerId)) {
                  window.mapboxMap.removeLayer(layerId);
                }
              });
              
              // Удаляем источник
              if (window.mapboxMap.getSource(routeInfo.sourceId)) {
                window.mapboxMap.removeSource(routeInfo.sourceId);
              }
            });
            
            // Очищаем объект routeLayers
            window.routeLayers = {};
            
            console.log('Все маршруты успешно удалены');
          } catch (error) {
            console.error('Ошибка при удалении маршрутов:', error);
          }
        })();
      ''']);
    } catch (e) {
      print('Ошибка при вызове JS для удаления маршрутов: $e');
    }
  }
  
  // Загрузка маршрутов по запросу
  Future<void> _loadRoutesOnDemand() async {
    // Сначала очищаем все существующие маршруты
    _clearAllRoutes();
    
    // Затем загружаем маршруты заново
    await loadAllRoutes();
  }

  // Метод для загрузки всех маршрутов целиком (как один слой)
  Future<void> _loadAllRoutesAsOneLayer(List<String> geoJsonFiles) async {
    try {
      print('Загрузка всех маршрутов в один слой...');
      
      // Создаем пустую структуру FeatureCollection для накопления всех объектов
      final combinedGeoJson = {
        'type': 'FeatureCollection',
        'features': <dynamic>[],
      };
      
      int fileCount = 0;
      
      for (final filePath in geoJsonFiles) {
        // Получаем имя файла без пути и расширения
        final fileName = filePath.split('/').last;
        final routeName = fileName.replaceAll('.geojson', '');
        
        setState(() {
          _currentLoadingRoute = 'Загрузка $routeName (${fileCount + 1}/${geoJsonFiles.length})';
        });
        
        try {
          // Загружаем JSON-данные из файла
          final geoJsonString = await rootBundle.loadString(filePath);
          final geoJsonData = json.decode(geoJsonString);
          
          if (geoJsonData is Map && geoJsonData.containsKey('features')) {
            // Добавляем атрибут источника к каждому объекту
            final features = geoJsonData['features'] as List?;
            if (features != null) {
              for (final feature in features) {
                // Добавляем информацию о файле-источнике в свойства объекта
                if (feature is Map && feature.containsKey('properties')) {
                  final properties = feature['properties'] as Map?;
                  if (properties != null) {
                    properties['source_file'] = routeName;
                  }
                }
                
                // Добавляем объект в общий список
                final featuresList = combinedGeoJson['features'] as List?;
                if (featuresList != null) {
                  featuresList.add(feature);
                }
              }
            }
          }
          
          // Добавляем имя маршрута в список
          if (!_routeNames.contains(routeName)) {
            setState(() {
              _routeNames.add(routeName);
              _routeVisibility[routeName] = true;
            });
          }
          
          fileCount++;
          setState(() {
            _loadedRoutes = fileCount;
          });
          
          // Даем небольшую паузу, чтобы UI мог обновиться
          await Future.delayed(const Duration(milliseconds: 50));
        } catch (e) {
          print('Ошибка при загрузке файла $filePath: $e');
        }
      }
      
      final featuresList = combinedGeoJson['features'] as List?;
      final featuresCount = featuresList?.length ?? 0;
      print('Загружено $featuresCount объектов из $fileCount файлов');
      
      // Если не удалось загрузить ни одного объекта, выходим
      if (featuresList == null || featuresList.isEmpty) {
        print('Не удалось загрузить ни одного объекта');
        return;
      }
      
      // Добавляем все объекты на карту как один слой
      setState(() {
        _currentLoadingRoute = 'Добавление объектов на карту...';
      });
      
      // Добавляем комбинированный GeoJSON на карту
      final jsonString = json.encode(combinedGeoJson).replaceAll("'", "\\'").replaceAll(r"$", r"\$");
      
      js.context.callMethod('eval', ['''
        (function() {
          try {
            console.log('Добавление комбинированного слоя на карту');
            
            if (!window.mapboxMap) {
              console.error('Карта Mapbox не инициализирована!');
              return;
            }
            
            // Создаем единый source и слои
            var sourceId = 'source-combined';
            var lineLayerId = 'layer-combined-lines';
            var pointLayerId = 'layer-combined-points';
            var labelLayerId = 'layer-combined-labels';
            
            // Удаляем существующие слои и источник, если они есть
            try {
              if (window.mapboxMap.getLayer(lineLayerId)) window.mapboxMap.removeLayer(lineLayerId);
              if (window.mapboxMap.getLayer(pointLayerId)) window.mapboxMap.removeLayer(pointLayerId);
              if (window.mapboxMap.getLayer(labelLayerId)) window.mapboxMap.removeLayer(labelLayerId);
              if (window.mapboxMap.getSource(sourceId)) window.mapboxMap.removeSource(sourceId);
            } catch (e) {
              console.warn('Ошибка при удалении старых слоев:', e);
            }
            
            // Добавляем источник данных
            window.mapboxMap.addSource(sourceId, {
              type: 'geojson',
              data: JSON.parse('$jsonString')
            });
            
            // Добавляем слой линий
            window.mapboxMap.addLayer({
              id: lineLayerId,
              type: 'line',
              source: sourceId,
              layout: {
                'line-join': 'round',
                'line-cap': 'round',
                'visibility': 'visible'
              },
              paint: {
                'line-color': ['coalesce', ['get', 'stroke'], '#3388ff'],
                'line-width': ['coalesce', ['get', 'stroke-width'], 3],
                'line-opacity': 0.8
              },
              filter: ['==', ['geometry-type'], 'LineString']
            });
            
            // Добавляем слой точек
            window.mapboxMap.addLayer({
              id: pointLayerId,
              type: 'circle',
              source: sourceId,
              layout: {
                'visibility': 'visible'
              },
              paint: {
                'circle-radius': 6,
                'circle-color': '#3388ff',
                'circle-stroke-width': 2,
                'circle-stroke-color': '#ffffff'
              },
              filter: ['==', ['geometry-type'], 'Point']
            });
            
            // Добавляем слой подписей
            window.mapboxMap.addLayer({
              id: labelLayerId,
              type: 'symbol',
              source: sourceId,
              layout: {
                'text-field': ['coalesce', ['get', 'name'], ['get', 'source_file']],
                'text-font': ['Open Sans Semibold', 'Arial Unicode MS Bold'],
                'text-offset': [0, 1.5],
                'text-anchor': 'top',
                'visibility': 'visible'
              },
              paint: {
                'text-color': '#ffffff',
                'text-halo-color': '#000000',
                'text-halo-width': 1
              },
              filter: ['==', ['geometry-type'], 'Point']
            });
            
            // Сохраняем информацию о слоях в глобальный объект
            if (!window.routeLayers) {
              window.routeLayers = {};
            }
            
            // Добавляем запись для "комбинированного" слоя
            window.routeLayers['combined'] = {
              sourceId: sourceId,
              layerIds: [lineLayerId, pointLayerId, labelLayerId],
              visible: true
            };
            
            console.log('Комбинированный слой успешно добавлен на карту');
          } catch (error) {
            console.error('Ошибка при добавлении комбинированного слоя:', error);
          }
        })();
      ''']);
      
      print('Комбинированный слой добавлен на карту');
      
      // Добавляем "combined" в список маршрутов
      setState(() {
        if (!_routeNames.contains("combined")) {
          _routeNames.add("combined");
          _routeVisibility["combined"] = true;
        }
      });
      
    } catch (e) {
      print('Ошибка при загрузке всех маршрутов в один слой: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Создаем HTML элемент для карты
    ui_web.platformViewRegistry.registerViewFactory(_mapElementId, (int viewId) {
      // Создаем DIV элемент с явно заданной высотой и шириной
      final mapElement = DivElement()
        ..id = _mapElementId
        ..style.width = '100%' 
        ..style.height = '100%'
        ..style.position = 'absolute'
        ..style.top = '0'
        ..style.left = '0'
        ..style.backgroundColor = '#e0f7fa';
      
      // Создаем индикатор загрузки программно, без использования innerHtml
      final loadingIndicator = DivElement()
        ..style.position = 'absolute'
        ..style.top = '0'
        ..style.left = '0'
        ..style.right = '0'
        ..style.bottom = '0'
        ..style.display = 'flex'
        ..style.alignItems = 'center'
        ..style.justifyContent = 'center'
        ..style.backgroundColor = 'rgba(255, 255, 255, 0.7)';
      
      final loadingBox = DivElement()
        ..style.textAlign = 'center'
        ..style.padding = '20px'
        ..style.backgroundColor = 'white'
        ..style.borderRadius = '8px';
      
      final loadingText = DivElement()
        ..text = 'Загрузка карты Mapbox...'
        ..style.marginTop = '10px';
      
      loadingBox.children.add(loadingText);
      loadingIndicator.children.add(loadingBox);
      mapElement.children.add(loadingIndicator);
      
      return mapElement;
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapbox GL JS (Web)'),
        actions: [
          // Кнопка переключения режима загрузки
          Tooltip(
            message: 'Переключение режима загрузки маршрутов:\n'
                    '- По слоям: каждый маршрут добавляется отдельным слоем\n'
                    '- Целиком: все маршруты объединяются в один слой',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Режим: ', style: TextStyle(fontSize: 12)),
                Text(
                  _loadByLayers ? 'По слоям' : 'Целиком', 
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)
                ),
                Switch(
                  value: _loadByLayers,
                  onChanged: (value) {
                    setState(() {
                      _loadByLayers = value;
                    });
                  },
                  activeColor: Colors.blue,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
          
          // Кнопка для загрузки маршрутов по запросу
          IconButton(
            icon: const Icon(Icons.cloud_download),
            tooltip: 'Загрузить маршруты (существующие маршруты будут удалены)',
            onPressed: _loadRoutesOnDemand,
          ),
          
          // Остальные кнопки
          IconButton(
            icon: const Icon(Icons.add_location),
            tooltip: 'Добавить маркер',
            onPressed: _addMarker,
          ),
          IconButton(
            icon: const Icon(Icons.view_in_ar),
            tooltip: 'Переключить 3D режим',
            onPressed: _toggle3DMode,
          ),
          // Кнопка для управления маршрутами
          IconButton(
            icon: const Icon(Icons.timeline),
            tooltip: 'Управление маршрутами',
            onPressed: () => setState(() => _showRoutesPanel = !_showRoutesPanel),
          ),
          // Добавляем кнопку для повторной инициализации карты
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Перезагрузить карту',
            onPressed: _initMapboxGlJs,
          ),
        ],
      ),
      drawer: const MenuDrawer(MapboxPageWeb.route),
      body: Stack(
        children: [
          // Добавляем контейнер фиксированного размера для карты
          SizedBox(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height - AppBar().preferredSize.height,
            child: HtmlElementView(
              viewType: _mapElementId,
            ),
          ),
          
          // Индикатор загрузки при загрузке маршрутов
          if (isLoading)
            _buildLoadingIndicator(),
          
          // Панель ошибки если есть
          if (error != null)
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      error!,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => setState(() => error = null),
                      child: const Text('Закрыть'),
                    ),
                  ],
                ),
              ),
            ),
          
          // Панель управления маршрутами (показываем только когда _showRoutesPanel = true)
          if (_showRoutesPanel)
            Positioned(
              right: 16,
              top: 70,
              width: 300,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.7,
                  ),
                  child: _buildRoutesPanel(),
                ),
              ),
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
} 