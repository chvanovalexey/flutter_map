// ignore_for_file: avoid_web_libraries_in_flutter
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'dart:ui_web' as ui_web;
import 'dart:html';
import 'dart:js' as js;
import 'package:flutter_map_example/widgets/drawer/floating_menu_button.dart';
import 'package:flutter_map_example/widgets/drawer/menu_drawer.dart';

class MapboxPageWeb extends StatefulWidget {
  static const String route = '/mapbox_page';

  const MapboxPageWeb({super.key});

  @override
  State<MapboxPageWeb> createState() => _MapboxPageWebState();
}

class _MapboxPageWebState extends State<MapboxPageWeb> with SingleTickerProviderStateMixin {
  // Mapbox token
  static const String mapboxAccessToken = 'pk.eyJ1IjoiY2h2YW5vdmFsZXhleSIsImEiOiJjbThlaGR5YXgwMWdpMmpzZG1hZm9weHFjIn0.y9kFEPItcETr0or609EYhg';
  
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
            console.log('Инициализация карты завершена');
          } catch (error) {
            console.error('Ошибка инициализации карты:', error);
          }
        })();
      ''']);
      
      print('JS код для инициализации Mapbox выполнен');
    } catch (e) {
      print('Ошибка при инициализации Mapbox GL JS: $e');
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
        ..style.backgroundColor = '#e0f7fa'
        ..style.border = '2px solid #ccc';
      
      // Добавляем индикатор загрузки
      mapElement.innerHtml = '''
        <div style="
          position: absolute;
          top: 0;
          left: 0;
          right: 0;
          bottom: 0;
          display: flex;
          align-items: center;
          justify-content: center;
          background-color: rgba(255, 255, 255, 0.7);
          z-index: 100;
        ">
          <div style="
            text-align: center;
            padding: 20px;
            background-color: white;
            border-radius: 8px;
            box-shadow: 0 4px 8px rgba(0, 0, 0, 0.1);
          ">
            <div style="
              width: 40px;
              height: 40px;
              margin: 0 auto 10px;
              border: 4px solid #e0e0e0;
              border-top: 4px solid #3498db;
              border-radius: 50%;
              animation: spin 1s linear infinite;
            "></div>
            <div>Загрузка карты Mapbox...</div>
          </div>
        </div>
        <style>
          @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
          }
          #$_mapElementId {
            position: relative;
            overflow: hidden;
          }
          .mapboxgl-map {
            width: 100%;
            height: 100%;
          }
        </style>
      ''';
      
      return mapElement;
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapbox GL JS (Web)'),
        actions: [
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