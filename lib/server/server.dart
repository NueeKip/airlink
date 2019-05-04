import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import '../models/data_link.dart';
import '../models/server.dart';
import '../log.dart';

class FileServer {
  DataLink _dataLink;
  Directory _rootDirectory;
  Directory _uploadDirectory;

  bool _isInitialized = false;
  bool _isRunning = false;
  List<ServerLog> _logs = [];

  Stream<HttpRequest> _server;
  StreamSubscription _serverSub;
  final Completer<Null> _readyCompleter = Completer<Null>();
  StreamController<ServerLog> _serverLog;

  Stream<ServerLog> get serverLog => _serverLog.stream;
  List<ServerLog> get logs => _logs;

  Future<Null> get onReady => _readyCompleter.future;
  bool get isInitialized => _isInitialized;
  bool get isRunning => _isRunning;

  void init(
      {@required DataLink dataLink,
      @required Directory rootDirectory,
      @required Directory uploadDirectory}) {
    print("INIT SERVER AT $dataLink");
    _rootDirectory = rootDirectory;
    _uploadDirectory = uploadDirectory;
    _dataLink = dataLink;
    HttpServer.bind(_dataLink.url, int.parse(_dataLink.port))
        .then((HttpServer server) {
      _server = server.asBroadcastStream();
      _readyCompleter.complete();
      _isInitialized = true;
    });
  }

  void _unauthorized(HttpRequest request, String msg) {
    request.response.write(jsonEncode({"Status": "Unauthorized"}));
    request.response.statusCode = HttpStatus.unauthorized;
    request.response.close();
    emitServerLog(
        logClass: LogMessageClass.warning,
        message: msg,
        statusCode: request.response.statusCode,
        requestUrl: request.uri.toString());
  }

  void _handlePost(HttpRequest request) async {
    //print("POST REQUEST: ${request.uri.path} / ${request.headers.contentType}");
    // verify authorization
    String tokenString = "Bearer ${_dataLink.apiKey}";
    try {
      if (request.headers.value(HttpHeaders.authorizationHeader) !=
          tokenString) {
        String msg = "Unauthorized request";
        log.warning(msg);
        _unauthorized(request, msg);
        return;
      }
    } catch (_) {
      String msg = "Can not get authorization header";
      log.error(msg);
      _unauthorized(request, msg);
      return;
    }
    // process request
    String content = await request.transform(const Utf8Decoder()).join();
    Map<dynamic, dynamic> data;
    try {
      data = jsonDecode(content) as Map;
    } catch (e) {
      log.error("DECODING ERROR $e");
    }
    String path = data["path"].toString();
    String dirPath;
    (path == "/" || path == "")
        ? dirPath = _rootDirectory.path
        : dirPath = _rootDirectory.path + path;
    Directory dir = Directory(dirPath);
    HttpResponse response = request.response;
    if (dir == null) {
      response.write(jsonEncode({"Status": "Not found"}));
      response.statusCode = HttpStatus.notFound;
      response.close();
      emitServerLog(
          logClass: LogMessageClass.warning,
          message: "Not found",
          statusCode: response.statusCode,
          requestUrl: path);
    }
    response.headers.contentType =
        new ContentType("application", "json", charset: "utf-8");
    var dirListing = await getDirectoryListing(dir);
    response.statusCode = HttpStatus.ok;
    response.write(jsonEncode(dirListing));
    response.close();
    // log
    emitServerLog(
        logClass: LogMessageClass.success,
        message: "",
        statusCode: response.statusCode,
        requestUrl: path);
  }

  Future<bool> start(BuildContext context) async {
    assert(_isInitialized);
    if (_isRunning) {
      log.warningScreen("The server is already running", context: context);
      return false;
    }
    _serverLog = StreamController<ServerLog>.broadcast();
    await onReady;
    log.info("STARTING SERVER");
    _serverSub = _server.listen((request) {
      switch (request.method) {
        case 'POST':
          _handlePost(request);
          break;
        default:
          request.response.statusCode = HttpStatus.methodNotAllowed;
          request.response.close();
          emitServerLog(
              logClass: LogMessageClass.warning,
              message: "Method not allowed ${request.method}",
              statusCode: request.response.statusCode,
              requestUrl: request.uri.toString());
          return false;
      }
    });
    _isRunning = true;
    return true;
  }

  Future<bool> stop(BuildContext context) async {
    if (_isRunning) {
      log.info("STOPPING SERVER");
      await _serverSub.cancel();
      _isRunning = false;
      _serverLog.close();
      return true;
    }
    log.warningScreen("The server is already running", context: context);
    return false;
  }

  Future<Map<String, List<Map<String, dynamic>>>> getDirectoryListing(
      Directory dir) async {
    List contents = dir.listSync()..sort((a, b) => a.path.compareTo(b.path));
    var dirs = <Map<String, String>>[];
    var files = <Map<String, dynamic>>[];
    for (var fileOrDir in contents) {
      if (fileOrDir is Directory) {
        var dir = Directory("${fileOrDir.path}");
        dirs.add({
          "name": path.basename(dir.path),
        });
      } else {
        var file = File("${fileOrDir.path}");
        files.add(<String, dynamic>{
          "name": path.basename(file.path),
          "size": file.lengthSync()
        });
      }
    }
    return {"files": files, "directories": dirs};
  }

  void emitServerLog(
      {@required LogMessageClass logClass,
      @required String requestUrl,
      @required String message,
      @required int statusCode}) async {
    ServerLog logItem = ServerLog(
        statusCode: statusCode,
        requestUrl: requestUrl,
        message: message,
        logClass: logClass);
    log.info(logItem.toString());
    _serverLog.sink.add(logItem);
    _logs.add(logItem);
  }
}
