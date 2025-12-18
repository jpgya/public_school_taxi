import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/reservation.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> addReservation(Reservation reservation) {
    return _db.collection('reservations').add(reservation.toMap());
  }

  Stream<List<Reservation>> getReservations(String userId) {
    return _db
        .collection('reservations')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
        snapshot.docs.map((doc) => Reservation.fromMap(doc.id, doc.data())).toList());
  }
}