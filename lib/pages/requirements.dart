import 'dart:io';

import 'package:dartx/dartx.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:swift_control/main.dart';
import 'package:swift_control/utils/requirements/multi.dart';
import 'package:swift_control/utils/requirements/platform.dart';
import 'package:swift_control/widgets/changelog_dialog.dart';
import 'package:swift_control/widgets/menu.dart';
import 'package:swift_control/widgets/title.dart';

import 'device.dart';

class RequirementsPage extends StatefulWidget {
  const RequirementsPage({super.key});

  @override
  State<RequirementsPage> createState() => _RequirementsPageState();
}

class _RequirementsPageState extends State<RequirementsPage> with WidgetsBindingObserver {
  int _currentStep = 0;

  List<PlatformRequirement> _requirements = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // call after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      settings.init().then((_) {
        _checkAndShowChangelog();
        if (!kIsWeb && Platform.isMacOS) {
          // add more delay due to CBManagerStateUnknown
          Future.delayed(const Duration(seconds: 2), () {
            _reloadRequirements();
          });
        } else {
          _reloadRequirements();
        }
      });
    });

    connection.hasDevices.addListener(() {
      if (connection.hasDevices.value) {
        Navigator.push(context, MaterialPageRoute(builder: (c) => DevicePage()));
      }
    });
  }

  Future<void> _checkAndShowChangelog() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final lastSeenVersion = settings.getLastSeenVersion();

      if (mounted) {
        await ChangelogDialog.showIfNeeded(context, currentVersion, lastSeenVersion);
      }

      // Update last seen version
      await settings.setLastSeenVersion(currentVersion);
    } catch (e) {
      print('Failed to check changelog: $e');
    }
  }

  @override
  dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reloadRequirements();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AppTitle(),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: buildMenuButtons(),
      ),
      body: _requirements.isEmpty
          ? Center(child: CircularProgressIndicator())
          : Card(
              margin: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Stepper(
                currentStep: _currentStep,
                connectorColor: WidgetStateProperty.resolveWith<Color>(
                  (Set<WidgetState> states) => Theme.of(context).colorScheme.primary,
                ),
                onStepContinue: _currentStep < _requirements.length
                    ? () {
                        setState(() {
                          _currentStep += 1;
                        });
                      }
                    : null,
                onStepTapped: (step) {
                  if (_requirements[step].status && _requirements[step] is! TargetRequirement) {
                    return;
                  }
                  final hasEarlierIncomplete = _requirements.indexWhere((req) => !req.status) < step;
                  if (hasEarlierIncomplete) {
                    return;
                  }
                  setState(() {
                    _currentStep = step;
                  });
                },
                controlsBuilder: (context, details) => Container(),
                steps: _requirements
                    .mapIndexed(
                      (index, req) => Step(
                        title: Text(req.name, style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: req.buildDescription() ?? (req.description != null ? Text(req.description!) : null),
                        content: Container(
                          padding: const EdgeInsets.only(top: 16.0),
                          alignment: Alignment.centerLeft,
                          child:
                              (index == _currentStep
                                  ? req.build(context, () {
                                      _reloadRequirements();
                                    })
                                  : null) ??
                              ElevatedButton(
                                onPressed: req.status
                                    ? null
                                    : () => _callRequirement(req, context, () {
                                        _reloadRequirements();
                                      }),
                                child: Text(req.name),
                              ),
                        ),
                        state: req.status ? StepState.complete : StepState.indexed,
                      ),
                    )
                    .toList(),
              ),
            ),
    );
  }

  void _callRequirement(PlatformRequirement req, BuildContext context, VoidCallback onUpdate) {
    req.call(context, onUpdate).then((_) {
      _reloadRequirements();
    });
  }

  void _reloadRequirements() {
    getRequirements(settings.getLastTarget()?.connectionType ?? ConnectionType.unknown).then((req) {
      _requirements = req;
      _currentStep = req.indexWhere((req) => !req.status);
      if (mounted) {
        setState(() {});
      }
    });
  }
}
