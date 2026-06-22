import 'dart:io';

/// Represents a WireGuard configuration including the interface and peers.
class WireguardConfig {
  final WireguardInterface interface;
  final List<WireguardPeer> peers;

  WireguardConfig({
    required this.interface,
    this.peers = const [],
  });

  /// Reads a WireGuard configuration from a .conf file.
  factory WireguardConfig.fromFile(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw ArgumentError('File not found: $path');
    }
    return WireguardConfig.fromString(file.readAsStringSync());
  }

  /// Parses a WireGuard configuration from a string.
  factory WireguardConfig.fromString(String content) {
    final lines = content.split('\n');
    
    WireguardInterface? currentInterface;
    final List<WireguardPeer> peers = [];
    
    String? currentSection;
    Map<String, String> sectionData = {};

    void processSection() {
      if (currentSection == 'Interface') {
        currentInterface = WireguardInterface.fromMap(sectionData);
      } else if (currentSection == 'Peer') {
        peers.add(WireguardPeer.fromMap(sectionData));
      }
      sectionData.clear();
    }

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }
      
      if (line.startsWith('[') && line.endsWith(']')) {
        processSection();
        currentSection = line.substring(1, line.length - 1);
      } else {
        final parts = line.split('=');
        if (parts.length >= 2) {
          final key = parts[0].trim();
          final value = parts.sublist(1).join('=').trim();
          sectionData[key] = value;
        }
      }
    }
    processSection(); // Process the last section

    if (currentInterface == null) {
      throw const FormatException('No [Interface] section found in WireGuard config');
    }

    return WireguardConfig(
      interface: currentInterface!,
      peers: peers,
    );
  }
}

/// Represents the [Interface] section of a WireGuard configuration.
class WireguardInterface {
  final String privateKey;
  final String? address;
  final int? listenPort;

  WireguardInterface({
    required this.privateKey,
    this.address,
    this.listenPort,
  });

  factory WireguardInterface.fromMap(Map<String, String> map) {
    if (!map.containsKey('PrivateKey')) {
      throw const FormatException('Interface section is missing PrivateKey');
    }
    return WireguardInterface(
      privateKey: map['PrivateKey']!,
      address: map['Address'],
      listenPort: map.containsKey('ListenPort') ? int.tryParse(map['ListenPort']!) : null,
    );
  }
}

/// Represents a [Peer] section of a WireGuard configuration.
class WireguardPeer {
  final String publicKey;
  final String? endpoint;
  final String? allowedIPs;
  final String? presharedKey;
  final int? persistentKeepalive;

  WireguardPeer({
    required this.publicKey,
    this.endpoint,
    this.allowedIPs,
    this.presharedKey,
    this.persistentKeepalive,
  });

  factory WireguardPeer.fromMap(Map<String, String> map) {
    if (!map.containsKey('PublicKey')) {
      throw const FormatException('Peer section is missing PublicKey');
    }
    return WireguardPeer(
      publicKey: map['PublicKey']!,
      endpoint: map['Endpoint'],
      allowedIPs: map['AllowedIPs'],
      presharedKey: map['PresharedKey'],
      persistentKeepalive: map.containsKey('PersistentKeepalive') 
          ? int.tryParse(map['PersistentKeepalive']!) 
          : null,
    );
  }
}
