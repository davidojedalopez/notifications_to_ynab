import 'dart:io' as io;
import 'dart:isolate';
import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:tuple/tuple.dart';
import 'package:recase/recase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_notification_listener/flutter_notification_listener.dart';
import 'configuration_screen.dart';
import 'globals.dart' as global;

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
    return MaterialApp(initialRoute: '/', routes: {
      '/': (context) => NotificationsLog(),
      '/configuration': (context) => ConfigurationScreen(),
    });
  }
}

class NotificationsLog extends StatefulWidget {
  @override
  _NotificationsLogState createState() => _NotificationsLogState();
}

class _NotificationsLogState extends State<NotificationsLog> {
  List<NotificationEvent> _log = [];
  List<NotificationEvent> _processableNotifications = [];
  final List<String> _processablePackages =
      global.packages.map((package) => package['packageName']!).toList();
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
          foreground: true,
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
        actions: <Widget>[
          IconButton(
              onPressed: () {
                /* Nu */
                /* NotificationEvent mockNotification = newEvent({
                  "title": 'Compra aprobada por \$155.00',
                  "text":
                      'Compraste en ALTURA PADEL CLUB con tu tarjeta por \$155.00',
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
                }); */

                /* BBVA */
                NotificationEvent mockNotification = newEvent({
                  "title": 'Compra en',
                  "text": 'COMPRA TDC EN JAPAC MU \$276.00 15 mayo 02:19h',
                  "package_name": "com.bancomer.mbanking",
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
              icon: const Icon(Icons.work)),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.pushNamed(context,
                  '/configuration'); // Navigate to the configuration screen when the settings icon is pressed
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
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
                    ),
                  );
                },
              ),
            ),
          )
        ],
      ),
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
    final String? regexSource = global.packages.firstWhere((package) =>
        package['packageName'] == event.packageName)['amountRegex'];
    final RegExp regex = RegExp(regexSource!, caseSensitive: false);

    final match = regex.firstMatch(event.text ?? '');
    var multipliedAmount = 0;
    if (match != null) {
      final amount = double.parse(match.group(1) ?? ''); // Convert to double
      multipliedAmount = (amount * 1000).toInt(); // Multiply by 100
    }
    return multipliedAmount;
  }

  String getDateFromNotification(NotificationEvent event) {
    final timestamp = event.timestamp;
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp!);
    final formattedDate = date.toIso8601String();
    return formattedDate;
  }

  String getPayeeFromNotification(NotificationEvent event) {
    final String? regexSource = global.packages.firstWhere(
        (package) => package['packageName'] == event.packageName)['payeeRegex'];
    final RegExp regex = RegExp(regexSource!, caseSensitive: false);

    final placeMatch = regex.firstMatch(event.text ?? '');
    var place = '';
    if (placeMatch != null) {
      place = placeMatch.group(1) ?? '';
      print('Extracted place: $place');
    }
    return place;
  }

  Tuple2<Future<http.Response>, String> createTransaction(int multipliedAmount,
      String place, String date, String bearerToken, String? accountId) {
    final requestBody = {
      "transaction": {
        "account_id": accountId,
        "date": date,
        "amount": multipliedAmount * -1,
        "payee_name": ReCase(place).titleCase,
        "memo": "Added automagically"
      }
    };

    return Tuple2(
        http.post(
            Uri.parse("https://api.ynab.com/v1/budgets/last-used/transactions"),
            headers: {
              "Authorization": "Bearer $bearerToken",
              "Content-Type": "application/json"
            },
            body: jsonEncode(requestBody)),
        jsonEncode(requestBody));
  }

  Future<void> processNotification(
      NotificationEvent event, int notificationId) async {
    final String? regexSource = global.packages.firstWhere((package) =>
        package['packageName'] == event.packageName)['chargeEventRegex'];
    final RegExp regex = RegExp(regexSource!, caseSensitive: false);
    final match = regex.firstMatch(event.title ?? '');

    if (match != null) {
      final amount = getAmountFromNotification(event);
      final payee = getPayeeFromNotification(event);
      final date = getDateFromNotification(event);
      final bearerToken = await getBearerToken();
      final accountId = await loadAccount(event.packageName!);

      final transactionResult =
          createTransaction(amount, payee, date, bearerToken, accountId);
      transactionResult.item1.then((response) {
        if (response.statusCode == 200 || response.statusCode == 201) {
          print("HTTP request successful");

          var jsonResponse = jsonDecode(response.body);
          print(jsonResponse);
        } else {
          print("HTTP request failed");
          var jsonResponse = jsonDecode(response.body);
          print(jsonResponse);
        }
      }).catchError((error) {
        print("Error making HTTP request: $error");
      });
    }
  }
}

Future<String> getBearerToken() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('bearerToken') ?? '';
}
