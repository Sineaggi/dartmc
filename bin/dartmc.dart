import 'dart:io';

import 'package:dartmc/dartmc.dart';

void main(List<String> arguments) async {
  final server = await MinecraftServer.lookup('us.mineplex.com');
  final status = await server.status();

  print(status);
  exit(0); // not sure i'm closing all the resources
}
