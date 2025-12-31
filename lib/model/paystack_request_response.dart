class PaystackRequestResponse {
  final bool status;
  final String? authUrl;
  final String? reference;
  final String? message;

  const PaystackRequestResponse({
    this.authUrl,
    required this.status,
    this.reference,
    this.message,
  });

  factory PaystackRequestResponse.fromJson(Map<String, dynamic> json) {
    return PaystackRequestResponse(
      status: json['status'] is bool ? json['status'] : false,
      authUrl: json['data'] != null ? json['data']["authorization_url"] : null,
      reference: json['data'] != null ? json['data']["reference"] : null,
      message: json['message'],
    );
  }
}
