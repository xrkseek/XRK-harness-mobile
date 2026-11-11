import 'package:xrk_client/xrk_client.dart';

/// A mux that is ready at once, for fake local clients. Local Face keeps HTTP
/// up even when mux lags; repairs still call [ready] for live events.
class ReadyMux extends DshMux {
  ReadyMux() : super(DshHttpCarrier(DshConnection(Uri.parse('http://127.0.0.1:9'))));

  @override
  Future<MuxGeneration> ready({Duration? timeout}) async => const MuxGeneration(1, 'fixture', '/tmp');
}
