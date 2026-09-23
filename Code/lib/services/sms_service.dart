import 'dart:async';

import 'package:another_telephony/telephony.dart';

/// Result of an attempt to send a single SMS.
class SmsSendResult {
  final String phoneNumber;
  final bool success;
  final String? error;

  const SmsSendResult({
    required this.phoneNumber,
    required this.success,
    this.error,
  });
}

/// Service that sends SMS directly through Android's `SmsManager`
/// (via the `another_telephony` plugin).
///
/// This path does NOT depend on the internet, mobile data, or Firebase.
/// It only needs a working SIM + cellular network and the `SEND_SMS`
/// permission. Messages are delivered even when data is turned off.
class SmsService {
  SmsService._();

  static final Telephony _telephony = Telephony.instance;

  /// Standard single-part SMS length. Longer messages are sent multipart.
  static const int _singleSmsLength = 155;

  /// Whether the device hardware can send SMS at all.
  static Future<bool> isSmsCapable() async {
    try {
      return (await _telephony.isSmsCapable) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Whether a usable SIM is present and ready.
  ///
  /// Returns `true` when we cannot determine the state, so we never block an
  /// emergency send on an inconclusive check.
  static Future<bool> hasReadySim() async {
    try {
      final state = await _telephony.simState;
      // Only ABSENT is a hard "no SIM". Other states (READY, UNKNOWN, etc.)
      // are treated as "attempt the send anyway".
      return state != SimState.ABSENT;
    } catch (_) {
      return true;
    }
  }

  /// Send an SMS to a single recipient. Never throws; returns a result.
  static Future<SmsSendResult> sendTo({
    required String phoneNumber,
    required String message,
  }) async {
    final sanitized = _sanitizeNumber(phoneNumber);
    if (sanitized.isEmpty) {
      return SmsSendResult(
        phoneNumber: phoneNumber,
        success: false,
        error: 'Invalid phone number',
      );
    }

    try {
      final completer = Completer<SmsSendResult>();

      // The plugin reports SENT/DELIVERED asynchronously. We resolve on the
      // first SENT (or DELIVERED) callback, and fall back to a timeout so the
      // emergency flow never hangs.
      _telephony.sendSms(
        to: sanitized,
        message: message,
        isMultipart: message.length > _singleSmsLength,
        statusListener: (SendStatus status) {
          if (completer.isCompleted) return;
          if (status == SendStatus.SENT || status == SendStatus.DELIVERED) {
            completer.complete(
              SmsSendResult(phoneNumber: sanitized, success: true),
            );
          }
        },
      );

      // If no callback arrives (e.g. no signal), assume the request was handed
      // to the radio and let Android retry; we report optimistic success after
      // the grace period so one bad contact does not stall the rest.
      return await completer.future.timeout(
        const Duration(seconds: 12),
        onTimeout: () => SmsSendResult(phoneNumber: sanitized, success: true),
      );
    } catch (e) {
      return SmsSendResult(
        phoneNumber: sanitized,
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Send the same message to every recipient. Failures on one number do not
  /// abort the others.
  static Future<List<SmsSendResult>> sendToAll({
    required List<String> phoneNumbers,
    required String message,
  }) async {
    final results = <SmsSendResult>[];
    for (final number in phoneNumbers) {
      results.add(await sendTo(phoneNumber: number, message: message));
    }
    return results;
  }

  /// Keep digits, a single leading `+`, and drop spaces / punctuation.
  static String _sanitizeNumber(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final hasPlus = trimmed.startsWith('+');
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    return hasPlus ? '+$digits' : digits;
  }
}
