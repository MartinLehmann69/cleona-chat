import 'dart:convert';

/// IPC request from GUI to Daemon (JSON-Lines over Unix Socket).
class IpcRequest {
  final int id;
  final String command;
  final Map<String, dynamic> params;
  final String? identityId; // Which identity this command targets

  IpcRequest({
    required this.id,
    required this.command,
    this.params = const {},
    this.identityId,
  });

  String toJsonLine() => '${jsonEncode(toJson())}\n';

  Map<String, dynamic> toJson() => {
        'type': 'request',
        'id': id,
        'command': command,
        'params': params,
        if (identityId != null) 'identityId': identityId,
      };

  static IpcRequest fromJson(Map<String, dynamic> json) => IpcRequest(
        id: json['id'] as int,
        command: json['command'] as String,
        params: (json['params'] as Map<String, dynamic>?) ?? {},
        identityId: json['identityId'] as String?,
      );
}

/// IPC response from Daemon to GUI.
class IpcResponse {
  final int id;
  final bool success;
  final Map<String, dynamic> data;
  final String? error;

  IpcResponse({
    required this.id,
    required this.success,
    this.data = const {},
    this.error,
  });

  String toJsonLine() => '${jsonEncode(toJson())}\n';

  Map<String, dynamic> toJson() => {
        'type': 'response',
        'id': id,
        'success': success,
        'data': data,
        if (error != null) 'error': error,
      };

  static IpcResponse fromJson(Map<String, dynamic> json) => IpcResponse(
        id: json['id'] as int,
        success: json['success'] as bool,
        data: (json['data'] as Map<String, dynamic>?) ?? {},
        error: json['error'] as String?,
      );
}

/// IPC event from Daemon to GUI (unsolicited push).
class IpcEvent {
  final String event;
  final Map<String, dynamic> data;
  final String? identityId; // Which identity generated this event

  IpcEvent({
    required this.event,
    this.data = const {},
    this.identityId,
  });

  String toJsonLine() => '${jsonEncode(toJson())}\n';

  Map<String, dynamic> toJson() => {
        'type': 'event',
        'event': event,
        'data': data,
        if (identityId != null) 'identityId': identityId,
      };

  static IpcEvent fromJson(Map<String, dynamic> json) => IpcEvent(
        event: json['event'] as String,
        data: (json['data'] as Map<String, dynamic>?) ?? {},
        identityId: json['identityId'] as String?,
      );
}

/// Parse a JSON line into the appropriate IPC message type.
dynamic parseIpcMessage(String line) {
  final json = jsonDecode(line) as Map<String, dynamic>;
  switch (json['type'] as String?) {
    case 'request':
      return IpcRequest.fromJson(json);
    case 'response':
      return IpcResponse.fromJson(json);
    case 'event':
      return IpcEvent.fromJson(json);
    default:
      throw FormatException('Unknown IPC message type: ${json['type']}');
  }
}
