import '../utils/win_helper.dart';

class BleCharacteristic {
  BleCharacteristic({
    required this.uuid,
    required this.properties,
  });

  String uuid;
  Properties properties;

  factory BleCharacteristic.fromJson(Map<String, dynamic> json) =>
      BleCharacteristic(
        uuid: WinHelper.fromWindowsUuid(json["uuid"]),
        properties: json["properties"] != null
            ? Properties.fromJson(json["properties"])
            : Properties(),
      );

  Map<String, dynamic> toJson() => {
        "uuid": uuid,
        "properties": properties.toJson(),
      };
}

class Properties {
  Properties({
    this.broadcast = false,
    this.read = false,
    this.writeWithoutResponse = false,
    this.write = false,
    this.notify = false,
    this.indicate = false,
    this.authenticatedSignedWrites = false,
    this.reliableWrite = false,
    this.writableAuxiliaries = false,
  });

  bool? broadcast;
  bool? read;
  bool? writeWithoutResponse;
  bool? write;
  bool? notify;
  bool? indicate;
  bool? authenticatedSignedWrites;
  bool? reliableWrite;
  bool? writableAuxiliaries;

  factory Properties.fromJson(Map<String, dynamic> json) => Properties(
        broadcast: json["broadcast"],
        read: json["read"],
        writeWithoutResponse: json["writeWithoutResponse"],
        write: json["write"],
        notify: json["notify"],
        indicate: json["indicate"],
        authenticatedSignedWrites: json["authenticatedSignedWrites"],
        reliableWrite: json["reliableWrite"],
        writableAuxiliaries: json["writableAuxiliaries"],
      );

  Map<String, dynamic> toJson() => {
        "broadcast": broadcast,
        "read": read,
        "writeWithoutResponse": writeWithoutResponse,
        "write": write,
        "notify": notify,
        "indicate": indicate,
        "authenticatedSignedWrites": authenticatedSignedWrites,
        "reliableWrite": reliableWrite,
        "writableAuxiliaries": writableAuxiliaries,
      };
}
