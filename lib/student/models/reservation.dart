class Reservation {
  Reservation({
    required this.id,
    required this.userId,
    required this.dates,
    required this.goSchool,
    required this.backSchool,
    this.backTime,
  });
  final String id;
  final String userId;
  final List<DateTime> dates;
  final bool goSchool;
  final bool backSchool;
  final String? backTime;

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'dates': dates.map((d) => d.toIso8601String()).toList(),
      'goSchool': goSchool,
      'backSchool': backSchool,
      'backTime': backTime,
      'createdAt': DateTime.now(),
    };
  }

  factory Reservation.fromMap(String id, Map<String, dynamic> map) {
    return Reservation(
      id: id,
      userId: map['userId'],
      dates: List<String>.from(map['dates'])
          .map((s) => DateTime.parse(s))
          .toList(),
      goSchool: map['goSchool'],
      backSchool: map['backSchool'],
      backTime: map['backTime'],
    );
  }
}