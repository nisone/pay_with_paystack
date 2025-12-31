// ignore_for_file: prefer_typing_uninitialized_variables, use_build_context_synchronously

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pay_with_paystack/model/payment_data.dart';
import 'package:pay_with_paystack/model/paystack_request_response.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PaystackPayNow extends StatefulWidget {
  final String secretKey;
  final String reference;
  final String callbackUrl;
  final String currency;
  final String email;
  final double amount;
  final String? plan;
  final metadata;
  final paymentChannel;
  final void Function(PaymentData data) transactionCompleted;
  final void Function(String reason) transactionNotCompleted;

  const PaystackPayNow({
    Key? key,
    required this.secretKey,
    required this.email,
    required this.reference,
    required this.currency,
    required this.amount,
    required this.callbackUrl,
    required this.transactionCompleted,
    required this.transactionNotCompleted,
    this.metadata,
    this.plan,
    this.paymentChannel,
  }) : super(key: key);

  @override
  State<PaystackPayNow> createState() => _PaystackPayNowState();
}

class _PaystackPayNowState extends State<PaystackPayNow> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String? _errorMessage;
  PaystackRequestResponse? _response;

  @override
  void initState() {
    super.initState();
    _makePaymentRequest();
  }

  /// Makes HTTP Request to Paystack for access to make payment.
  Future<void> _makePaymentRequest() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final amount = widget.amount * 100;
      Map<String, dynamic> enrichedMetadata;

      if (widget.metadata == null) {
        enrichedMetadata = {
          "cancel_action": "https://github.com/popekabu/pay_with_paystack"
        };
      } else if (widget.metadata is Map) {
        enrichedMetadata = Map<String, dynamic>.from(widget.metadata);
        enrichedMetadata["cancel_action"] =
            "https://github.com/popekabu/pay_with_paystack";
      } else {
        enrichedMetadata = {
          "data": widget.metadata.toString(),
          "cancel_action": "https://github.com/popekabu/pay_with_paystack"
        };
      }

      final response = await http.post(
        Uri.parse('https://api.paystack.co/transaction/initialize'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.secretKey}',
        },
        body: jsonEncode({
          "email": widget.email,
          "amount": amount.toString(),
          "reference": widget.reference,
          "currency": widget.currency,
          "plan": widget.plan,
          "metadata": enrichedMetadata,
          "callback_url": widget.callbackUrl,
          "channels": widget.paymentChannel
        }),
      );

      if (response.statusCode == 200) {
        final decodedResponse =
            PaystackRequestResponse.fromJson(jsonDecode(response.body));

        final authUrl = decodedResponse.authUrl;
        final reference = decodedResponse.reference;

        if (decodedResponse.status == true &&
            authUrl != null &&
            reference != null) {
          _initializeWebViewController(authUrl, reference);
          if (mounted) {
            setState(() {
              _response = decodedResponse;
              _isLoading = false;
            });
          }
        } else {
          throw Exception(
              "Payment initialization failed: ${decodedResponse.message ?? 'Unknown error'}");
        }
      } else {
        throw Exception(
            "Response Code: ${response.statusCode}, Body: ${response.body}");
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _initializeWebViewController(String authUrl, String reference) {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) async {
            final url = request.url;
            if (url == 'https://github.com/popekabu/pay_with_paystack' ||
                url == 'https://standard.paystack.co/close' ||
                url == 'https://paystack.co/close' ||
                url.contains(widget.callbackUrl)) {
              await _checkTransactionStatus(reference);
              if (mounted) {
                Navigator.of(context).pop();
              }
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(authUrl));
  }

  /// Checks for transaction status of current transaction before view closes.
  Future<void> _checkTransactionStatus(String ref) async {
    try {
      final response = await http.get(
        Uri.parse('https://api.paystack.co/transaction/verify/$ref'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.secretKey}',
        },
      );

      if (response.statusCode == 200) {
        var decodedRespBody = jsonDecode(response.body);
        if (decodedRespBody["data"]["status"] == "success") {
          final data = PaymentData.fromJson(decodedRespBody["data"]);
          widget.transactionCompleted(data);
        } else {
          widget.transactionNotCompleted(
              decodedRespBody["data"]["status"].toString());
        }
      }
    } catch (_) {
      // Silent failure on check, just close or let user verify manually if needed
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only block pop if we are in the middle of a transaction (loading or webview active)
    // If there is an error, we should allow popping to exit.
    final canPop = _errorMessage != null;

    return PopScope(
      canPop: canPop,
      onPopInvoked: (didPop) {
        if (!didPop && _errorMessage == null) {
          // Show exit confirmation or just ignore
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 50),
              const SizedBox(height: 10),
              Text(
                "Failed to initialize payment",
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 5),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text("Close"),
              ),
              TextButton(
                onPressed: _makePaymentRequest,
                child: const Text("Retry"),
              )
            ],
          ),
        ),
      );
    }

    if (_response != null) {
      return WebViewWidget(controller: _controller);
    }

    return const SizedBox.shrink();
  }
}
