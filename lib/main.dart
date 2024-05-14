import 'dart:ffi';
import 'dart:io' as io;
import 'dart:isolate';
import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:tuple/tuple.dart';
import 'package:recase/recase.dart';

import 'package:flutter_notification_listener/flutter_notification_listener.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
      home: NotificationsLog(),
    );
  }
}

class NotificationsLog extends StatefulWidget {
  @override
  _NotificationsLogState createState() => _NotificationsLogState();
}

class _NotificationsLogState extends State<NotificationsLog> {
  List<NotificationEvent> _log = [];
  List<NotificationEvent> _processableNotifications = [];
  List<String> _processablePackages = ["com.nu.production"];
  bool started = false;
  bool _loading = false;

  ReceivePort port = ReceivePort();

  @override
  void initState() {
    initPlatformState();
    super.initState();
  }

  // we must use static method, to handle in background
  @pragma(
      'vm:entry-point') // prevent dart from stripping out this function on release build in Flutter 3.x
  static void _callback(NotificationEvent evt) {
    print("send evt to ui: $evt");
    final SendPort? send = IsolateNameServer.lookupPortByName("_listener_");
    if (send == null) print("can't find the sender");
    send?.send(evt);
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    NotificationsListener.initialize(callbackHandle: _callback);

    // this can fix restart<debug> can't handle error
    IsolateNameServer.removePortNameMapping("_listener_");
    IsolateNameServer.registerPortWithName(port.sendPort, "_listener_");
    port.listen((message) => onData(message));

    // don't use the default receivePort
    // NotificationsListener.receivePort.listen((evt) => onData(evt));

    var isRunning = (await NotificationsListener.isRunning) ?? false;
    print("""Service is ${!isRunning ? "not " : ""}already running""");

    setState(() {
      started = isRunning;
    });
  }

  void onData(NotificationEvent event) async {
    bool shouldProcess = shouldProcessNotification(event);

    final id = await insertNotification(event, shouldProcess);
    print("INSERTED NOTIFICATION ID $id");

    var docDirectory = await getApplicationDocumentsDirectory();
    print(docDirectory);

    if (shouldProcess) {
      _processableNotifications.add(event);

      processNotification(event, id);
    }

    setState(() {
      _log.add(event);
    });

    print("**************");
    print(event.toString());
  }

  bool shouldProcessNotification(NotificationEvent event) =>
      _processablePackages.contains(event.packageName);

  void startListening() async {
    print("start listening");
    setState(() {
      _loading = true;
    });
    var hasPermission = (await NotificationsListener.hasPermission) ?? false;
    if (!hasPermission) {
      print("no permission, so open settings");
      NotificationsListener.openPermissionSettings();
      return;
    }

    var isRunning = (await NotificationsListener.isRunning) ?? false;

    if (!isRunning) {
      await NotificationsListener.startService(
          foreground: false,
          title: "Listener Running",
          description: "Welcome to having me");
    }

    setState(() {
      started = true;
      _loading = false;
    });
  }

  void stopListening() async {
    print("stop listening");

    setState(() {
      _loading = true;
    });

    await NotificationsListener.stopService();

    setState(() {
      started = false;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Listener Example'),
        actions: [
          IconButton(
              onPressed: () {
                // Create a mock notification
                NotificationEvent mockNotification = newEvent({
                  "title": 'Compra aprobada',
                  "text": 'Compraste en AMAZON con tu tarjeta por \$500.00',
                  "package_name": "com.nu.production",
                  "channelId": 'Mock Channel',
                  "flags": 0,
                  "canTap": true,
                  "uid": 10168,
                  "id": 123,
                  "isGroup": false,
                  "key": "0|com.google.android.as|123|null|10168",
                  "timestamp": 1715641845543,
                  "hasLargeIcon": false
                });

                onData(mockNotification);
              },
              icon: Icon(Icons.work))
        ],
      ),
      body: Center(
          child: ListView.builder(
              itemCount: _log.length,
              reverse: true,
              itemBuilder: (BuildContext context, int idx) {
                final entry = _log[idx];
                return ListTile(
                    onTap: () {
                      entry.tap();
                    },
                    title: Container(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.title ?? "<<no title>>"),
                          Text(entry.text ?? "<<no text>>"),
                          Text(entry.createAt.toString().substring(0, 19)),
                          Text("Package name: ${entry.packageName.toString()}"),
                          Text("Channel ID: ${entry.channelId.toString()}"),
                          SizedBox(height: 30),
                        ],
                      ),
                    ));
              })),
      floatingActionButton: FloatingActionButton(
        onPressed: started ? stopListening : startListening,
        tooltip: 'Start/Stop sensing',
        child: _loading
            ? Icon(Icons.close)
            : (started ? Icon(Icons.stop) : Icon(Icons.play_arrow)),
      ),
    );
  }

  int getAmountFromNotification(NotificationEvent event) {
    final RegExp regex = RegExp(r'\$([\d,]+(\.\d{1,2})?)');
    final match = regex.firstMatch(event.text ?? '');
    var multipliedAmount = 0;
    if (match != null) {
      final amount = double.parse(match.group(1) ?? ''); // Convert to double
      multipliedAmount = (amount * 1000).toInt(); // Multiply by 100
      print('Extracted amount: $amount, Multiplied amount: $multipliedAmount');
    }
    return multipliedAmount;
  }

  String getDateFromNotification(NotificationEvent event) {
    final timestamp = event.timestamp;
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp!);
    final formattedDate = date.toIso8601String();
    print('Extracted date: $formattedDate');
    return formattedDate;
  }

  String getPayeeFromNotification(NotificationEvent event) {
    final RegExp placeRegex = RegExp(r'Compraste en ([A-Z]+) con tu tarjeta');
    final placeMatch = placeRegex.firstMatch(event.text ?? '');
    var place = '';
    if (placeMatch != null) {
      place = placeMatch.group(1) ?? '';
      print('Extracted place: $place');
    }
    return place;
  }

  Tuple2<Future<http.Response>, String> createTransaction(
      int multipliedAmount, String place, String date) {
    final requestBody = {
      "transaction": {
        "account_id": "41821ce0-c429-4b95-84be-6c26c97a94bd",
        "date": date,
        "amount": multipliedAmount,
        "payee_name": ReCase(place).titleCase,
        "memo": "automatically added"
      }
    };
    return Tuple2(
        http.post(
            Uri.parse("https://api.ynab.com/v1/budgets/last-used/transactions"),
            headers: {
              "Authorization":
                  "Bearer 0SYXrq5cWchr5Wf_W1QKXuCgBwjPSPgfHkmUQKFS7t0",
              "Content-Type": "application/json"
            },
            body: jsonEncode(requestBody)),
        jsonEncode(requestBody));
  }

  void processNotification(NotificationEvent event, int notificationId) {
    if (event.title?.startsWith("Compra aprobada") ?? false) {
      final amount = getAmountFromNotification(event);
      final payee = getPayeeFromNotification(event);
      final date = getDateFromNotification(event);

      final transactionResult = createTransaction(amount, payee, date);
      transactionResult.item1.then((response) {
        if (response.statusCode == 200 || response.statusCode == 201) {
          print("HTTP request successful");

          var jsonResponse = jsonDecode(response.body);
          print(jsonResponse);

          insertTransaction(notificationId, date, amount, payee,
              response.statusCode, transactionResult.item2, response.body);
        } else {
          print("HTTP request failed");
          var jsonResponse = jsonDecode(response.body);
          print(jsonResponse);

          insertTransaction(notificationId, date, amount, payee,
              response.statusCode, transactionResult.item2, response.body);
        }
      }).catchError((error) {
        print("Error making HTTP request: $error");

        insertTransaction(notificationId, date, amount, payee, 500,
            transactionResult.item2, jsonEncode(error));
      });
    }
  }
}

/* Database */

class DBHelper {
  static Database? _db = null;

  Future<Database?> get db async {
    if (_db != null) {
      return _db;
    }
    _db = await initDatabase();
    return _db;
  }

  initDatabase() async {
    io.Directory docDirectory = await getApplicationDocumentsDirectory();

    String databasePath = path.join(docDirectory.path, 'database.db');
    print(databasePath);
    var ourDb =
        await openDatabase(databasePath, version: 1, onCreate: _onCreate);
    return ourDb;
  }

  void _onCreate(Database db, int version) async {
    // When creating the db, create the table
    await db.execute(
        'CREATE TABLE Notification(id INTEGER PRIMARY KEY, title TEXT, text TEXT, package_name TEXT, channel_id TEXT, processed INTEGER, raw_notification_json TEXT)');

    await db.execute(
        'CREATE TABLE YnabTransaction(id INTEGER PRIMARY KEY, notification_id INTEGER, date TEXT, amount INTEGER, payee TEXT, http_status INTEGER, raw_request_json TEXT, raw_response_json TEXT, FOREIGN KEY(notification_id) REFERENCES Notification(id))');
  }
}

Future<int> insertNotification(NotificationEvent evt, bool processed) async {
  // Get a reference to the database.
  DBHelper dbHelper = DBHelper();
  final Database? db = await dbHelper.db;

  // Create a Map with the data you want to insert.
  Map<String, dynamic> map = {
    'title': evt.title,
    'text': evt.text,
    'package_name': evt.packageName,
    'channel_id': evt.channelId,
    'processed': processed ? 1 : 0,
    'raw_notification_json':
        jsonEncode(evt.raw.toString()), // convert the event to a JSON string
  };

  // Insert the Map into the database and get the id of the new record.
  int id = await db!.insert('Notification', map);

  print("NOTIFICATION INSERTED");
  return id;
}

Future<int> insertTransaction(
    int notificationId,
    String date,
    int amount,
    String payee,
    int httpStatus,
    String rawRequestJson,
    String rawResponseJson) async {
  // Get a reference to the database.
  DBHelper dbHelper = DBHelper();
  final Database? db = await dbHelper.db;

  // Create a Map with the data you want to insert.
  Map<String, dynamic> map = {
    'notification_id': notificationId,
    'date': date,
    'amount': amount,
    'payee': payee,
    'http_status': httpStatus,
    'raw_request_json': rawRequestJson,
    'raw_response_json': rawResponseJson,
  };

  // Insert the Map into the database and get the id of the new record.
  int id = await db!.insert('YnabTransaction', map);

  return id;
}
