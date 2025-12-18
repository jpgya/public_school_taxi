// lib/local/jititai_tab_content.dart

import 'dart:math';
import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// --- データモデルクラス ---
class RideRecord {
  final DateTime date;
  final String vehicle; // タクシー会社名
  final double distance;
  final int passengers;
  final int fee; // 利用者負担額合計

  RideRecord({
    required this.date,
    required this.vehicle,
    required this.distance,
    required this.passengers,
    required this.fee,
  });
}

// --- メインのStatefulWidgetクラス ---
class JititaiTabContent extends StatefulWidget {
  final String jititaiName;

  const JititaiTabContent({Key? key, required this.jititaiName}) : super(key: key);

  @override
  _JititaiTabContentState createState() => _JititaiTabContentState();
}

class _JititaiTabContentState extends State<JititaiTabContent> {
  // UIの状態
  bool _isLoading = false;
  bool _isPriceLocked = true;

  // ユーザーが選択する値
  int _priceValue = 500; // ユーザー1回あたりの料金（初期値）
  DateTime _selectedDate = DateTime.now();

  // ダミーデータから生成されるデータ
  List<RideRecord> _rideRecords = [];
  Map<String, int> _taxiCompanyTotals = {}; // 自治体->タクシー会社への支払い合計
  int _userTotalFee = 0; // 利用者->自治体への支払い合計

  @override
  void initState() {
    super.initState();
    // 初期データを生成
    _generateDummyDataForSelectedMonth();
  }

  // 選択された年月に基づいてダミーデータを生成・再計算するメソッド
  void _generateDummyDataForSelectedMonth() {
    setState(() => _isLoading = true);

    // 意図的に少し待機して、ローディングインジケータを見せる
    Future.delayed(const Duration(milliseconds: 300), () {
      final List<RideRecord> records = [];
      final Map<String, int> taxiTotals = {};
      int userTotal = 0;
      final random = Random();

      final taxiCompanies = ['村田タクシー', '柴田タクシー'];

      // 選択された月に応じて15〜29件のランダムな件数のデータを生成
      int numberOfRecords = 15 + random.nextInt(15);
      int daysInMonth = DateTime(_selectedDate.year, _selectedDate.month + 1, 0).day;

      for (int i = 0; i < numberOfRecords; i++) {
        final day = random.nextInt(daysInMonth) + 1;
        final date = DateTime(_selectedDate.year, _selectedDate.month, day, random.nextInt(10) + 8);

        final distance = 5 + random.nextDouble() * 25; // 5kmから30km
        final passengers = random.nextInt(4) + 1; // 1〜4人
        final company = taxiCompanies[random.nextInt(taxiCompanies.length)];

        // 料金計算
        final int totalUserFee = _priceValue * passengers; // 利用者負担 = 設定料金 x 乗客数
        final int taxiFee = (distance * 120).round(); // 自治体負担 (タクシー代) = 距離 x 120円 (仮の計算)

        records.add(RideRecord(
          date: date,
          vehicle: company,
          distance: distance,
          passengers: passengers,
          fee: totalUserFee,
        ));

        userTotal += totalUserFee;
        taxiTotals.update(company, (value) => value + taxiFee, ifAbsent: () => taxiFee);
      }

      // テーブルの表示順を日付の降順にする
      records.sort((a, b) => b.date.compareTo(a.date));

      setState(() {
        _rideRecords = records;
        _taxiCompanyTotals = taxiTotals;
        _userTotalFee = userTotal;
        _isLoading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // 料金サマリー表示用のウィジェットリストを動的に生成
    List<Widget> summaryWidgets = _taxiCompanyTotals.entries.map((entry) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '自治体 → ${entry.key}：¥${NumberFormat("#,###").format(entry.value)}',
          style: const TextStyle(fontSize: 24.0),
        ),
      );
    }).toList();


    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '自治体名：${widget.jititaiName}',
              style: const TextStyle(fontSize: 27.0, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            // --- 料金設定セクション ---
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text('料金設定：', style: TextStyle(fontSize: 24.0)),
                SizedBox(
                  width: 50,
                  height: 40,
                  child: AbsorbPointer(
                    absorbing: _isPriceLocked,
                    child: Opacity(
                      opacity: _isPriceLocked ? 0.5 : 1.0,
                      child: CupertinoPicker(
                        itemExtent: 30,
                        scrollController: FixedExtentScrollController(
                          initialItem: _priceValue > 0 ? _priceValue ~/ 10 : 0,
                        ),
                        onSelectedItemChanged: (int index) {
                          if (!_isPriceLocked) {
                            setState(() => _priceValue = index * 10);
                          }
                        },
                        children: List.generate(101, (i) => Center(child: Text('${i * 10}'))),
                      ),
                    ),
                  ),
                ),
                const Text('円/回', style: TextStyle(fontSize: 24.0)),
                const Spacer(),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _isPriceLocked = !_isPriceLocked;
                      if (_isPriceLocked) {
                        // 「決定」が押されたので、データを再計算・再描画
                        _generateDummyDataForSelectedMonth();
                      }
                    });
                  },

                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isPriceLocked ? Colors.grey[400] : Colors.orange,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  child: Text(
                    _isPriceLocked ? '変更' : '決定',
                    style: const TextStyle(fontSize: 18.0, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // --- 利用履歴セクション ---
            Row(
              children: [
                const Text('利用履歴：', style: TextStyle(fontSize: 24.0)),
                SizedBox(
                  width: 50,
                  height: 50,
                  child: CupertinoPicker(
                    itemExtent: 30,
                    scrollController: FixedExtentScrollController(initialItem: _selectedDate.year - 2024),
                    onSelectedItemChanged: (index) {
                      final newYear = 2024 + index;
                      setState(() {
                        _selectedDate = DateTime(newYear, _selectedDate.month);
                      });
                      _generateDummyDataForSelectedMonth(); // 年が変わったらデータを再生成
                    },
                    children: List.generate(5, (i) => Center(child: Text('${2024 + i}'))),
                  ),
                ),
                const Text('年', style: TextStyle(fontSize: 24.0)),
                SizedBox(
                  width: 70,
                  height: 50,
                  child: CupertinoPicker(
                    itemExtent: 30,
                    scrollController: FixedExtentScrollController(initialItem: _selectedDate.month - 1),
                    onSelectedItemChanged: (index) {
                      final newMonth = index + 1;
                      setState(() {
                        _selectedDate = DateTime(_selectedDate.year, newMonth);
                      });
                      _generateDummyDataForSelectedMonth(); // 月が変わったらデータを再生成
                    },
                    children: List.generate(12, (i) => Center(child: Text('${i + 1}'))),
                  ),
                ),
                const Text('月', style: TextStyle(fontSize: 24.0)),
              ],
            ),
            const SizedBox(height: 20),
            // --- 利用履歴テーブル ---
            Container(
              decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
              child: _isLoading
                  ? const SizedBox(height: 300, child: Center(child: CircularProgressIndicator()))
                  : ScrollableRideTable(records: _rideRecords),
            ),
            const SizedBox(height: 30),
            // --- 料金サマリーセクション ---
            const Text("料金サマリー", style: TextStyle(fontSize: 22.0, fontWeight: FontWeight.bold)),
            const Divider(),
            if (_isLoading)
              const Center(child: Text("計算中..."))
            else ...[
              ...summaryWidgets,
              if (summaryWidgets.isEmpty)
                const Text("タクシーの利用実績はありません。", style: TextStyle(fontSize: 24.0)),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '利用者 → 自治体：¥${NumberFormat("#,###").format(_userTotalFee)}',
                  style: const TextStyle(fontSize: 24.0, color: Colors.green, fontWeight: FontWeight.bold),
                ),
              ),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}


// --- テーブル表示用のStatelessWidget ---
// --- テーブル表示用のStatelessWidget (DataTable2を使用) ---
class ScrollableRideTable extends StatelessWidget {
  final List<RideRecord> records;

  const ScrollableRideTable({Key? key, required this.records}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 300, // テーブル全体の高さを指定
      child: DataTable2(
        columnSpacing: 12,
        horizontalMargin: 12,
  
        fixedTopRows: 1, // ★★★ ヘッダーを固定 ★★★
        columns: const [
          DataColumn2(
            label: Center(child: Text('日付')),
            size: ColumnSize.M, // 列のサイズを調整
          ),
          DataColumn2(
            label: Center(child: Text('車両')),
            size: ColumnSize.M, // 長い会社名のために広めのサイズ
          ),
          DataColumn2(
            label: Center(child: Text('距離')),
            size: ColumnSize.M,
            numeric: true,
          ),
          DataColumn2(
            label: Center(child: Text('乗客数')),
            size: ColumnSize.M,
            numeric: true,
          ),
          DataColumn2(
            label: Center(child: Text('利用者負担')),
            size: ColumnSize.M,
            numeric: true,
          ),
        ],
        rows: records.map((record) {
          return DataRow2(
            cells: [
              DataCell(Text(DateFormat('MM/dd').format(record.date))),
              // Tooltipで長い会社名も表示できるようにする
              DataCell(Tooltip(
                message: record.vehicle,
                child: Text(record.vehicle, overflow: TextOverflow.ellipsis),
              )),
              DataCell(FittedBox(child: Text('${record.distance.toStringAsFixed(1)}km'))),
              DataCell(Text('${record.passengers}人')),
              DataCell(Text('¥${NumberFormat("#,###").format(record.fee)}')),
            ],
          );
        }).toList(),
      ),
    );
  }
}

