// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:process/process.dart';

import '../base/file_system.dart';
import '../base/logger.dart';
import '../base/platform.dart';
import '../base/terminal.dart';
import '../migrate/migrate_manifest.dart';
import '../migrate/migrate_utils.dart';
import '../project.dart';
import '../runner/flutter_command.dart';
import 'migrate.dart';

/// Flutter migrate subcommand to check the migration status of the project.
class MigrateStatusCommand extends FlutterCommand {
  MigrateStatusCommand({
    bool verbose = false,
    required this.logger,
    required this.fileSystem,
    required Platform platform,
    required ProcessManager processManager,
  }) : _verbose = verbose,
       migrateUtils = MigrateUtils(
         logger: logger,
         fileSystem: fileSystem,
         platform: platform,
         processManager: processManager,
       ) {
    requiresPubspecYaml();
    argParser.addOption(
      'working-directory',
      help: 'Specifies the custom migration working directory used to stage and edit proposed changes. '
            'This path can be absolute or relative to the flutter project root.',
      valueHelp: 'path',
    );
    argParser.addOption(
      'project-directory',
      help: 'The root directory of the flutter project.',
      valueHelp: 'path',
    );
    argParser.addFlag(
      'diff',
      defaultsTo: true,
      help: 'Shows the diff output when enabled. Enabled by default.',
    );
    argParser.addFlag(
      'show-added-files',
      help: 'Shows the contents of added files. Disabled by default.',
    );
  }

  final bool _verbose;

  final Logger logger;

  final FileSystem fileSystem;

  final MigrateUtils migrateUtils;

  @override
  final String name = 'status';

  @override
  final String description = 'Prints the current status of the in progress migration.';

  @override
  String get category => FlutterCommandCategory.project;

  @override
  Future<Set<DevelopmentArtifact>> get requiredArtifacts async => const <DevelopmentArtifact>{};

  /// Manually marks the lines in a diff that should be printed unformatted for visbility.
  final Set<int> _initialDiffLines = <int>{0, 1};

  @override
  Future<FlutterCommandResult> runCommand() async {
    final String? projectDirectory = stringArg('project-directory');
    final FlutterProjectFactory flutterProjectFactory = FlutterProjectFactory(logger: logger, fileSystem: fileSystem);
    final FlutterProject project = projectDirectory == null ? FlutterProject.current() : flutterProjectFactory.fromDirectory(fileSystem.directory(projectDirectory));
    Directory workingDirectory = project.directory.childDirectory(kDefaultMigrateWorkingDirectoryName);
    final String? customWorkingDirectoryPath = stringArg('working-directory');
    if (customWorkingDirectoryPath != null) {
      if (customWorkingDirectoryPath.startsWith(fileSystem.path.separator) || customWorkingDirectoryPath.startsWith('/')) {
        // Is an absolute path
        workingDirectory = fileSystem.directory(customWorkingDirectoryPath);
      } else {
        workingDirectory = project.directory.childDirectory(customWorkingDirectoryPath);
      }
    }
    if (!workingDirectory.existsSync()) {
      logger.printStatus('No migration in progress. Start a new migration with:');
      printCommandText('flutter migrate start', logger);
      return const FlutterCommandResult(ExitStatus.fail);
    }

    final File manifestFile = MigrateManifest.getManifestFileFromDirectory(workingDirectory);
    if (!manifestFile.existsSync()) {
      logger.printError('No migrate manifest in the migrate working directory at ${workingDirectory.path}. Fix the working directory or abandon and restart the migration.');
      return const FlutterCommandResult(ExitStatus.fail);
    }
    final MigrateManifest manifest = MigrateManifest.fromFile(manifestFile);

    if (boolArg('diff') || _verbose) {
      if (boolArg('show-added-files') || _verbose) {
        for (final String localPath in manifest.addedFiles) {
          logger.printStatus('Newly addded file at $localPath:\n');
          try {
            logger.printStatus(workingDirectory.childFile(localPath).readAsStringSync(), color: TerminalColor.green);
          } on FileSystemException {
            logger.printStatus('Contents are byte data\n', color: TerminalColor.grey);
          }
        }
      }
      final List<String> files = <String>[];
      files.addAll(manifest.mergedFiles);
      files.addAll(manifest.resolvedConflictFiles(workingDirectory));
      files.addAll(manifest.remainingConflictFiles(workingDirectory));
      for (final String localPath in files) {
        logger.printStatus('@@@@@@@@@CHECKING FILES $localPath:');
        logger.printStatus('@@@@@@@@@CHECKING FILES ${project.directory.childFile(localPath).path} ::: ${workingDirectory.childFile(localPath).path}:');
        logger.printStatus('@@@@@@@@@CHECKING FILES ${project.directory.childFile(localPath).existsSync()} ::: ${workingDirectory.childFile(localPath).existsSync()}:');
        final DiffResult result = await migrateUtils.diffFiles(project.directory.childFile(localPath), workingDirectory.childFile(localPath));
        if (result.diff != '' && result.diff != null) {
          // Print with different colors for better visibility.
          int lineNumber = -1;
          for (final String line in result.diff!.split('\n')) {
            lineNumber++;
            if (line.startsWith('---') || line.startsWith('+++') || line.startsWith('&&') || _initialDiffLines.contains(lineNumber)) {
              logger.printStatus(line);
              continue;
            }
            if (line.startsWith('-')) {
              logger.printStatus(line, color: TerminalColor.red);
              continue;
            }
            if (line.startsWith('+')) {
              logger.printStatus(line, color: TerminalColor.green);
              continue;
            }
            logger.printStatus(line, color: TerminalColor.grey);
          }
        } else {
          logger.printStatus('!!!!!!!!!!!!!!!${result.diffType} "${result.diff}"');
        }
      }
    }

    logger.printBox('Working directory at `${workingDirectory.path}`');

    checkAndPrintMigrateStatus(manifest, workingDirectory, logger: logger);

    final bool readyToApply = manifest.remainingConflictFiles(workingDirectory).isEmpty;

    if (!readyToApply) {
      logger.printStatus('Guided conflict resolution wizard:');
      printCommandText('flutter migrate resolve-conflicts', logger);
      logger.printStatus('Resolve conflicts and accept changes with:');
    } else {
      logger.printStatus('All conflicts resolved. Review changes above and apply the migration with:', color: TerminalColor.green);
    }
    printCommandText('flutter migrate apply', logger);

    return const FlutterCommandResult(ExitStatus.success);
  }
}
