import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

// --- APIキーの設定 ---
const String googleApiKey = "GOOGLE_MAP_API_KEY";

class RouteTrackingMapScreen extends StatefulWidget {
  final String routeDocId;
  final String selectedDate;

  const RouteTrackingMapScreen({
    super.key,
    required this.routeDocId,
    required this.selectedDate
  });

  @override
  State<RouteTrackingMapScreen> createState() => _RouteTrackingMapScreenState();
}

class _RouteTrackingMapScreenState extends State<RouteTrackingMapScreen> {
  // Map state
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  // Driver's real-time position
  StreamSubscription? _driverLocationSubscription;

  // UI State
  bool _isLoading = true;
  String _statusMessage = "ルート情報を読み込み中...";
  String? _driverDisplayName;
  String? _driverId;

  bool _isDriverDriving = false;
  bool _isCameraInitialized = false;

  // Route Info
  LatLng? _myHomePosition;
  int? _myHomeWaypointIndex;

  // --- 新しい到着予測のための状態変数 ---
  bool _isTokoRoute = false;
  DateTime? _predictedArrivalTime;

  static const int RIDE_ON_TIME_MINUTES = 3;
  static const String FINAL_ARRIVAL_TIME_STRING = "08:30";

  // --- Firebase関連 ---
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseReference _databaseReference = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: 'https://school-taxi-ae8b1-default-rtdb.asia-southeast1.firebasedatabase.app',
  ).ref();
  final String? _currentUserId = FirebaseAuth.instance.currentUser?.uid;

  static const CameraPosition _initialCameraPosition = CameraPosition(
    target: LatLng(35.681236, 139.767125),
    zoom: 5.0,
  );

  @override
  void initState() {
    super.initState();
    _validateAndLoad();
  }

  @override
  void dispose() {
    _driverLocationSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _validateAndLoad() async {
    if (googleApiKey.startsWith("YOUR_GOOGLE_MAPS_API_KEY") || googleApiKey.isEmpty) {
      _handleError("エラー: 地図表示に必要な設定がされていません。");
      return;
    }
    if (widget.routeDocId.isEmpty) {
      _handleError("エラー: 表示するルートが指定されていません。");
      return;
    }
    await _loadRouteAndTrackDriver();
  }

  void _handleError(String message) {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _statusMessage = message;
    });
  }

  Future<void> _loadRouteAndTrackDriver() async {
    setState(() { _statusMessage = "ルート情報を読み込み中..."; });
    try {
      final routeDoc = await _firestore.collection('routes').doc(widget.routeDocId).get();
      if (!routeDoc.exists || routeDoc.data() == null) {
        throw Exception("指定されたルート情報が見つかりませんでした。");
      }
      final routeData = routeDoc.data()!;
      _driverId = routeData['driverId'] as String?;
      if (_driverId == null || _driverId!.isEmpty) {
        throw Exception("ルートに担当ドライバーが割り当てられていません。");
      }

      if (routeData.containsKey('isGoSchool') && routeData['isGoSchool'] == true) {
        setState(() { _isTokoRoute = true; });
      }

      await _drawRouteFromData(routeData); // 初期データは渡すが、内部で再取得する
      await _loadDriverProfile();
      _startListeningToDriverLocation();

    } catch (e) {
      _handleError(e.toString().replaceFirst("Exception: ", ""));
    }
  }

  Future<void> _drawRouteFromData(Map<String, dynamic> initialData) async {
    _markers.clear();
    _polylines.clear();
    _myHomePosition = null;
    _myHomeWaypointIndex = null;
    bool myHomeFound = false;

    try {
      // --- 1. ルートの最新情報を取得 ---
      final latestRouteDoc = await _firestore.collection('routes').doc(widget.routeDocId).get();
      if (!latestRouteDoc.exists || latestRouteDoc.data() == null) {
        _handleError("ルート情報の再取得に失敗しました。");
        return;
      }
      final data = latestRouteDoc.data()!;

      // --- 2. 自分の最新の住所情報を取得 ---
      String? myAddress;
      if (_currentUserId != null) {
        final userDoc = await _firestore.collection('Users').doc(_currentUserId).get();
        if (userDoc.exists && userDoc.data()!.containsKey('Address')) {
          myAddress = userDoc.data()!['Address'] as String?;
        }
      }
      if (myAddress == null || myAddress.isEmpty) {
        debugPrint("警告: ログインユーザーの住所が見つかりません。");
      }
      final String? normalizedMyAddress = myAddress?.trim().replaceAll(RegExp(r'\s+'), '');
      // --- ここまででデータ取得が完了 ---

      final origin = data['origin'] as Map<String, dynamic>?;
      if (origin != null) {
        final String address = origin['address'] as String? ?? '出発地';
        _addOrUpdateGenericMarker(markerId: 'origin', position: LatLng(origin['latitude'], origin['longitude']), title: address, iconHue: BitmapDescriptor.hueViolet);
      }

      final waypoints = data['waypoints'] as List<dynamic>?;
      if (waypoints != null) {
        for (int i = 0; i < waypoints.length; i++) {
          final point = waypoints[i] as Map<String, dynamic>;
          final position = LatLng(point['latitude'], point['longitude']);
          final String address = point['address'] as String? ?? '経由地 ${i + 1}';
          final String normalizedRouteAddress = address.trim().replaceAll(RegExp(r'\s+'), '');

          // ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
          // ★★★ 住所比較を「完全一致」(`==`) に変更 ★★★
          // ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
          final bool isMyHome = !myHomeFound &&
              (normalizedMyAddress != null && normalizedMyAddress.isNotEmpty && normalizedRouteAddress.isNotEmpty) &&
              (normalizedMyAddress == normalizedRouteAddress);

          if (isMyHome) {
            _myHomePosition = position;
            _myHomeWaypointIndex = i;
            myHomeFound = true;
          }
          _addOrUpdateGenericMarker(
            markerId: 'waypoint_$i', position: position, title: isMyHome ? '経由地（あなたの家）' : address,
            iconHue: isMyHome ? BitmapDescriptor.hueCyan : BitmapDescriptor.hueOrange, zIndex: isMyHome ? 1.0 : 0.0,
          );
        }
      }

      final destination = data['destination'] as Map<String, dynamic>?;
      if (destination != null) {
        final position = LatLng(destination['latitude'], destination['longitude']);
        final String address = destination['address'] as String? ?? '目的地';
        _addOrUpdateGenericMarker(markerId: 'destination', position: position, title: address, iconHue: BitmapDescriptor.hueGreen);
      }

      final encodedPolyline = data['polyline'] as String?;
      if (encodedPolyline != null && encodedPolyline.isNotEmpty) {
        final polylineCoordinates = PolylinePoints().decodePolyline(encodedPolyline).map((p) => LatLng(p.latitude, p.longitude)).toList();
        _polylines.add(Polyline(polylineId: const PolylineId('saved_route'), points: polylineCoordinates, color: Colors.blue.withOpacity(0.7), width: 7));
      }
    } catch (e) {
      _handleError("ルート描画中にエラーが発生しました: $e");
    }
  }

  Future<void> _loadDriverProfile() async {
    try {
      if (_driverId == null) return;
      DocumentSnapshot driverDoc = await _firestore.collection('drivers').doc(_driverId).get();
      if (driverDoc.exists && driverDoc.data() != null) {
        final data = driverDoc.data() as Map<String, dynamic>;
        if (mounted) setState(() => _driverDisplayName = data['displayName'] as String?);
      }
    } catch (e) {
      debugPrint("ドライバーのプロフィール読み込みエラー: $e");
    }
  }

  void _startListeningToDriverLocation() {
    if (_driverId == null) return;
    _driverLocationSubscription = _databaseReference.child('driverLocations/$_driverId').onValue.listen((event) {
      if (!mounted) return;
      if (!event.snapshot.exists || event.snapshot.value == null) {
        if (_isLoading) _handleError("ドライバーの現在位置がまだ共有されていません。");
        return;
      }
      final data = Map<String, dynamic>.from(event.snapshot.value as Map);
      final newLatitude = data['latitude'] as double?;
      final newLongitude = data['longitude'] as double?;
      final newIsDriving = data['isDriving'] as bool?;

      if (newLatitude != null && newLongitude != null) {
        final driverPosition = LatLng(newLatitude, newLongitude);

        if (_isTokoRoute) {
          _calculateArrivalTime(driverPosition, newIsDriving ?? _isDriverDriving);
        }

        if (!_isCameraInitialized) {
          setState(() {
            _addOrUpdateDriverMarker(driverPosition);
            if (newIsDriving != null) _isDriverDriving = newIsDriving;
            _isLoading = false;
            _statusMessage = "ルートを表示しました。";
          });
          _isCameraInitialized = true;
          _updateCameraToBounds();
        } else {
          setState(() {
            _addOrUpdateDriverMarker(driverPosition);
            if (newIsDriving != null) _isDriverDriving = newIsDriving;
          });
        }
      }
    }, onError: (error) {
      _handleError("エラー: ドライバー情報の取得に失敗しました。");
    });
  }

  void _calculateArrivalTime(LatLng driverPosition, bool isCurrentlyDriving) {
    if (_myHomePosition == null || _polylines.isEmpty || _myHomeWaypointIndex == null) return;

    DateTime? newPredictedTime;
    final routePoints = _polylines.first.points;
    if (routePoints.length < 2) return;

    if (isCurrentlyDriving) {
      int closestPointIndex = -1;
      double minDistance = double.infinity;
      for (int i = 0; i < routePoints.length; i++) {
        final distance = _calculateDistanceBetween(driverPosition, routePoints[i]);
        if (distance < minDistance) {
          minDistance = distance;
          closestPointIndex = i;
        }
      }

      int homePointIndex = -1;
      minDistance = double.infinity;
      for (int i = 0; i < routePoints.length; i++) {
        final distance = _calculateDistanceBetween(_myHomePosition!, routePoints[i]);
        if (distance < minDistance) {
          minDistance = distance;
          homePointIndex = i;
        }
      }

      if (closestPointIndex != -1 && homePointIndex != -1 && closestPointIndex < homePointIndex) {
        double remainingDistanceInMeters = 0;
        for (int i = closestPointIndex; i < homePointIndex; i++) {
          remainingDistanceInMeters += _calculateDistanceBetween(routePoints[i], routePoints[i + 1]);
        }
        final averageSpeedKmh = 25;
        final estimatedMinutes = (remainingDistanceInMeters / 1000 / averageSpeedKmh) * 60;

        newPredictedTime = DateTime.now().add(Duration(minutes: estimatedMinutes.round()));
      }
    } else {
      if (_predictedArrivalTime == null) {
        final Marker? destinationMarker = _markers.firstWhere((m) => m.markerId.value == 'destination', orElse: () => _markers.first);
        if (destinationMarker == null) return;

        int destinationPointIndex = -1;
        double minDistance = double.infinity;
        for (int i = 0; i < routePoints.length; i++) {
          final distance = _calculateDistanceBetween(destinationMarker.position, routePoints[i]);
          if (distance < minDistance) { minDistance = distance; destinationPointIndex = i; }
        }
        if (destinationPointIndex == -1) return;

        int homePointIndex = -1;
        minDistance = double.infinity;
        for (int i = 0; i < routePoints.length; i++) {
          final distance = _calculateDistanceBetween(_myHomePosition!, routePoints[i]);
          if (distance < minDistance) { minDistance = distance; homePointIndex = i; }
        }
        if (homePointIndex == -1) return;

        double distanceToDestinationMeters = 0;
        int startIndex = min(homePointIndex, destinationPointIndex);
        int endIndex = max(homePointIndex, destinationPointIndex);
        for (int i = startIndex; i < endIndex; i++) {
          distanceToDestinationMeters += _calculateDistanceBetween(routePoints[i], routePoints[i + 1]);
        }

        final averageSpeedKmh = 25;
        final travelMinutes = (distanceToDestinationMeters / 1000 / averageSpeedKmh) * 60;

        final markersAfterMe = _markers.where((m) =>
        m.markerId.value.startsWith('waypoint_') &&
            int.parse(m.markerId.value.split('_').last) > _myHomeWaypointIndex!
        ).length;
        final rideOnTimeAfterMe = markersAfterMe * RIDE_ON_TIME_MINUTES;

        final now = DateTime.now();
        final finalArrivalTime = DateTime(now.year, now.month, now.day, int.parse(FINAL_ARRIVAL_TIME_STRING.split(':')[0]), int.parse(FINAL_ARRIVAL_TIME_STRING.split(':')[1]));
        final totalMinutesToSubtract = travelMinutes + rideOnTimeAfterMe;

        newPredictedTime = finalArrivalTime.subtract(Duration(minutes: totalMinutesToSubtract.round()));
      } else {
        newPredictedTime = _predictedArrivalTime;
      }
    }

    if (newPredictedTime != null && (_predictedArrivalTime == null || newPredictedTime.minute != _predictedArrivalTime!.minute)) {
      setState(() {
        _predictedArrivalTime = newPredictedTime;
      });
    }
  }

  double _calculateDistanceBetween(LatLng pos1, LatLng pos2) {
    const R = 6371e3;
    final phi1 = pos1.latitude * pi / 180;
    final phi2 = pos2.latitude * pi / 180;
    final deltaPhi = (pos2.latitude - pos1.latitude) * pi / 180;
    final deltaLambda = (pos2.longitude - pos1.longitude) * pi / 180;
    final a = sin(deltaPhi / 2) * sin(deltaPhi / 2) + cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  void _addOrUpdateDriverMarker(LatLng position) {
    final marker = Marker(markerId: const MarkerId('driverLocation'), position: position, infoWindow: InfoWindow(title: "ドライバー: ${_driverDisplayName ?? '走行中'}"), icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow), zIndex: 2);
    if (!mounted) return;
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'driverLocation');
      _markers.add(marker);
    });
  }

  void _addOrUpdateGenericMarker({required String markerId, required LatLng position, required String title, double iconHue = BitmapDescriptor.hueRed, double zIndex = 0.0}) {
    final marker = Marker(markerId: MarkerId(markerId), position: position, infoWindow: InfoWindow(title: title), icon: BitmapDescriptor.defaultMarkerWithHue(iconHue), zIndex: zIndex);
    if (_markers.any((m) => m.markerId.value == markerId)) {
      _markers.removeWhere((m) => m.markerId.value == markerId);
    }
    _markers.add(marker);
  }

  void _updateCameraToBounds() {
    if (!mounted || _mapController == null || _markers.isEmpty) return;
    Future.delayed(const Duration(milliseconds: 250), () {
      if (!mounted || _mapController == null) return;
      if (_markers.length == 1) {
        _mapController!.animateCamera(CameraUpdate.newLatLngZoom(_markers.first.position, 15));
      } else {
        try {
          LatLngBounds bounds = _calculateBoundsFromPoints(_markers.map((m) => m.position).toList());
          _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80.0));
        } catch(e) {
          debugPrint("カメラの更新に失敗しました: $e");
        }
      }
    });
  }

  LatLngBounds _calculateBoundsFromPoints(List<LatLng> points) {
    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;
    for (var point in points) {
      minLat = min(minLat, point.latitude); maxLat = max(maxLat, point.latitude);
      minLng = min(minLng, point.longitude); maxLng = max(maxLng, point.longitude);
    }
    return LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.selectedDate+"のルート"),
        backgroundColor: theme.colorScheme.primaryContainer,
      ),
      body: Column(
        children: [
          _buildEtaPanel(theme),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                GoogleMap(
                  mapType: MapType.normal, initialCameraPosition: _initialCameraPosition,
                  onMapCreated: (GoogleMapController controller) {
                    _mapController = controller;
                    if (!_isLoading) _updateCameraToBounds();
                  },
                  markers: _markers, polylines: _polylines,
                  myLocationEnabled: false, myLocationButtonEnabled: false,
                  zoomControlsEnabled: true, mapToolbarEnabled: true,
                ),
                if (_isLoading)
                  _buildLoadingIndicator(theme)
                else if (_markers.isEmpty)
                  _buildErrorMessageWidget(theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEtaPanel(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12.0),
      margin: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.person, color: theme.colorScheme.secondary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_driverDisplayName ?? 'ドライバー情報読み込み中...', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: _isDriverDriving ? Colors.green.shade100 : Colors.grey.shade300, borderRadius: BorderRadius.circular(8)),
                child: Text(_isDriverDriving ? "走行中" : "停止中", style: theme.textTheme.bodyMedium?.copyWith(color: _isDriverDriving ? Colors.green.shade800 : Colors.black87, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          if (_isTokoRoute) ...[
            const Divider(height: 20, thickness: 1),
            if (_predictedArrivalTime != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("お迎え予定時刻", style: theme.textTheme.titleMedium),
                    const SizedBox(width: 12),
                    Icon(Icons.home_work_rounded, color: theme.colorScheme.primary, size: 28),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('H:mm').format(_predictedArrivalTime!),
                      style: theme.textTheme.headlineSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
                    ),
                    Text(" 頃", style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary)),
                  ],
                ),
              )
            else if (!_isLoading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                    _myHomePosition == null ? "ルートにあなたの自宅が含まれていません" : "到着時刻を計算中...",
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoadingIndicator(ThemeData theme) { return Positioned.fill(child: Container(color: Colors.white.withOpacity(0.8), child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const CircularProgressIndicator(), const SizedBox(height: 20), Text(_statusMessage, style: theme.textTheme.titleMedium)])))); }
  Widget _buildErrorMessageWidget(ThemeData theme) { return Container(color: Colors.white.withOpacity(0.8), child: Center(child: Padding(padding: const EdgeInsets.all(20.0), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.error_outline, color: theme.colorScheme.error, size: 50), const SizedBox(height: 16), Text(_statusMessage, textAlign: TextAlign.center, style: theme.textTheme.titleMedium?.copyWith(color: Colors.black87))])))); }
  Widget _buildApiKeyMissingWidget(ThemeData theme) { return Center(child: Padding(padding: const EdgeInsets.all(24.0), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.vpn_key_off_rounded, color: theme.colorScheme.error, size: 60), const SizedBox(height: 20), Text("エラー", style: theme.textTheme.headlineSmall?.copyWith(color: theme.colorScheme.error, fontWeight: FontWeight.bold), textAlign: TextAlign.center), const SizedBox(height: 15), Text(_statusMessage, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5))]))); }
}
