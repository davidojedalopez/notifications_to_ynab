import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:notifications_to_ynab/main.dart' as main;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'globals.dart' as globals;

class ConfigurationScreen extends StatefulWidget {
  const ConfigurationScreen({super.key});

  @override
  // ignore: library_private_types_in_public_api
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
        title: const Text('Configuration'),
      ),
      body: Column(
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text(
              'Link notifications from your apps to YNAB accounts',
              style: TextStyle(fontSize: 16),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.builder(
                itemCount: packages.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text(packages[index]['displayName']!),
                    trailing: FutureBuilder<List<Map<String, String>>>(
                      future: accountsFuture,
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          return DropdownButton<String>(
                            value: selectedAccounts[packages[index]
                                ['packageName']],
                            onChanged: (String? newValue) {
                              setState(() {
                                selectedAccounts[packages[index]
                                    ['packageName']!] = newValue;
                              });
                              if (newValue != null) {
                                storeAccount(
                                    packages[index]['packageName']!, newValue);
                              }
                            },
                            items: snapshot.data!
                                .map<DropdownMenuItem<String>>((account) {
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
                        return const CircularProgressIndicator();
                      },
                    ),
                  );
                },
              ),
            ),
          ),
          BearerTokenInput(),
        ],
      ),
    );
  }

  Future<void> _refresh() async {
    // Implement your refresh logic here.
    // For example, you can call a method to fetch the packages and accounts again.
    setState(() {
      accountsFuture = fetchAccounts();
    });
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

/* Token input */

class BearerTokenInput extends StatefulWidget {
  const BearerTokenInput({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _BearerTokenInputState createState() => _BearerTokenInputState();
}

class _BearerTokenInputState extends State<BearerTokenInput> {
  final _formKey = GlobalKey<FormState>();
  String _bearerToken = '';
  String _inputToken = '';

  @override
  void initState() {
    super.initState();
    _loadBearerToken();
  }

  Future<void> _saveBearerToken(String token) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('bearerToken', token);
    print(prefs.getString('bearerToken'));

    setState(() {
      _bearerToken = token;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _loadBearerToken(),
      builder: (BuildContext context, AsyncSnapshot<String?> snapshot) {
        return Form(
          key: _formKey,
          child: Column(
            children: <Widget>[
              Container(
                margin: const EdgeInsets.all(30.0),
                child: TextFormField(
                  initialValue: _bearerToken,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'YNAB personal access token',
                    helperText: snapshot.hasData && snapshot.data!.isNotEmpty
                        ? 'Access token already defined! (pull to refresh)'
                        : null,
                    helperStyle: TextStyle(color: Colors.green),
                  ),
                  onSaved: (value) => _inputToken = value!,
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    _formKey.currentState?.save();
                    _saveBearerToken(_inputToken);
                  }
                },
                child: const Text('Submit'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<String?> _loadBearerToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('bearerToken');
  }
}
