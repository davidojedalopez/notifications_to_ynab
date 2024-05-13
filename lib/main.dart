import 'dart:ffi';
import 'dart:isolate';
import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:http/http.dart' as http;

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

  void onData(NotificationEvent event) {
    var processablePackages = ["com.nu.production"];
    setState(() {
      _log.add(event);
      if (processablePackages.contains(event.packageName)) {
        _processableNotifications.add(event);
        processNotification(event);
      }
    });

    print("**************");
    print(event.toString());
  }

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
                print("TODO:");
              },
              icon: Icon(Icons.settings))
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

  Future<http.Response> createTransaction(
      int multipliedAmount, String place, String date) {
    return http.post(
        Uri.parse(
            "https://api.ynab.com/v1/budgets/72bd251c-4676-43d1-b48f-2c77886108c4/transactions"),
        headers: {
          "Authorization": "Bearer 0SYXrq5cWchr5Wf_W1QKXuCgBwjPSPgfHkmUQKFS7t0",
          "Content-Type": "application/json"
        },
        body: jsonEncode({
          "transaction": {
            "account_id": "41821ce0-c429-4b95-84be-6c26c97a94bd",
            "date": date,
            "amount": multipliedAmount,
            "payee_name": place,
            "memo": "automatically added"
          }
        }));
  }

  void processNotification(NotificationEvent event) {
    if (event.title?.startsWith("Compra aprobada") ?? false) {
      final amount = getAmountFromNotification(event);
      final payee = getPayeeFromNotification(event);
      final date = getDateFromNotification(event);

      createTransaction(amount, payee, date).then((response) {
        if (response.statusCode == 200) {
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
