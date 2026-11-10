import 'dart:async';

import 'package:xrk_client/xrk_client.dart';

import '../l10n/l10n.dart';

/// The link to the engine broke, or never came up.
bool engineUnreachable(Object error) =>
    error is XrkTransportException ||
    error is DshCarrierLostException ||
    error is DshClosedException ||
    error is TimeoutException;

/// The reasons every page words the same way: the link, the sign-in, a
/// conversation that is gone, and recognized gateway failures. Null for anything else;
/// each page then says it its own way, or says nothing.
String? engineErrorReason(Object error) => switch (error) {
  _ when engineUnreachable(error) => appL10n.commonEngineUnreachable,
  DshCarrierRefusedException() || DshHttpException(statusCode: 401 || 403) => appL10n.stateEngineAuthFailed,
  XrkRemoteException(code: 'session/not-found') => appL10n.stateChatMissing,
  XrkRemoteException(
    code: 'gateway/service-unavailable' || 'gateway/context-unavailable' || 'gateway/lookup-unavailable',
  ) =>
    appL10n.stateEngineServiceUnavailable,
  XrkRemoteException(
    code: 'gateway/definition-unavailable' || 'gateway/invocation-unavailable' || 'gateway/method-unavailable',
  ) =>
    appL10n.stateEngineOperationUnavailable,
  XrkRemoteException(code: 'gateway/cancelled') => appL10n.commonCancelled,
  XrkRemoteException(code: 'gateway/peer-disposed') => appL10n.commonEngineUnreachable,
  XrkRemoteException(code: 'gateway/method-not-found' || 'gateway/not-found') => appL10n.stateEngineUnsupported,
  _ => null,
};
