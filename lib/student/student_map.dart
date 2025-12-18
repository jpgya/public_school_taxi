import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:geolocator/geolocator.dart';
import 'dart:async';
// import 'package:url_launcher/url_launcher.dart';

class TaxiDriverMapPage extends StatefulWidget {
  const TaxiDriverMapPage({super.key, required this.title});

  final String title;

  @override
  TaxiDriverMapPageState createState() => TaxiDriverMapPageState();
}

class TaxiDriverMapPageState extends State<TaxiDriverMapPage> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  latlong.LatLng _currentPosition = const latlong.LatLng(35.681236, 139.767125); // デフォルト: 東京駅
  StreamSubscription<Position>? _positionStreamSubscription;
  final List<Marker> _markers = [];
  bool _isMapReady = false;
  bool _isLoading = true;

  final double _minZoom = 5.0;
  final double _maxZoom = 18.0;
  final double _initialZoom = 16.0; // 少し拡大

  late AnimationController _animationController;
  Animation<double>? _latAnimation, _lngAnimation, _zoomAnimation;

  // UI状態用
  bool _isSpeedDialOpen = false;
  bool _isTrackingUser = true; // 初期状態はユーザーを追跡

  Timer? _mapInteractionTimer; // 地図操作後の追跡オフ遅延用

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(duration: const Duration(milliseconds: 500), vsync: this);
    _initializeMap();
  }

  Future<void> _initializeMap() async {
    setState(() => _isLoading = true);
    try {
      await _determinePositionAndSetupLocationStream();
    } catch (e) {
      print("Error during map initialization: $e");
      if (mounted) {
        _showSnackBar("位置情報を取得できませんでした。ネットワークや権限を確認してください。", isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _animationController.dispose();
    _mapInteractionTimer?.cancel();
    super.dispose();
  }

  void _showSnackBar(String message, {bool isError = false, SnackBarAction? action}) {
    if (mounted) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar(); // 表示中のSnackBarがあれば消す
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
          action: action,
          duration: action != null ? const Duration(seconds: 7) : const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _determinePositionAndSetupLocationStream() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnackBar(
        '位置情報サービスが無効です。設定で有効にしてください。',
        isError: true,
        action: SnackBarAction(
          label: '設定を開く',
          onPressed: () async => await Geolocator.openLocationSettings(),
        ),
      );
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showSnackBar('位置情報の権限が拒否されました。', isError: true);
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showSnackBar(
        '位置情報の権限が永続的に拒否されています。アプリ設定から許可してください。',
        isError: true,
        action: SnackBarAction(
          label: '設定を開く',
          onPressed: () async => await Geolocator.openAppSettings(),
        ),
      );
      return;
    }

    try {
      Position initialPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      if (mounted) {
        _currentPosition = latlong.LatLng(initialPosition.latitude, initialPosition.longitude);
        _updateMarker();
        if (_isMapReady) {
          _animatedMapMove(_currentPosition, _mapController.camera.zoom < _minZoom + 1 ? _initialZoom : _mapController.camera.zoom);
        }
        setState(() {
          _isTrackingUser = true; // 初期位置取得成功で追跡開始
        });
      }
    } catch (e) {
      print("Error getting initial position: $e");
      _showSnackBar("初期位置を取得できませんでした。デフォルト位置で表示します。", isError: true);
      if (mounted && _isMapReady) {
        _animatedMapMove(_currentPosition, _initialZoom);
      }
      _updateMarker(); // デフォルト位置でマーカーを更新
    }

    _positionStreamSubscription?.cancel(); // 既存のストリームがあればキャンセル
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // 更新頻度を少し上げる
      ),
    ).listen(
          (Position position) {
        if (mounted) {
          _currentPosition = latlong.LatLng(position.latitude, position.longitude);
          _updateMarker(); // マーカーは常に更新
          if (_isMapReady && _isTrackingUser) { // 追跡モードの場合のみ地図を動かす
            // アニメーションなしで直接移動させるか、短時間のアニメーションにする
            _mapController.move(_currentPosition, _mapController.camera.zoom);
            // または _animatedMapMove(_currentPosition, _mapController.camera.zoom, durationMs: 200);
          }
          setState(() {}); // _currentPositionの更新をUIに反映するため（マーカー以外に緯度経度表示などがある場合）
        }
      },
      onError: (error) {
        print("Error in location stream: $error");
        if (mounted) _showSnackBar("位置情報の更新中にエラーが発生しました。", isError: true);
      },
    );
  }

  void _updateMarker() {
    if (!mounted) return;
    final newMarker = Marker(
      width: 80.0, // サイズ調整
      height: 80.0,
      point: _currentPosition,
      child: Tooltip(
        message: '現在地\n緯度: ${_currentPosition.latitude.toStringAsFixed(4)}\n経度: ${_currentPosition.longitude.toStringAsFixed(4)}',
        preferBelow: true, // メッセージをマーカーの下に
        child: LocationMarkerIcon(isTracking: _isTrackingUser), // カスタムマーカーアイコン
      ),
    );
    setState(() {
      _markers.clear();
      _markers.add(newMarker);
    });
  }

  void _onMapReady() {
    if (mounted) {
      setState(() => _isMapReady = true);
      // _isLoadingがfalseになった後、初期位置へ移動
      // ただし、_determinePositionAndSetupLocationStream内で初期位置取得成功時に既に移動している可能性あり
      if (!_isLoading) { // _isLoadingチェックを追加
        _animatedMapMove(_currentPosition, _mapController.camera.zoom < _minZoom +1 ? _initialZoom : _mapController.camera.zoom);
      }
    }
  }

  void _animatedMapMove(latlong.LatLng destLocation, double destZoom, {int durationMs = 500}) {
    if (!_isMapReady || !mounted) return;

    final latTween = Tween<double>(begin: _mapController.camera.center.latitude, end: destLocation.latitude);
    final lngTween = Tween<double>(begin: _mapController.camera.center.longitude, end: destLocation.longitude);
    final zoomTween = Tween<double>(begin: _mapController.camera.zoom, end: destZoom);

    _animationController.duration = Duration(milliseconds: durationMs);
    _animationController.reset();

    _latAnimation = latTween.animate(CurvedAnimation(parent: _animationController, curve: Curves.easeInOut));
    _lngAnimation = lngTween.animate(CurvedAnimation(parent: _animationController, curve: Curves.easeInOut));
    _zoomAnimation = zoomTween.animate(CurvedAnimation(parent: _animationController, curve: Curves.easeInOut));

    void listener() {
      if (_latAnimation != null && _lngAnimation != null && _zoomAnimation != null && mounted) {
        _mapController.move(
          latlong.LatLng(_latAnimation!.value, _lngAnimation!.value),
          _zoomAnimation!.value,
        );
      }
    }
    _animationController.addListener(listener);
    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
        _animationController.removeListener(listener); // リスナーを適切に削除
      }
    });


    _animationController.forward();
  }

  void _centerOnMyLocation() {
    if (!_isMapReady || !mounted) return;
    double targetZoom = _mapController.camera.zoom;
    if (targetZoom < _initialZoom-2 || targetZoom > _maxZoom) targetZoom = _initialZoom; // ズームレベル調整

    _animatedMapMove(_currentPosition, targetZoom);
    if (!_isTrackingUser) {
      setState(() => _isTrackingUser = true); // 追跡モードをオンにする
      _showSnackBar("現在地の追跡を開始しました。");
    }
    _closeSpeedDial();
  }

  void _zoomIn() {
    if (!_isMapReady) return;
    double currentZoom = _mapController.camera.zoom;
    if (currentZoom < _maxZoom) {
      _animatedMapMove(_mapController.camera.center, currentZoom + 1.0);
      _handleMapInteraction(); // 地図操作として扱う
    } else {
      _showSnackBar("これ以上拡大できません。");
    }
    _closeSpeedDial();
  }

  void _zoomOut() {
    if (!_isMapReady) return;
    double currentZoom = _mapController.camera.zoom;
    if (currentZoom > _minZoom) {
      _animatedMapMove(_mapController.camera.center, currentZoom - 1.0);
      _handleMapInteraction(); // 地図操作として扱う
    } else {
      _showSnackBar("これ以上縮小できません。");
    }
    _closeSpeedDial();
  }

  void _closeSpeedDial() {
    if (_isSpeedDialOpen) {
      setState(() => _isSpeedDialOpen = false);
    }
  }

  // 地図がユーザーによって操作されたときの処理
  void _handleMapInteraction() {
    _mapInteractionTimer?.cancel(); // 既存のタイマーがあればキャンセル
    _mapInteractionTimer = Timer(const Duration(milliseconds: 300), () { // 少し遅延させて頻繁な切り替えを防ぐ
      if (mounted && _isTrackingUser) {
        setState(() => _isTrackingUser = false);
        _showSnackBar("地図を操作したため、現在地の自動追跡をオフにしました。");
        _updateMarker(); // マーカーアイコン更新のため
      }
    });
  }


  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        toolbarHeight: 60,
        title: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              children: [
                Icon(_isTrackingUser ? Icons.location_on : Icons.explore_off_outlined, size: 28), // 追跡状態アイコン
                const SizedBox(width: 8),
                Text(widget.title, style: TextStyle(fontSize: 24, color: colorScheme.onPrimary)),
                // const SizedBox(width: 60), // 右端のスペースはFABがあるので不要かも
              ],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition,
              initialZoom: _initialZoom,
              minZoom: _minZoom,
              maxZoom: _maxZoom,
              onMapReady: _onMapReady,
              onPositionChanged: (MapPosition position, bool hasGesture) {
                if (hasGesture) {
                  _handleMapInteraction();
                }
              },
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.doubleTapZoom, // ダブルタップズームは無効化も検討
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.school_taxi', // アンダースコアに変更
                // offlineMode: true, // オフライン対応する場合
                // tileProvider: CachedNetworkTileProvider(), // キャッシュを利用する場合
              ),
              MarkerLayer(markers: _markers),
              RichAttributionWidget(
                alignment: AttributionAlignment.bottomRight,
                attributions: [
                  TextSourceAttribution(
                    'OpenStreetMap contributors',
                    onTap: () async {
                      // final Uri osmCopyrightUri = Uri.parse('https://www.openstreetmap.org/copyright');
                      // if (await canLaunchUrl(osmCopyrightUri)) {
                      //   await launchUrl(osmCopyrightUri);
                      // } else {
                      //   _showSnackBar('OpenStreetMapの著作権ページを開けませんでした。', isError: true);
                      // }
                    },
                  ),
                ],
              ),
            ],
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.6),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(colorScheme.onPrimary.withOpacity(0.9)),
                    ),
                    const SizedBox(height: 16),
                    Text("地図を準備中...", style: TextStyle(color: colorScheme.onPrimary, fontSize: 16)),
                  ],
                ),
              ),
            ),

          // Speed Dial 風 FAB
          Positioned(
            right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 16,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                if (_isSpeedDialOpen) ...[
                  _buildSmallFab(
                    heroTag: "center_fab",
                    icon: _isTrackingUser ? Icons.gps_fixed : Icons.my_location, // 追跡状態でアイコン変更
                    tooltip: _isTrackingUser ? '追跡中 (タップで手動モード)' : '現在地に移動 & 追跡開始',
                    onPressed: _centerOnMyLocation,
                  ),
                  const SizedBox(height: 12),
                  _buildSmallFab(
                    heroTag: "zoom_in_fab",
                    icon: Icons.add,
                    tooltip: '拡大',
                    onPressed: _zoomIn,
                  ),
                  const SizedBox(height: 12),
                  _buildSmallFab(
                    heroTag: "zoom_out_fab",
                    icon: Icons.remove,
                    tooltip: '縮小',
                    onPressed: _zoomOut,
                  ),
                  const SizedBox(height: 16),
                ],
                FloatingActionButton(
                  heroTag: "main_fab",
                  onPressed: () {
                    setState(() => _isSpeedDialOpen = !_isSpeedDialOpen);
                  },
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  elevation: 6,
                  child: AnimatedSwitcher( // アイコンをアニメーションで切り替え
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (Widget child, Animation<double> animation) {
                      return ScaleTransition(scale: animation, child: child);
                    },
                    child: Icon(
                      _isSpeedDialOpen ? Icons.close : Icons.menu,
                      key: ValueKey<bool>(_isSpeedDialOpen), // アニメーションのためのキー
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Small FAB を生成するヘルパーメソッド
  Widget _buildSmallFab({
    required String heroTag,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return FloatingActionButton.small(
      heroTag: heroTag,
      onPressed: onPressed,
      tooltip: tooltip,
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
      foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
      elevation: 4,
      child: Icon(icon),
    );
  }
}


// カスタムマーカーアイコンウィジェット
class LocationMarkerIcon extends StatelessWidget {
  final bool isTracking;
  const LocationMarkerIcon({super.key, required this.isTracking});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(2.0),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            spreadRadius: 2,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        isTracking ? Icons.navigation : Icons.person_pin_circle, // 追跡中はナビゲーション風アイコン
        color: isTracking ? colorScheme.primary : colorScheme.tertiary, // 色も変更
        size: 38.0,
      ),
    );
  }
}
