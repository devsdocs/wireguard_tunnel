import 'package:wireguard_tunnel/wireguard_tunnel.dart';
import 'package:test/test.dart';

void main() {
  group('WireguardConfig', () {
    test('parses standard conf string with one peer', () {
      const confString = '''
[Interface]
PrivateKey = aaaaaa
Address = 10.0.0.1/24
ListenPort = 51820

[Peer]
PublicKey = bbbbbb
AllowedIPs = 10.0.0.2/32
Endpoint = 192.168.1.100:51820
PersistentKeepalive = 25
''';

      final config = WireguardConfig.fromString(confString);
      
      expect(config.interface.privateKey, 'aaaaaa');
      expect(config.interface.address, '10.0.0.1/24');
      expect(config.interface.listenPort, 51820);
      
      expect(config.peers, hasLength(1));
      final peer = config.peers.first;
      expect(peer.publicKey, 'bbbbbb');
      expect(peer.allowedIPs, '10.0.0.2/32');
      expect(peer.endpoint, '192.168.1.100:51820');
      expect(peer.persistentKeepalive, 25);
    });

    test('parses conf string with multiple peers and ignores comments', () {
      const confString = '''
# This is a comment
[Interface]
PrivateKey = private_key_here
# Address = 10.0.0.1/24

[Peer]
# Peer 1
PublicKey = pub_key_1
AllowedIPs = 10.0.0.2/32

[Peer]
PublicKey = pub_key_2
Endpoint = test.example.com:51820
''';

      final config = WireguardConfig.fromString(confString);
      
      expect(config.interface.privateKey, 'private_key_here');
      expect(config.interface.address, isNull);
      
      expect(config.peers, hasLength(2));
      expect(config.peers[0].publicKey, 'pub_key_1');
      expect(config.peers[1].publicKey, 'pub_key_2');
      expect(config.peers[1].endpoint, 'test.example.com:51820');
    });

    test('throws FormatException if Interface section is missing', () {
      const confString = '''
[Peer]
PublicKey = bbbbbb
''';
      expect(() => WireguardConfig.fromString(confString), throwsFormatException);
    });
  });
}
