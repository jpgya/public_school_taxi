import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:school_taxi/button.dart';
import 'package:school_taxi/change.dart';
import 'package:school_taxi/local/local.dart';
import 'package:school_taxi/student/student.dart';
import 'package:school_taxi/taxiDriver/taxi_driver.dart';

import 'firebase_options.dart';

void main() async{
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await initializeDateFormatting('ja_JP',null);
  runApp(
      const ProviderScope(
          child: MyApp(),
      )
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
       fontFamily: "Noto Sans JP",
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      debugShowCheckedModeBanner: false,
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
      
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SingleChildScrollView(
          child: Center(

            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: <Widget>[
                FittedBox(child: Image.asset('images/icon.jpg'),),
                SizedBox(
                  height: MediaQuery.of(context).size.width * 5 / 5,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly ,
                    children: [

                      SizedBox(
                        height: 80,
                        width: MediaQuery.of(context).size.width * 4 / 5,
                        child: Padding(
                          padding: const EdgeInsets.all(10.0),
                          child: NavigateButton(title: "生徒", next: StudentPage(title: "生徒"), buttonColor: Colors.blue, textColor: Colors.white),
                        ),
                      ),
                      SizedBox(
                         height: 80,
                         width: MediaQuery.of(context).size.width * 4 / 5,
                          child: Padding(
                            padding: const EdgeInsets.all(10.0),
                            child: NavigateButton(title: "タクシー", next: TaxiDriverPage(title: "タクシー"), buttonColor: Colors.green, textColor: Colors.white,),
                          ),
                      ),
                      SizedBox(
                        height: 80,
                        width: MediaQuery.of(context).size.width * 4 / 5,
                        child: Padding(
                          padding: const EdgeInsets.all(10.0),
                          child: NavigateButton(title: "自治体", next: LocalPage(title: "自治体"), buttonColor: Colors.orange, textColor: Colors.white,),
                        ),
                      ),
                    ],
                  ),
                ),

              ],
            ),
          ),
        ),
      ),
    );
  }
}