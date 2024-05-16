import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:notifications_listener/main.dart' as main;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'globals.dart' as globals;

class ConfigurationScreen extends StatefulWidget {
  @override
  _ConfigurationScreenState createState() => _ConfigurationScreenState();
}

class _ConfigurationScreenState extends State<ConfigurationScreen> {
  final packages = globals.packages;

  Map<String, String?> selectedAccounts = {};
  Future<List<Map<String, String>>>? accountsFuture;

  @override
  void initState() {
    super.initState();

    accountsFuture = fetchAccounts();

    packages.forEach((package) async {
      selectedAccounts[package['packageName']!] =
          await loadAccount(package['packageName']!);
    });
    print(selectedAccounts);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Configuration'),
      ),
      body: ListView.builder(
        itemCount: packages.length,
        itemBuilder: (context, index) {
          return ListTile(
            title: Text(packages[index]['displayName']!),
            trailing: FutureBuilder<List<Map<String, String>>>(
              future: accountsFuture,
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return DropdownButton<String>(
                    value: selectedAccounts[packages[index]['packageName']],
                    onChanged: (String? newValue) {
                      setState(() {
                        selectedAccounts[packages[index]['packageName']!] =
                            newValue;
                      });
                      if (newValue != null) {
                        storeAccount(packages[index]['packageName']!, newValue);
                      }
                    },
                    items:
                        snapshot.data!.map<DropdownMenuItem<String>>((account) {
                      return DropdownMenuItem<String>(
                        value: account['id'],
                        child: Text(account['name']!),
                      );
                    }).toList(),
                  );
                } else if (snapshot.hasError) {
                  return Text('${snapshot.error}');
                }

                // By default, show a loading spinner.
                return CircularProgressIndicator();
              },
            ),
          );
        },
      ),
    );
  }

  Future<List<Map<String, String>>> fetchAccounts() async {
    final bearerToken = await main.getBearerToken();
    final response = await http.get(
      Uri.parse("https://api.ynab.com/v1/budgets/last-used/accounts"),
      headers: {
        "Authorization": "Bearer $bearerToken",
        "Content-Type": "application/json"
      },
    );

    if (response.statusCode == 200) {
      var jsonResponse = jsonDecode(response.body);
      List<Map<String, String>> accounts = [];
      for (var account in jsonResponse['data']['accounts']) {
        accounts.add({
          'id': account['id'],
          'name': account['name'],
        });
      }
      return accounts;
    } else {
      throw Exception('Failed to load accounts');
    }
  }

  Future<void> storeAccount(String packageName, String accountId) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString(packageName, accountId);
  }
}

Future<String?> loadAccount(String packageName) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(packageName);
}
