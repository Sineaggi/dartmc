library dartmc;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:basic_utils/basic_utils.dart';
import 'package:leb128/leb128.dart';

abstract class Resource {
  void dispose();
}

void using<T extends Sink>(T resource, void Function(T) fn) {
  fn(resource);
  resource.close();
}

class Version {
  String name;
  int protocol;
  Version(this.name, this.protocol);
  static Version init(raw) {
    if (raw is! Map) {
      throw Exception('Invalid version object (expected Map, found ${raw.runtimeType}');
    }
    if (!raw.containsKey('name')) {
      throw Exception("Invalid version object (no 'name' value)");
    }
    var name = raw['name'];
    if (name is! String) {
      throw Exception("Invalid version object (expected 'name' to be String, was ${name.runtimeType})");
    }
    if (!raw.containsKey('protocol')) {
      throw Exception("Invalid version object (no 'protocol' value)");
    }
    var protocol = raw['protocol'];
    if (protocol is! int) {
      throw Exception("Invalid version object (expected 'protocol' to be int, was ${name.runtimeType})");
    }
    return Version(name, protocol);
  }
  @override
  String toString() {
    return 'Version(name=$name, protocol=$protocol)';
  }
}

class PingResponse {
  Players players;
  Version version;
  String description;
  String? favicon;
  int latency;
  PingResponse(this.players, this.version, this.description, this.favicon, this.latency);

  @override
  String toString() {
    return 'PingResponse(players=$players, version=$version, description=$description, favicon=$favicon, latency=$latency)';
  }
}

class StatusResponse {
  Players players;
  Version version;
  String description;
  String? favicon;

  var latency = 0.0;

  StatusResponse(this.players, this.version, this.description, this.favicon);

  static StatusResponse init(Map<String, dynamic> raw) {
    if (!raw.containsKey('players')) {
      throw Exception("Invalid status object (no 'players' value)");
    }
    var players = Players.init(raw['players']);
    if (!raw.containsKey('version')) {
      throw Exception("Invalid status object (no 'version' value)");
    }
    var version = Version.init(raw['version']);

    if (!raw.containsKey('description')) {
      throw Exception("Invalid status object (no 'description' value)");
    }
    var description = raw['description'];
    var description_str = '';
    if (description is Map) {
      var text = description['text'];
      description_str = text;
    } else {
      throw Exception('Unknown description type ${description.runtimeType}');
    }
    var favicon = raw['favicon'];
    return StatusResponse(players, version, description_str, favicon);
  }
}

class Player {
  String name;
  String id;
  Player(this.name, this.id);
  static Player init(raw) {
    if (raw is! Map) {
      throw Exception('Invalid player object (expected Map, found ${raw.runtimeType}');
    }
    if (!raw.containsKey('name')) {
      throw Exception("Invalid player object (no 'name' value)");
    }
    var name = raw['name'];
    if (name is! String) {
      throw Exception("Invalid player object (expected 'name' to be String, was ${name.runtimeType})");
    }
    if (!raw.containsKey('id')) {
      throw Exception("Invalid player object (no 'id' value)");
    }
    var id = raw['id'];
    if (id is! String) {
      throw Exception("Invalid player object (expected 'id' to be String, was ${id.runtimeType})");
    }
    return Player(name, id);
  }
  @override
  String toString() {
    return 'Player(name=$name, id=$id)';
  }
}

class Players {
  int max;
  int online;
  List<Player> sample;
  Players(this.max, this.online, this.sample);
  static Players init(raw) {
    if (raw is! Map) {
      throw Exception('Invalid players object (expected Map, found ${raw.runtimeType}');
    }
    if (!raw.containsKey('online')) {
      throw Exception("Invalid players object (no 'online' value)");
    }
    var online = raw['online'];
    if (online is! int) {
      throw Exception("Invalid players object (expected 'online' to be int, was ${online.runtimeType})");
    }
    if (!raw.containsKey('max')) {
      throw Exception("Invalid players object (no 'max' value)");
    }
    var max = raw['max'];
    if (max is! int) {
      throw Exception("Invalid players object (expected 'max' to be int, was ${online.runtimeType})");
    }
    List<Player> sample = List.empty(growable: true);
    if (raw.containsKey('sample')) {
      if (raw['sample'] is! Iterable) {
        throw Exception("Invalid players object (expected 'sample' to be list, was ${raw['sample'].runtimeType})");
      }
      for (var p in raw['sample']) {
        sample.add(Player.init(p));
      }
    }

    return Players(max, online, sample);
  }
  @override
  String toString() {
    return 'Players(max=$max, online=$online, sample=$sample)';
  }
}

class Connection {
  List<int> sent = List.empty(growable: true);
  List<int> received = List.empty(growable: true);
  void write(List<int> data) {
      sent.addAll(data);
  }
  void receive(List<int> data) {
    received.addAll(data);
  }
  void writeVarint(int value) {
    if (value < -2147483648 || 2147483647 < value) {
      throw Exception("Minecraft varints must be in the range of [-2**31, 2**31 - 1].");
    }
    var encoded = Leb128.encodeSigned(value);
    write(encoded);
  }
  Future<String> readUtf() async {
    var length = await readVarint();
    return utf8.decode(await read(length));
  }
  void writeUtf(String value) {
    var encoded = utf8.encode(value);
    writeVarint(encoded.length);
    write(encoded);
  }
  void writeShort(int value) {
    throw Exception("not implemented");
  }
  void writeUshort(int value) {
    Uint8List input = Uint8List.fromList([0, 0]);
    ByteData bd = input.buffer.asByteData();
    bd.setUint16(0, value);
    write(input);
  }
  Future<int> readLong() async {
    Uint8List output = Uint8List.fromList(await read(8));
    ByteData bd = output.buffer.asByteData();
    return bd.getInt64(0);
  }
  void writeLong(int value) {
    Uint8List input = Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 0]);
    ByteData bd = input.buffer.asByteData();
    bd.setInt64(0, value);
    write(input);
  }
  List<int> flush() {
    var result = sent;
    sent = List.empty(growable: true);
    return result;
  }
  void writeBuffer(Connection buffer) {
    var data = buffer.flush();
    writeVarint(data.length);
    write(data);
  }

  Future<List<int>> read(int length) async {
    var result = received.sublist(0, length);
    received = received.sublist(length);
    return result;
  }

  Future<int> readVarint() async {
    var result = 0;
    for(final i in range(0, 5)) {
      var part = (await read(1))[0];
      result |= (part & 0x7F) << (7 * i);
      if (part & 0x80 == 0) {
        return result;
      }
    }
    return result;
  }

  Future<Connection> readBuffer() async {
    //var length = await readVarint();
    throw Exception("not done");
  }
}

Iterable<int> range(int low, int high) sync* {
  for (var i = low; i < high; ++i) {
    yield i;
  }
}

void to_varint(int value) {
  if (value < -2147483648 || 2147483647 < value) {
      throw Exception("Minecraft varints must be in the range of [-2**31, 2**31 - 1].");
  }
  var vr = Leb128.encodeSigned(value);
  print(vr);
}

class ServerPinger {
  Connection connection;
  int version;
  String host;
  int port;
  int pingToken;
  ServerPinger(this.connection, this.version, this.host, this.port, this.pingToken);
  static ServerPinger init(Connection connection,
  {String host = '',
      int port = 0,
  int version = 47,
  int? pingToken}) {
    // return ServerPinger(connection, version, host, port, pingToken ?? Random().nextInt((1 << 63) - 1));
    return ServerPinger(connection, version, host, port, pingToken ?? Random().nextInt((1 << 31) - 1));
  }
  void handshake() {
    var packet = Connection();
    packet.writeVarint(0);
    packet.writeVarint(version);
    packet.writeUtf(host);
    packet.writeUshort(port);
    packet.writeVarint(1); // Intention to query status

    connection.writeBuffer(packet);
  }

  Future<StatusResponse> readStatus() async {
    var request = Connection();
    request.writeVarint(0); // Request status
    connection.writeBuffer(request);

    var response = await connection.readBuffer();
    if (await response.readVarint() != 0) {
      throw Exception('Received invalid status response packet.');
    }
    Map<String, dynamic> raw = jsonDecode(await response.readUtf());
    return StatusResponse.init(raw);
  }

  Future<int> testPing() async {
    var request = Connection();
    request.writeVarint(1); // Test ping
    request.writeLong(pingToken);
    var sent = DateTime.now();
    connection.writeBuffer(request);

    var response = await connection.readBuffer();
    var received = DateTime.now();
    if (await response.readVarint() != 1) {
      throw Exception('Received invalid ping response packet.');
    }
    var receivedToken = await response.readLong();
    if (receivedToken != pingToken) {
      throw Exception('Received mangled ping response packet (expected token $pingToken, received $receivedToken)');
    }
    var delta = received.difference(sent);
    return delta.inMilliseconds;
  }
}

class TCPSocketConnection extends Connection {
  Socket writer;
  ChunkedStreamReader<int> reader;

  TCPSocketConnection(this.reader, this.writer);

  static Future<TCPSocketConnection> connect(String host, int port) async {
    var socket = await Socket.connect(host, port);
    //ChunkedStreamReader();
    //final r = ChunkedStreamReader(File('myfile.txt').openRead());
    var reader = ChunkedStreamReader<int>(socket);
    //var sompla = ChunkedStreamReader.ChunkedStreamReader(socket);
    //ChunkedStreamIterator(socket);
    return TCPSocketConnection(reader, socket);
  }

  @override
  void write(List<int> data) {
    //await for (var data in socket) {
    //}
    writer.add(data);
  }

  Future<List<int>> read(int length) async {
    var result = List<int>.empty(growable: true);
    while (result.length < length) {
      var newBytes = await reader.readBytes(length - result.length);
      if (newBytes.length == 0) {
      throw Exception("Server did not respond with any information!");
      }
      result.addAll(newBytes);

    }
    return result;
  }

  @override
  Future<int> readVarint() async {
    var result = 0;
    for(final i in range(0, 5)) {
      var part = (await read(1))[0];
      result |= (part & 0x7F) << (7 * i);
      if (part & 0x80 == 0) {
        return result;
      }
    }
    return result;
  }

  @override
  Future<Connection> readBuffer() async {
    var length = await readVarint();
    var result = Connection();
    result.receive(await read(length));
    return result;
  }

  Future close() async {
    await reader.cancel();
    await writer.close();
  }
}

class MinecraftServer {
  final String host;
  final int port;
  MinecraftServer(this.host, this.port);

  static Future<MinecraftServer> lookup(String address) async {
    var uri = Uri.parse('//' + address);
    var host = uri.host;
    var port = uri.port;
    if (!uri.hasPort) {
      port = 25565;
      var answers = await DnsUtils.lookupRecord('_minecraft._tcp.' + host, RRecordType.SRV);
      if (answers != null && answers.isNotEmpty) {
        var srvRecord = SRVRecord.parseRecord(answers[0]);
        port = srvRecord.port;
        host = srvRecord.host.substring(0, srvRecord.host.length - 1); // strip trailing .
        print('host=$host, port=$port');
      }
    }
    return MinecraftServer(host, port);
  }

  Future<PingResponse> status() async {
    //Socket socket = await Socket.connect(this.host, this.port);

    //socket.listen((List<int> event) {
    //  print(utf8.decode(event));
    //});

    var connection = await TCPSocketConnection.connect(host, port);

    var pinger = ServerPinger.init(connection, host: host, port: port);
    pinger.handshake();

    var status = await pinger.readStatus();
    var latency = await pinger.testPing();
    var result = PingResponse(status.players, status.version, status.description, status.favicon, latency);

    await connection.close();
    return result;

    // send hello
    //socket.add(utf8.encode('hello'));



    // wait 5 seconds
    //await Future.delayed(Duration(seconds: 5));

    //await socket.close();

    //return PingResponse.init(raw);
  }
}

class SRVRecord {
  final String host;
  final int port;
  static SRVRecord parseRecord(RRecord record) {
    var dd = record.data.split(' ');
    return SRVRecord(dd[3], int.tryParse(dd[2])!);
  }
  SRVRecord(this.host, this.port);
}
