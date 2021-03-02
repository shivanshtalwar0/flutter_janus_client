import 'dart:async';
import 'dart:io';

import 'package:janus_client/JanusPlugin.dart';
import 'package:janus_client/JanusTransport.dart';
import 'package:janus_client/JanusClient.dart';
import 'package:janus_client/utils.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'JanusClient.dart';

class JanusSession {
  int refreshInterval;
  JanusTransport transport;
  JanusClient context;
  int sessionId;
  Map<String, Function> _transactions = {};
  Timer _keepAliveTimer;
  Map<int, JanusPlugin> _pluginHandles = {};

  JanusSession({this.refreshInterval, this.transport, this.context});

  Future<void> create() async {
    try {
      String transaction = getUuid().v4();
      Map<String, dynamic> request = {
        "janus": "create",
        "transaction": transaction,
        ...context.tokenMap,
        ...context.apiMap
      };
      Map<String, dynamic> response;
      if (transport is RestJanusTransport) {
        RestJanusTransport rest = (transport as RestJanusTransport);
        response = await rest.post(request);
        if(response!=null){
          if (response.containsKey('janus') && response.containsKey('data')) {
            sessionId = response['data']['id'];
            rest.sessionId = sessionId;
          }
        }
        else{
         throw "Janus Server not live or incorrect url/path specified";
        }
      } else if (transport is WebSocketJanusTransport) {
        WebSocketJanusTransport ws = (transport as WebSocketJanusTransport);
        if (!ws.isConnected) {
          ws.connect();
        }
        ws.sink.add(stringify(request));
        response = parse(await ws.stream.firstWhere(
            (element) => (parse(element)['transaction'] == transaction)));
        if (response.containsKey('janus') && response.containsKey('data')) {
          sessionId = response['data']['id'] as int;
          ws.sessionId = sessionId;
        }
      }
      _keepAlive();
    } on WebSocketChannelException catch (e) {
      throw "Connection to given url can't be established\n reason:-" +
          e.message;
    } catch (e) {
      throw "Connection to given url can't be established\n reason:-"+e.toString() ;
    }
  }

  Future<JanusPlugin> attach(String pluginName) async {
    String transaction = getUuid().v4();
    Map<String, dynamic> request = {
      "janus": "attach",
      "plugin": pluginName,
      "transaction": transaction
    };
    request["token"] = context.token;
    request["apisecret"] = context.apiSecret;
    request["session_id"] = sessionId;
    int handleId;
    Map<String, dynamic> response;
    if (transport is RestJanusTransport) {
      print('using rest transport for creating plugin handle');
      RestJanusTransport rest = (transport as RestJanusTransport);
      response = await rest.post(request);
      if (response.containsKey('janus') && response.containsKey('data')) {
        handleId = response['data']['id'];
        rest.sessionId = sessionId;
        rest.handleId = handleId;
        print(rest.handleId);
      }
    } else if (transport is WebSocketJanusTransport) {
      print('using websocket transport for creating plugin handle');
      WebSocketJanusTransport ws = (transport as WebSocketJanusTransport);
      if (!ws.isConnected) {
        ws.connect();
      }
      ws.sink.add(stringify(request));
      response = parse(await ws.stream.firstWhere(
          (element) => (parse(element)['transaction'] == transaction)));
      if (response.containsKey('janus') && response.containsKey('data')) {
        handleId = response['data']['id'] as int;
        ws.handleId = handleId;
        print(response);
        print(ws.handleId);
      }
    }
  }

  void dispose() {
    _keepAliveTimer.cancel();
    transport.dispose();
  }

  _keepAlive() {
    if (sessionId != null) {
      Timer.periodic(Duration(seconds: refreshInterval), (timer) async {
        this._keepAliveTimer = timer;
        try {
          String transaction = getUuid().v4();
          Map<String, dynamic> response;
          if (transport is RestJanusTransport) {
            print('using rest transport for keep alive ping');
            RestJanusTransport rest = (transport as RestJanusTransport);
            response = await rest.post({
              "janus": "keepalive",
              "session_id": sessionId,
              "transaction": transaction,
              ...context.apiMap,
              ...context.tokenMap
            });
            print(response);
          } else if (transport is WebSocketJanusTransport) {
            print('using websocket transport for keep alive ping');
            WebSocketJanusTransport ws = (transport as WebSocketJanusTransport);
            if (!ws.isConnected) {
              ws.connect();
            }
            ws.sink.add(stringify({
              "janus": "keepalive",
              "session_id": sessionId,
              "transaction": transaction,
              ...context.apiMap,
              ...context.tokenMap
            }));
            response = parse(await ws.stream.firstWhere(
                (element) => (parse(element)['transaction'] == transaction)));
            print(response);
          }
        } catch (e) {
          timer.cancel();
        }
      });
    }
  }
}