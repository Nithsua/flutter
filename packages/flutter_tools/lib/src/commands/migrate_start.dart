// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';

import '../base/file_system.dart';
import '../base/logger.dart';
import '../globals.dart' as globals;
import '../project.dart';
import '../runner/flutter_command.dart';
import '../migrate/migrate_compute.dart';
import '../migrate/migrate_manifest.dart';
import '../migrate/migrate_utils.dart';
import '../cache.dart';
import 'migrate.dart';

class MigrateStartCommand extends FlutterCommand {
  MigrateStartCommand({
    bool verbose = false,
    this.logger,
  }) : _verbose = verbose {
    requiresPubspecYaml();
    argParser.addOption(
      'working-directory',
      help: '',
      defaultsTo: null,
      valueHelp: 'path',
    );
    argParser.addOption(
      'platforms',
      help: '',
      defaultsTo: null,
      valueHelp: 'path',
    );
    argParser.addFlag(
      'delete-temp-directories',
      negatable: true,
      defaultsTo: true,
      help: "",
    );
    argParser.addOption(
      'base-app-directory',
      help: '',
      defaultsTo: null,
      valueHelp: 'path',
    );
    argParser.addOption(
      'target-app-directory',
      help: '',
      defaultsTo: null,
      valueHelp: 'path',
    );
    argParser.addOption(
      'base-revision',
      help: '',
      defaultsTo: null,
      valueHelp: '',
    );
    argParser.addOption(
      'target-revision',
      help: '',
      defaultsTo: null,
      valueHelp: '',
    );
  }

  final bool _verbose;

  final Logger logger;

  @override
  final String name = 'start';

  @override
  final String description = 'Begins a new migration. Computes the changes needed to migrate the project from the base revision of Flutter to the current revision of Flutter and outputs the results in a working directory. Use `\$ flutter migrate apply` accept and apply the changes.';

  @override
  String get category => FlutterCommandCategory.project;

  @override
  Future<Set<DevelopmentArtifact>> get requiredArtifacts async => const <DevelopmentArtifact>{};

  @override
  Future<FlutterCommandResult> runCommand() async {
    final FlutterProject project = FlutterProject.current();
    if (project.isModule || project.isPlugin) {
      globals.logger.printError('Migrate tool only supports app projects. This project is a ${project.isModule ? 'module' : 'plugin'}');
      return const FlutterCommandResult(ExitStatus.fail);
    }

    List<SupportedPlatform> platforms = <SupportedPlatform>[];
    if (stringArg('platforms') != null) {
      for (String platformString in stringArg('platforms')!.split(',')) {
        platformString = platformString.trim();
        platforms.add(SupportedPlatform.values.firstWhere(
          (SupportedPlatform val) => val.toString() == 'SupportedPlatform.$platformString'
        ));
      }
    }

    MigrateResult? migrateResult = await computeMigration(
      verbose: _verbose,
      flutterProject: project,
      baseAppPath: stringArg('base-app-directory'),
      targetAppPath: stringArg('target-app-directory'),
      baseRevision: stringArg('base-revision'),
      targetRevision: stringArg('target-revision'),
      deleteTempDirectories: boolArg('delete-temp-directories'),
      platforms: platforms,
      logger: logger,
    );
    if (migrateResult == null) {
      return const FlutterCommandResult(ExitStatus.fail);
    }

    await writeWorkingDir(migrateResult, verbose: _verbose);

    MigrateUtils.deleteTempDirectories(
      paths: <String>[],
      directories: migrateResult.tempDirectories,
    );

    return const FlutterCommandResult(ExitStatus.success);
  }
}
