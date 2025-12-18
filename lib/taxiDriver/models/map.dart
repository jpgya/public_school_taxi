import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

// --- APIキーの設定 ---
const String googleApiKey = "GOOGLE_MAP_API_KEY"; // ★★★★★ ご自身のAPIキーに置き換えてください ★★★★★

class MapScreen extends StatefulWidget {
  final DateTime selectedDate;
  final String schoolId;
  final bool isGoSchool;

  const MapScreen({
    super.key,
    required this.selectedDate,
    required this.schoolId,
    required this.isGoSchool,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  final TextEditingController _originController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  final List<TextEditingController> _waypointControllers = [];

  LatLng? _currentPosition;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  List<LatLng> _polylineCoordinates = [];

  String _distance = "";
  String _duration = "";
  String _departureTime = "";
  bool _isLoading = true;
  String _statusMessage = "初期化中...";

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? _loggedInUserCompanyId;

  final DatabaseReference _databaseReference = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: 'https://school-taxi-ae8b1-default-rtdb.asia-southeast1.firebasedatabase.app'
  ).ref();
  StreamSubscription<Position>? _positionStreamSubscription;
  bool _isDriving = false;


  static const CameraPosition _initialCameraPosition = CameraPosition(
    target: LatLng(35.681236, 139.767125),
    zoom: 12,
  );

  @override
  void initState() {
    super.initState();
    if (googleApiKey.startsWith("YOUR_GOOGLE_MAPS_API_KEY") || googleApiKey.isEmpty) {
      _handleError("エラー: APIキーが設定されていません。");
    } else {
      _initializeAndTriggerRouteSearch();
    }
  }

  void _handleError(String message) {
    debugPrint(">>>>>> エラー発生: $message <<<<<<");
    if (mounted) {
      setState(() {
        _isLoading = false;
        _statusMessage = message;
      });
      _showErrorSnackbar(message);
    }
  }

  Future<void> _initializeAndTriggerRouteSearch() async {
    setStateIfMounted(() => _isLoading = true);
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) throw Exception("ログインしていません。");

      final userDoc = await _firestore.collection('drivers').doc(currentUser.uid).get();
      if (!userDoc.exists) throw Exception("ログインユーザーの情報が見つかりません。");

      _loggedInUserCompanyId = (userDoc.data() as Map<String, dynamic>)['companyId'] as String?;
      if (_loggedInUserCompanyId == null || _loggedInUserCompanyId!.isEmpty) {
        throw Exception("ユーザーに会社IDが紐付いていません。");
      }

      await _requestLocationPermissionAndGetCurrentLocation();
      await _triggerFirebaseRouteSearch();

    } catch (e, stackTrace) {
      debugPrint("初期化エラー: $e");
      debugPrint("スタックトレース: $stackTrace");
      _handleError("初期化エラー: ${e.toString().replaceFirst("Exception: ", "")}");
    }
  }

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    for (var controller in _waypointControllers) {
      controller.dispose();
    }
    _positionStreamSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _requestLocationPermissionAndGetCurrentLocation() async {
    setStateIfMounted(() => _statusMessage = "現在位置の権限を確認中...");
    PermissionStatus status = await Permission.location.request();
    if (status.isGranted) {
      await _getCurrentLocation();
    } else {
      String permStatusMsg = '位置情報の権限が拒否されました。';
      if (status.isPermanentlyDenied) permStatusMsg += ' 設定アプリから権限を許可してください。';
      _handleError(permStatusMsg);
      if (mounted && (status.isPermanentlyDenied || (status.isDenied && !await Permission.location.shouldShowRequestRationale))) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(permStatusMsg),
          action: SnackBarAction(label: "設定を開く", onPressed: openAppSettings),
        ));
      }
    }
  }

  Future<void> _getCurrentLocation() async {
    setStateIfMounted(() => _statusMessage = "現在位置を取得中...");
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 20),
      ).timeout(const Duration(seconds: 25));

      setStateIfMounted(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
        _addOrUpdateMarker(
          markerId: "currentLocation",
          position: _currentPosition!,
          title: "現在地",
          iconHue: BitmapDescriptor.hueAzure,
        );
        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(CameraPosition(target: _currentPosition!, zoom: 15)),
        );
        _statusMessage = "現在地を取得しました。";
      });
    } on TimeoutException {
      _handleError('現在地の取得がタイムアウトしました。');
    } catch (e) {
      _handleError('現在地の取得に失敗しました: ${e.toString()}');
    }
  }

  void _addOrUpdateMarker({
    required String markerId,
    required LatLng position,
    required String title,
    String? snippet,
    double iconHue = BitmapDescriptor.hueRed,
    String? labelTextForController,
  }) {
    final marker = Marker(
      markerId: MarkerId(markerId),
      position: position,
      infoWindow: InfoWindow(title: title, snippet: snippet),
      icon: BitmapDescriptor.defaultMarkerWithHue(iconHue),
    );
    setStateIfMounted(() {
      _markers.removeWhere((m) => m.markerId.value == markerId);
      _markers.add(marker);

      if (labelTextForController != null) {
        if (markerId == 'origin_firebase') _originController.text = labelTextForController;
        else if (markerId == 'destination_firebase') _destinationController.text = labelTextForController;
        else if (markerId.startsWith('waypoint_firebase_')) {
          try {
            int index = int.parse(markerId.split('_').last);
            if (index >= 0 && _waypointControllers.length <= index) {
              _waypointControllers.addAll(List.generate(index - _waypointControllers.length + 1, (_) => TextEditingController()));
            }
            if (index >= 0 && index < _waypointControllers.length) {
              _waypointControllers[index].text = labelTextForController;
            }
          } catch(e) { debugPrint("ウェイポイントコントローラーへの設定エラー: $e"); }
        }
      }
    });
  }

  Future<LatLng?> _getLatLngFromAddress(String address) async {
    if (address.trim().isEmpty) return null;
    try {
      List<geo.Location> locations = await geo.locationFromAddress(address, localeIdentifier: "ja_JP");
      if (locations.isNotEmpty) {
        return LatLng(locations.first.latitude, locations.first.longitude);
      } else {
        throw Exception("場所「$address」が見つかりません。");
      }
    } catch (e) {
      throw Exception("「$address」の座標取得に失敗しました。");
    }
  }

  void setStateIfMounted(VoidCallback fn) {
    if (mounted) { setState(fn); }
  }

  Future<void> _triggerFirebaseRouteSearch() async {
    final currentDriverId = _auth.currentUser?.uid;
    if (currentDriverId == null) return _handleError("ログイン情報が無効です。");

    DateTime? arrivalTime;
    if (widget.isGoSchool) {
      arrivalTime = DateTime(widget.selectedDate.year, widget.selectedDate.month, widget.selectedDate.day, 8, 30);
    }

    setStateIfMounted(() {
      _isLoading = true;
      _polylines.clear();
      _polylineCoordinates.clear();
      _markers.removeWhere((m) => m.markerId.value != 'currentLocation');
      _distance = "";
      _duration = "";
      _departureTime = "";
      _statusMessage = "選択されたルートを取得中...";
      _waypointControllers.clear();
    });

    List<Map<String, dynamic>> reservationsWithData = [];

    try {
      final driverDocFuture = _firestore.collection('drivers').doc(currentDriverId).get();
      final companyDocFuture = _firestore.collection('companys').doc(_loggedInUserCompanyId).get();
      final results = await Future.wait([driverDocFuture, companyDocFuture]);

      final driverDoc = results[0];
      final companyDoc = results[1];
      if (!driverDoc.exists) throw Exception("あなたのドライバー情報が見つかりません。");
      final int maxPassengers = (driverDoc.data() as Map<String, dynamic>)['maxNum'] as int? ?? 0;
      if (maxPassengers <= 0) throw Exception("最大乗車人数が設定されていません。");
      if (!companyDoc.exists) throw Exception("会社情報が見つかりません。");
      final String? companyAddress = (companyDoc.data() as Map<String, dynamic>)['address'] as String?;
      if (companyAddress == null || companyAddress.isEmpty) throw Exception("会社の住所が設定されていません。");

      final startOfDay = Timestamp.fromDate(DateTime(widget.selectedDate.year, widget.selectedDate.month, widget.selectedDate.day));
      final endOfDay = Timestamp.fromDate(DateTime(widget.selectedDate.year, widget.selectedDate.month, widget.selectedDate.day, 23, 59, 59));
      final usersOfSchoolSnap = await _firestore.collection('Users').where('schoolId', isEqualTo: widget.schoolId).get();
      if (usersOfSchoolSnap.docs.isEmpty) throw Exception("この学校に所属する生徒が見つかりませんでした。");
      final userIdsOfSchool = usersOfSchoolSnap.docs.map((doc) => doc.id).toList();

      final reservationRunSnapshot = await _firestore.collection('reservations')
          .where('userId', whereIn: userIdsOfSchool)
          .where(widget.isGoSchool ? 'goSchool' : 'backSchool', isEqualTo: true)
          .where('pickUpTime', isGreaterThanOrEqualTo: startOfDay)
          .where('pickUpTime', isLessThanOrEqualTo: endOfDay)
          .orderBy('pickUpTime').orderBy('pickUpOrder').get();
      if (reservationRunSnapshot.docs.isEmpty) throw Exception("指定された条件の送迎予約はありません。");

      List<DocumentSnapshot> reservationsToProcess = reservationRunSnapshot.docs.toList();
      if (reservationsToProcess.length > maxPassengers) {
        reservationsToProcess = reservationsToProcess.sublist(0, maxPassengers);
      }

      WriteBatch batch = _firestore.batch();
      for (final resDoc in reservationsToProcess) {
        batch.update(resDoc.reference, {'assignedDriverId': currentDriverId, 'status': 'assigned'});
        reservationsWithData.add({'id': resDoc.id, 'data': resDoc.data() as Map<String, dynamic>});
      }
      await batch.commit();

      final schoolDoc = await _firestore.collection('schools').doc(widget.schoolId).get();
      final schoolAddress = (schoolDoc.data() as Map<String, dynamic>?)?['address'] as String?;
      if (schoolAddress == null || schoolAddress.isEmpty) throw Exception("学校の住所が見つかりませんでした。");

      List<String> waypointAddresses = [];
      List<int> waypointToReservationIndexMap = [];
      for (int i = 0; i < reservationsWithData.length; i++) {
        final res = reservationsWithData[i];
        final userDoc = await _firestore.collection('Users').doc(res['data']['userId']).get();
        if (userDoc.exists) {
          final addr = (userDoc.data() as Map<String, dynamic>)['Address'] as String?;
          if (addr != null && addr.isNotEmpty) {
            waypointAddresses.add(addr);
            waypointToReservationIndexMap.add(i);
          }
        }
      }
      debugPrint("LOG: waypointAddresses: $waypointAddresses");
      debugPrint("LOG: waypointToReservationIndexMap: $waypointToReservationIndexMap");

      if (reservationsWithData.isNotEmpty && waypointAddresses.isEmpty) {
        throw Exception("ルート設定に必要な生徒の住所が見つかりませんでした。");
      }

      String originDisplayAddress, destinationDisplayAddress;
      List<String> waypointsForRoute = List.from(waypointAddresses);

      if (widget.isGoSchool) {
        originDisplayAddress = companyAddress;
        destinationDisplayAddress = schoolAddress;
      } else {
        originDisplayAddress = schoolAddress;
        if (waypointsForRoute.isNotEmpty) {
          destinationDisplayAddress = waypointsForRoute.removeLast();
          waypointToReservationIndexMap.removeLast();
        } else {
          destinationDisplayAddress = companyAddress; // 経由地0でも目的地は会社
        }
      }

      await _buildAndFetchRoute(
        originDisplayAddress,
        destinationDisplayAddress,
        waypointsForRoute,
        arrivalTime,
        reservationsWithData,
        waypointToReservationIndexMap,
      );

      if (_currentPosition != null) {
        await _databaseReference.child('driverLocations/$currentDriverId').set({
          'latitude': _currentPosition!.latitude,
          'longitude': _currentPosition!.longitude,
          'timestamp': ServerValue.timestamp,
          'isDriving': false, // この時点では走行していない
        });
        debugPrint("LOG: 初期位置をRealtime Databaseに保存しました。");
      }

    } catch (e, stackTrace) {
      debugPrint("トリガーエラー: $e");
      debugPrint("スタックトレース: $stackTrace");
      _handleError(e.toString().replaceFirst("Exception: ", ""));
    } finally {
      setStateIfMounted(() => _isLoading = false);
    }
  }

  Future<void> _buildAndFetchRoute(
      String originAddr,
      String destAddr,
      List<String> waypointAddrs,
      DateTime? arrivalTime,
      List<Map<String, dynamic>> reservationData,
      List<int> waypointToReservationIndexMap,
      ) async {

    final originLatLng = await _getLatLngFromAddress(originAddr);
    if (originLatLng == null) throw Exception("出発地「$originAddr」の座標が見つかりません。");
    final originPayload = {"location": {"latLng": {"latitude": originLatLng.latitude, "longitude": originLatLng.longitude}}};
    _addOrUpdateMarker(markerId: 'origin_firebase', position: originLatLng, title: '出発地: $originAddr', iconHue: BitmapDescriptor.hueViolet, labelTextForController: originAddr);

    final destinationLatLng = await _getLatLngFromAddress(destAddr);
    if (destinationLatLng == null) throw Exception("目的地「$destAddr」の座標が見つかりません。");
    final destinationPayload = {"location": {"latLng": {"latitude": destinationLatLng.latitude, "longitude": destinationLatLng.longitude}}};
    _addOrUpdateMarker(markerId: 'destination_firebase', position: destinationLatLng, title: '目的地: $destAddr', iconHue: BitmapDescriptor.hueGreen, labelTextForController: destAddr);

    List<Map<String, dynamic>> intermediatesPayload = [];
    List<Map<String, dynamic>> waypointDataForStorage = [];

    for (int i = 0; i < waypointAddrs.length; i++) {
      final addr = waypointAddrs[i];
      final waypointLatLng = await _getLatLngFromAddress(addr);
      if (waypointLatLng != null) {
        intermediatesPayload.add({"location": {"latLng": {"latitude": waypointLatLng.latitude, "longitude": waypointLatLng.longitude}}});
        waypointDataForStorage.add({'address': addr, 'latitude': waypointLatLng.latitude, 'longitude': waypointLatLng.longitude});
        _addOrUpdateMarker(
            markerId: 'waypoint_firebase_$i',
            position: waypointLatLng,
            title: '経由地 ${i + 1}: $addr',
            iconHue: BitmapDescriptor.hueOrange,
            labelTextForController: addr);
      }
    }
    debugPrint("LOG: APIに渡す経由地(waypointDataForStorage): $waypointDataForStorage");
    await _callGoogleRoutesAPI(
      originPayload, destinationPayload, intermediatesPayload,
      {'address': originAddr, 'latitude': originLatLng.latitude, 'longitude': originLatLng.longitude},
      {'address': destAddr, 'latitude': destinationLatLng.latitude, 'longitude': destinationLatLng.longitude},
      waypointDataForStorage,
      arrivalTime, reservationData, waypointToReservationIndexMap,
    );
  }

  Future<void> _callGoogleRoutesAPI(
      Map<String, dynamic> originPayload,
      Map<String, dynamic> destinationPayload,
      List<Map<String, dynamic>> intermediatesPayload,
      Map<String, dynamic> originForStorage,
      Map<String, dynamic> destinationForStorage,
      List<Map<String, dynamic>> waypointsForStorage,
      DateTime? arrivalTime,
      List<Map<String, dynamic>> reservationData,
      List<int> waypointToReservationIndexMap,
      ) async {
    setStateIfMounted(() { _statusMessage = "Google Routes APIにルートを問い合わせ中..."; });

    final String url = 'https://routes.googleapis.com/directions/v2:computeRoutes';
    final Map<String, String> headers = {
      'Content-Type': 'application/json', 'X-Goog-Api-Key': googleApiKey,
      'X-Goog-FieldMask': 'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline,routes.optimized_intermediate_waypoint_index',
    };
    final Map<String, dynamic> body = {
      "origin": originPayload, "destination": destinationPayload,
      "travelMode": "DRIVE", "routingPreference": "TRAFFIC_AWARE",
      "computeAlternativeRoutes": false, "languageCode": "ja", "polylineQuality": "OVERVIEW",
    };

    if (intermediatesPayload.isNotEmpty) {
      body["intermediates"] = intermediatesPayload;
      body["optimizeWaypointOrder"] = true;
    }

    try {
      final response = await http.post(Uri.parse(url), headers: headers, body: json.encode(body));
      if (response.statusCode == 200) {
        final decodedResponse = json.decode(response.body);
        debugPrint("LOG: Google API Response Body: $decodedResponse");
        if (decodedResponse['routes'] != null && decodedResponse['routes'].isNotEmpty) {
          final route = decodedResponse['routes'][0];
          final double totalDurationSeconds = double.parse((route['duration'] as String).replaceAll('s', ''));

          DateTime? calculatedDepartureTime;
          List<DateTime?> waypointArrivalTimes = List.filled(waypointsForStorage.length, null);

          List<int> rawOptimizedOrder = [];
          if (route['optimizedIntermediateWaypointIndex'] != null) {
            rawOptimizedOrder = (route['optimizedIntermediateWaypointIndex'] as List<dynamic>).map((e) => e as int).toList();
          }

          // ★★★★★ 無効なインデックス(-1など)を排除する安全ガード ★★★★★
          List<int> optimizedOrder = rawOptimizedOrder.where((index) => index >= 0 && index < intermediatesPayload.length).toList();

          if(rawOptimizedOrder.length != optimizedOrder.length) {
            debugPrint("WARN: APIから無効なインデックスが返されたためフィルタリングしました。 API応答: $rawOptimizedOrder -> 修正後: $optimizedOrder");
          }

          if (optimizedOrder.isEmpty && intermediatesPayload.isNotEmpty) {
            optimizedOrder = List.generate(intermediatesPayload.length, (i) => i);
            debugPrint("WARN: APIが有効な訪問順序を返さなかったため、元の順序を利用します。: $optimizedOrder");
          }

          debugPrint("LOG: 最終的な訪問順序(optimizedOrder): $optimizedOrder");

          // 手動逆算ロジック
          if (arrivalTime != null) {
            calculatedDepartureTime = arrivalTime.subtract(Duration(seconds: totalDurationSeconds.toInt()));
            _departureTime = DateFormat('HH:mm').format(calculatedDepartureTime);

            List<Marker> sortedWaypoints = [];
            if (optimizedOrder.isNotEmpty) {
              for(int index in optimizedOrder) {
                // markerIdが 'waypoint_firebase_インデックス番号' の形式であることを期待
                final marker = _markers.firstWhere(
                        (m) => m.markerId.value == 'waypoint_firebase_$index',
                    orElse: () => const Marker(markerId: MarkerId('not_found'))
                );
                if(marker.markerId.value != 'not_found'){
                  sortedWaypoints.add(marker);
                }
              }
            }
            debugPrint("LOG: sortedWaypoints: ${sortedWaypoints.map((m) => m.markerId.value).toList()}");

            DateTime currentLegArrivalTime = arrivalTime;

            final schoolMarker = _markers.firstWhere((m) => m.markerId.value == 'destination_firebase', orElse: () => const Marker(markerId: MarkerId('not_found')));
            if(schoolMarker.markerId.value == 'not_found') throw Exception("目的地のマーカーが見つかりません。");

            Marker? previousPoint = schoolMarker;

            if (sortedWaypoints.isNotEmpty) {
              for (int i = sortedWaypoints.length - 1; i >= 0; i--) {
                Marker currentWaypoint = sortedWaypoints[i];
                debugPrint("LOG: 逆算中... from: ${currentWaypoint.markerId.value}, to: ${previousPoint?.markerId.value}");
                if (previousPoint != null) {
                  double dist = _calculateDistance(
                      currentWaypoint.position.latitude, currentWaypoint.position.longitude,
                      previousPoint.position.latitude, previousPoint.position.longitude
                  );
                  int durationMinutes = (dist * 1.8).round() + 1;
                  DateTime waypointArrivalTime = currentLegArrivalTime.subtract(Duration(minutes: durationMinutes));

                  int? originalIndex = getSafeIndex(currentWaypoint, waypointArrivalTimes.length);
                  debugPrint("LOG: ${currentWaypoint.markerId.value}のSafeIndexは $originalIndex");

                  if (originalIndex != null) {
                    waypointArrivalTimes[originalIndex] = waypointArrivalTime;
                  }
                  currentLegArrivalTime = waypointArrivalTime;
                }
                previousPoint = currentWaypoint;
              }
            }
            debugPrint("LOG: 計算後の到着時刻リスト(waypointArrivalTimes): $waypointArrivalTimes");

            for(int i = 0; i < waypointArrivalTimes.length; i++) {
              DateTime? arrival = waypointArrivalTimes[i];
              if (arrival != null) {
                final markerToUpdate = _markers.firstWhere((m) => m.markerId.value == 'waypoint_firebase_$i', orElse: () => const Marker(markerId: MarkerId('not_found')));
                if (markerToUpdate.markerId.value != 'not_found') {
                  _addOrUpdateMarker(
                    markerId: markerToUpdate.markerId.value,
                    position: markerToUpdate.position,
                    title: markerToUpdate.infoWindow.title ?? "経由地",
                    snippet: '到着目安: ${DateFormat('HH:mm').format(arrival)}',
                    iconHue: BitmapDescriptor.hueOrange,
                    labelTextForController: _waypointControllers.length > i ? _waypointControllers[i].text : null,
                  );
                }
              }
            }
          }

          // Firestoreへの保存
          final routeDocId = '${widget.schoolId}_${DateFormat('yyyy-MM-dd').format(widget.selectedDate)}_${widget.isGoSchool ? 'go' : 'back'}';
          await _firestore.collection('routes').doc(routeDocId).set({
            'schoolId': widget.schoolId, 'isGoSchool': widget.isGoSchool, 'routeDate': Timestamp.fromDate(widget.selectedDate),
            'createdAt': FieldValue.serverTimestamp(), 'driverId': _auth.currentUser?.uid,
            'origin': originForStorage, 'destination': destinationForStorage, 'waypoints': waypointsForStorage,
            'optimizedWaypointOrder': optimizedOrder, 'polyline': route['polyline']['encodedPolyline'],
            'totalDistanceMeters': route['distanceMeters'], 'totalDurationSeconds': totalDurationSeconds,
            'recommendedDepartureTime': calculatedDepartureTime != null ? Timestamp.fromDate(calculatedDepartureTime) : null,
          });

          WriteBatch reservationBatch = _firestore.batch();
          if (calculatedDepartureTime != null) {
            for (int i = 0; i < optimizedOrder.length; i++) {
              int originalWaypointIndex = optimizedOrder[i];
              // ★★★★★ ここでも安全チェックを追加 ★★★★★
              if (originalWaypointIndex >= 0 && originalWaypointIndex < waypointToReservationIndexMap.length) {
                int reservationIndex = waypointToReservationIndexMap[originalWaypointIndex];
                if (reservationIndex < reservationData.length) {
                  String reservationId = reservationData[reservationIndex]['id'];
                  if (originalWaypointIndex < waypointArrivalTimes.length) {
                    DateTime? arrivalTimeAtWaypoint = waypointArrivalTimes[originalWaypointIndex];
                    if(arrivalTimeAtWaypoint != null) {
                      reservationBatch.update(_firestore.collection('reservations').doc(reservationId), {
                        'recommendedDepartureTime': Timestamp.fromDate(calculatedDepartureTime),
                        'estimatedArrivalTimeAtWaypoint': Timestamp.fromDate(arrivalTimeAtWaypoint),
                      });
                    }
                  }
                }
              }
            }
          }
          await reservationBatch.commit();

          // UI更新
          final String totalDistanceText = "${(route['distanceMeters'] / 1000).toStringAsFixed(1)} km";
          final int totalMinutes = (totalDurationSeconds / 60).round();
          final String totalDurationText = (totalMinutes >= 60) ? "${(totalMinutes / 60).floor()}時間 ${totalMinutes % 60}分" : "$totalMinutes分";
          _polylineCoordinates = PolylinePoints().decodePolyline(route['polyline']['encodedPolyline']).map((p) => LatLng(p.latitude, p.longitude)).toList();

          if (_polylineCoordinates.isNotEmpty) {
            setStateIfMounted(() {
              _polylines.add(Polyline(polylineId: const PolylineId('route_firebase'), points: _polylineCoordinates, color: Theme.of(context).colorScheme.primary, width: 7));
              _distance = totalDistanceText;
              _duration = totalDurationText;
              _statusMessage = "ルートが見つかりました。";
            });
            _mapController?.animateCamera(CameraUpdate.newLatLngBounds(_getBoundsForRouteMarkers(), 70.0));
          } else {
            throw Exception("APIから有効なポリラインデータが返されませんでした。");
          }
        } else {
          throw Exception("APIからルートが見つかりませんでした: ${decodedResponse['error']?['message'] ?? '詳細不明'}");
        }
      } else {
        throw Exception("Routes APIエラー: ${response.statusCode}, ${response.body}");
      }
    } catch (e, stackTrace) {
      debugPrint("APIコールエラー: $e");
      debugPrint("スタックトレース: $stackTrace");
      _handleError("ルート検索APIエラー: ${e.toString().replaceFirst("Exception: ", "")}");
    }
  }

  /// 2点間の直線距離を計算(km)
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295; // Math.PI / 180
    final a = 0.5 - cos((lat2 - lat1) * p)/2 +
        cos(lat1 * p) * cos(lat2 * p) *
            (1 - cos((lon2 - lon1) * p))/2;
    return 12742 * asin(sqrt(a)); // 2 * R; R = 6371 km
  }

  /// Markerから安全にインデックスを取得
  int? getSafeIndex(Marker marker, int maxLength) {
    try {
      final id = marker.markerId.value;
      if (!id.startsWith('waypoint_firebase_')) return null;

      final lastPart = id.split('_').last;
      final index = int.tryParse(lastPart);

      if (index == null || index < 0 || index >= maxLength) {
        debugPrint("LOG: getSafeIndex - 無効なインデックス($index)です。maxLength: $maxLength");
        return null;
      }
      return index;
    } catch (e) {
      debugPrint("LOG: getSafeIndex - パースエラー: $e");
      return null;
    }
  }


  Future<void> _startDriving() async {
    if (!await _handleLocationPermission()) return;
    if (_isDriving) return;
    if (_auth.currentUser == null) return _showErrorSnackbar("ログインしていません。");
    final driverId = _auth.currentUser!.uid;

    setState(() => _isDriving = true);
    try {
      await _databaseReference.child('driverLocations/$driverId/isDriving').set(true);
      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
      ).listen((Position position) {
        if (!mounted) return;
        _currentPosition = LatLng(position.latitude, position.longitude);
        _addOrUpdateMarker(
          markerId: "currentLocation",
          position: _currentPosition!,
          title: "現在地 (走行中)",
          iconHue: BitmapDescriptor.hueGreen,
        );
        _updateLocationToDatabase(driverId, position);
        setState(() {});
      });
      _showErrorSnackbar('走行を開始しました。', isError: false);
      setStateIfMounted(() => _statusMessage = "走行中...");
    } catch (e) {
      _showErrorSnackbar('走行開始に失敗しました: $e');
      if (mounted) setState(() => _isDriving = false);
    }
  }

  Future<void> _stopDriving() async {
    if (!_isDriving) return;
    if (_auth.currentUser == null) return _showErrorSnackbar("ログイン情報が無効です。");
    final driverId = _auth.currentUser!.uid;

    setState(() => _isDriving = false);
    try {
      await _positionStreamSubscription?.cancel();
      _positionStreamSubscription = null;
      await _databaseReference.child('driverLocations/$driverId/isDriving').set(false);
      if (_currentPosition != null) {
        await _databaseReference.child('driverLocations/$driverId').update({
          'latitude': _currentPosition!.latitude,
          'longitude': _currentPosition!.longitude,
          'timestamp': ServerValue.timestamp,
        });
        _addOrUpdateMarker(
          markerId: "currentLocation",
          position: _currentPosition!,
          title: "現在地 (停止中)",
          iconHue: BitmapDescriptor.hueAzure,
        );
      }
      _showErrorSnackbar('走行を完了しました。', isError: false);
      setStateIfMounted(() => _statusMessage = "停止中");
    } catch (e) {
      _showErrorSnackbar('走行完了処理に失敗しました: $e');
    }
  }

  Future<void> _updateLocationToDatabase(String driverId, Position position) async {
    if (!_isDriving) return;
    try {
      await _databaseReference.child('driverLocations/$driverId').update({
        'latitude': position.latitude, 'longitude': position.longitude,
        'timestamp': ServerValue.timestamp, 'isDriving': true,
      });
    } catch (e) {
      debugPrint("DBへの位置情報更新エラー: $e");
    }
  }

  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showErrorSnackbar('位置情報サービスが無効です。'); return false;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showErrorSnackbar('位置情報の権限が拒否されました。'); return false;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      _showErrorSnackbar('位置情報の権限が恒久的に拒否されています。設定から許可してください。'); return false;
    }
    return true;
  }

  void _showErrorSnackbar(String message, {bool isError = true}) {
    if (mounted) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : Colors.green,
        duration: const Duration(seconds: 3),
      ));
    }
  }

  LatLngBounds _getBoundsForRouteMarkers() {
    List<LatLng> points = _markers.map((m) => m.position).toList();
    if (points.isEmpty) return LatLngBounds(southwest: _initialCameraPosition.target, northeast: _initialCameraPosition.target);
    return _calculateBoundsFromPoints(points);
  }

  LatLngBounds _calculateBoundsFromPoints(List<LatLng> points) {
    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;
    for (var point in points) {
      minLat = point.latitude < minLat ? point.latitude : minLat;
      maxLat = point.latitude > maxLat ? point.latitude : maxLat;
      minLng = point.longitude < minLng ? point.longitude : minLng;
      maxLng = point.longitude > maxLng ? point.longitude : maxLng;
    }
    return LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    bool isApiKeyValidAndSet = googleApiKey.isNotEmpty && !googleApiKey.startsWith("YOUR_GOOGLE_MAPS_API_KEY");

    return Scaffold(
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text("${DateFormat.yMEd('ja').format(widget.selectedDate)} ${widget.isGoSchool ? '登校' : '下校'}ルート"),
        ),
        backgroundColor: theme.colorScheme.primaryContainer,
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 20.0),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))),
            )
        ],
      ),
      body: !isApiKeyValidAndSet
          ? _buildApiKeyMissingWidget(theme)
          : Column(
        children: [
          _buildControlPanel(theme),
          if(_distance.isNotEmpty || _duration.isNotEmpty) _buildRouteInfoPanel(theme),
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  mapType: MapType.normal,
                  initialCameraPosition: _initialCameraPosition,
                  onMapCreated: (GoogleMapController controller) {
                    _mapController = controller;
                    if (_currentPosition != null) {
                      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_currentPosition!, 15));
                    }
                  },
                  markers: _markers,
                  polylines: _polylines,
                  myLocationEnabled: false,
                  myLocationButtonEnabled: true,
                  zoomControlsEnabled: true,
                  padding: EdgeInsets.only(bottom: _distance.isNotEmpty ? 75 : 15),
                ),
                if (_isLoading)
                  Positioned.fill(
                    child: Container(
                      color: Colors.white.withOpacity(0.8),
                      child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const CircularProgressIndicator(), const SizedBox(height: 20), Text(_statusMessage, style: theme.textTheme.titleMedium)])),
                    ),
                  ),
                if (!_isLoading && _polylines.isEmpty)
                  Positioned.fill(
                    child: Container(
                      color: Colors.white.withOpacity(0.8),
                      child: Center(child: Padding(padding: const EdgeInsets.all(20.0), child: Text(_statusMessage, style: theme.textTheme.titleMedium, textAlign: TextAlign.center,))),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel(ThemeData theme) {
    return Material(
      elevation: 2.0,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: Icon(_isDriving ? Icons.stop_rounded : Icons.play_arrow_rounded),
                    label: Text(_isDriving ? '走行完了' : '走行開始'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isDriving ? Colors.red : Colors.green,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    onPressed: _isLoading || _polylineCoordinates.isEmpty ? null : (_isDriving ? _stopDriving : _startDriving),
                  ),
                ),
              ],
            ),
            // ExpansionTile(
            //   tilePadding: EdgeInsets.zero,
            //   title: Text("表示されているルート", style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
            //   leading: Icon(Icons.route_rounded, color: theme.colorScheme.secondary),
            //   initiallyExpanded: false,
            //   children: [
            //     _buildTextField(controller: _originController, labelText: '出発地', readOnly: true, theme: theme, icon: Icons.trip_origin),
            //     const SizedBox(height: 8),
            //     ..._waypointControllers.map((c) => Padding(
            //       padding: const EdgeInsets.only(bottom: 8.0),
            //       child: _buildTextField(controller: c, labelText: '経由地', readOnly: true, theme: theme, icon: Icons.pin_drop),
            //     )).toList(),
            //     _buildTextField(controller: _destinationController, labelText: '目的地', readOnly: true, theme: theme, icon: Icons.flag_rounded),
            //   ],
            // ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteInfoPanel(ThemeData theme) {
    if ((_distance.isEmpty && _duration.isEmpty) && !_isLoading) return const SizedBox.shrink();
    if (_isLoading && _distance.isEmpty && _duration.isEmpty) return const SizedBox.shrink();
    if (_distance.isEmpty && _duration.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 12.0),
      margin: const EdgeInsets.fromLTRB(10, 5, 10, 8),
      decoration: BoxDecoration(color: theme.colorScheme.secondaryContainer.withOpacity(0.9), borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 4))]),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        if (_departureTime.isNotEmpty) ...[
          _buildInfoItem(icon: Icons.access_time_filled_rounded, value: _departureTime, label: '推奨出発時刻', theme: theme),
          Container(height: 45, width: 1.5, color: theme.dividerColor.withOpacity(0.6)),
        ],
        _buildInfoItem(icon: Icons.linear_scale_rounded, value: _distance, label: '総距離', theme: theme),
        Container(height: 45, width: 1.5, color: theme.dividerColor.withOpacity(0.6)),
        _buildInfoItem(icon: Icons.timer_outlined, value: _duration, label: '推定所要時間', theme: theme),
      ]),
    );
  }

  Widget _buildInfoItem({required IconData icon, required String value, required String label, required ThemeData theme}) {
    return Expanded(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: theme.colorScheme.onSecondaryContainer, size: 28),
      const SizedBox(height: 4),
      Text(value, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSecondaryContainer, fontWeight: FontWeight.bold, fontSize: 16.5)),
      const SizedBox(height: 1),
      Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSecondaryContainer.withOpacity(0.85), fontSize: 12)),
    ]));
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String labelText,
    required IconData icon,
    required ThemeData theme,
    bool readOnly = false,
  }) {
    return TextFormField(
      controller: controller, readOnly: readOnly,
      decoration: InputDecoration(
        labelText: labelText,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: readOnly ? theme.colorScheme.surface.withOpacity(0.5) : theme.colorScheme.surfaceVariant.withOpacity(0.35),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildApiKeyMissingWidget(ThemeData theme) {
    return Center(child: Padding(padding: const EdgeInsets.all(24.0), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.vpn_key_off_rounded, color: Colors.red, size: 60),
      const SizedBox(height: 20),
      Text("APIキーが設定されていません", style: theme.textTheme.headlineSmall?.copyWith(color: Colors.red, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
      const SizedBox(height: 15),
      const Text("この機能には有効なGoogle Maps APIキーが必要です。", textAlign: TextAlign.center),
    ])));
  }
}
