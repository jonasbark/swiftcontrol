import 'package:bike_control/pages/home/chain_state.dart';
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// A checklist step's words.
///
/// Steps read differently depending on whether they are done: a finished step
/// states a fact ("Paired over Bluetooth"), an unfinished one asks for
/// something ("Find your controller"). Keeping both wordings against one
/// [SetupStepId] means the chain model never has to carry sentences, and the
/// rider never reads an instruction for something they have already done.
class ChainStepText {
  const ChainStepText(this.label, [this.hint]);

  final String label;
  final String? hint;
}

ChainStepText chainStepText(BuildContext context, SetupStep step, {String? appName}) {
  final l = context.i18n;
  final app = appName ?? l.chainAppTitle;

  return switch (step.id) {
    SetupStepId.controllerBluetoothReady => step.done
        ? ChainStepText(l.chainStepBluetoothReady)
        : ChainStepText(l.chainStepBluetoothReadyPending, l.chainStepBluetoothReadyHint),
    SetupStepId.controllerPaired => step.done
        ? ChainStepText(l.chainStepControllerPaired)
        : ChainStepText(l.chainStepControllerPairedPending, l.chainStepControllerPairedHint),
    SetupStepId.controllerButtonsMapped => step.done
        ? ChainStepText(l.chainStepButtonsMapped)
        : ChainStepText(l.chainStepButtonsMappedPending, l.chainStepButtonsMappedHint),
    SetupStepId.controllerInRange => step.done
        ? ChainStepText(l.chainStepInRange)
        : ChainStepText(l.chainStepInRangePending, l.chainStepInRangeHint),
    SetupStepId.trainerPaired => step.done
        ? ChainStepText(l.chainStepTrainerPaired)
        : ChainStepText(l.chainStepTrainerPairedPending),
    // Whether the trainer app has actually picked the bridge up. The hint names
    // the exact entry to look for, which is the thing riders miss.
    SetupStepId.trainerAppBridged => step.done
        ? ChainStepText(l.chainStepTrainerBridged(app))
        : ChainStepText(
            l.chainStepTrainerBridgedPending(app),
            l.chainStepTrainerBridgedHint(step.hintArg ?? 'BikeControl', app),
          ),
    SetupStepId.appSelected => step.done
        ? ChainStepText(l.chainStepAppSelected)
        : ChainStepText(l.chainStepAppSelectedPending, l.chainStepAppSelectedHint),
    SetupStepId.appConnectionMethod => step.done
        ? ChainStepText(l.chainStepAppConnectionMethod)
        : ChainStepText(l.chainStepAppConnectionMethodPending, l.chainStepAppConnectionMethodHint),
    SetupStepId.appConnected => step.done
        ? ChainStepText(l.chainStepAppConnected(app))
        : ChainStepText(l.chainStepAppConnectedPending(app), l.chainStepAppConnectedHint),
  };
}

/// The name the banner uses for a link when it has to talk about it in a
/// sentence — "Controller and Trainer app still need setting up".
String chainLinkName(BuildContext context, ChainLinkKey key) {
  return switch (key) {
    ChainLinkKey.controller => context.i18n.chainControllerTitle,
    ChainLinkKey.trainer => context.i18n.chainTrainerTitle,
    ChainLinkKey.app => context.i18n.chainAppTitle,
  };
}
