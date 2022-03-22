// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';

import '../base/file_system.dart';
import '../base/logger.dart';
import '../base/terminal.dart';
import '../cache.dart';
import '../commands/migrate.dart';
import '../flutter_project_metadata.dart';
import '../globals.dart' as globals;
import '../project.dart';
import '../runner/flutter_command.dart';
import '../version.dart';
import 'custom_merge.dart';
import 'migrate_manifest.dart';
import 'migrate_utils.dart';

// This defines files and directories that should be skipped regardless
// of gitignore and config settings
const List<String> _skippedFiles = const <String>[
  'lib/main.dart',
  'ios/Runner.xcodeproj/project.pbxproj'
  'README.md', // changes to this shouldn't be overwritten since is is user owned.
];

const List<String> _skippedDirectories = const <String>[
  '.dart_tool', // ignore the .dart_tool generated dir
  '.git', // ignore the git metadata
  'lib', // Files here are always user owned and we don't want to overwrite their apps.
  'test', // Files here are typically user owned and flutter-side changes are not relevant.
  'assets', // Common directory for user assets.
];

bool _skipped(String localPath) {
  if (_skippedFiles.contains(localPath)) {
    return true;
  }
  for (String dir in _skippedDirectories) {
    if (localPath.startsWith('$dir/')) {
      return true;
    }
  }
  return false;
}

const List<String> _skippedMergeFileExt = const <String>[
  // Don't merge image files
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
];

/// True for files that should not be merged. Typically, images and binary files.
bool _skippedMerge(String localPath) {
  for (String ext in _skippedMergeFileExt) {
    if (localPath.endsWith(ext)) {
      return true;
    }
  }
  return false;
}

/// Stores a file that has been marked for migraton and metadata about the file.
class FilePendingMigration {
  FilePendingMigration(this.localPath, this.file);
  String localPath;
  File file;
}

/// Data class that holds all results and generated directories from a computeMigration run.
///
/// mergeResults, addedFiles, and deletedFiles includes the sets of files to be migrated while
/// the other members track the temporary sdk and generated app directories created by the tool.
///
/// The compute function does not clean up the temp directories, as the directories may be reused,
/// so this must be done manually afterwards.
class MigrateResult {
  MigrateResult({
    required this.mergeResults,
    required this.addedFiles,
    required this.deletedFiles,
    required this.tempDirectories,
    required this.sdkDirs,
    this.generatedBaseTemplateDirectory,
    this.generatedTargetTemplateDirectory});

  /// Creates a MigrateResult with all empty members.
  MigrateResult.empty()
    : mergeResults = <MergeResult>[],
      addedFiles = <FilePendingMigration>[],
      deletedFiles = <FilePendingMigration>[],
      tempDirectories = <Directory>[],
      sdkDirs = <String, Directory>{};

  final List<MergeResult> mergeResults;
  final List<FilePendingMigration> addedFiles;
  final List<FilePendingMigration> deletedFiles;
  final List<Directory> tempDirectories;
  Directory? generatedBaseTemplateDirectory;
  Directory? generatedTargetTemplateDirectory;
  Map<String, Directory> sdkDirs;
}

/// Computes the changes that migrates the current flutter project to the target revision.
///
/// This method attempts to find a base revision, which is the revision of the Flutter SDK
/// the app was generated with or the last revision the app was migrated to. The base revision
/// typically comes from the .migrate_config, but for legacy apps, the config may not exist. In
/// this case, we fallback to using the revision in .metadata, and if that does not exist, we
/// use the target revision as the base revision. In the final fallback case, the migration should
/// still work, but will likely generate slightly more conflicts rather than merges.
///
/// Operations the computation performs:
/// 
///  - Parse .migrate_config files
///  - Collect revisions to use for each platform
///  - Download each flutter revision and call `flutter create` for each.
///  - Call `flutter create` with target revision (target is typically current flutter version)
///  - Diff base revision generated app with target revision generated app
///  - Compute all newly added files between base and target revisions
///  - Compute 3 way merge of all files that are modifed by user and flutter
///  - Track temp dirs to be deleted
Future<MigrateResult?> computeMigration({
    bool verbose = false,
    FlutterProject? flutterProject,
    String? baseAppPath,
    String? targetAppPath,
    String? baseRevision,
    String? targetRevision,
    bool deleteTempDirectories = true,
    List<SupportedPlatform>? platforms,
    Logger? logger,
  }) async {
  if (logger == null) {
    logger = globals.logger;
  }
  final Directory workingDir = FlutterProject.current().directory.childDirectory(kDefaultMigrateWorkingDirectoryName);
  if (workingDir.existsSync()) {
    logger.printStatus('Old migration already in progress.', emphasis: true);
    logger.printStatus('Pending migration files exist in `<your_project_root_dir>/$kDefaultMigrateWorkingDirectoryName`');
    logger.printStatus('Resolve merge conflicts and accept changes with by running:\n');
    logger.printStatus('\$ flutter migrate apply\n', color: TerminalColor.grey, indent: 4);
    logger.printStatus('You may also abandon the existing migration and start a new one with:\n');
    logger.printStatus('\$ flutter migrate abandon', color: TerminalColor.grey, indent: 4);
    return null;
  }
  if (flutterProject == null) {
    flutterProject = FlutterProject.current();
  }
  final Status statusTicker = logger.startProgress('Computing migration');

  final FlutterProjectMetadata metadata = FlutterProjectMetadata(flutterProject.directory.childFile('.metadata'), logger);
  final MigrateConfig config = metadata.migrateConfig;

  // We call populate in case MigrateConfig is empty. If it is filled, populate should not do anything.
  config.populate(
    projectDirectory: flutterProject.directory,
    logger: logger,
  );
  final String fallbackRevision = await getFallbackBaseRevision(metadata, FlutterVersion(workingDirectory: flutterProject.directory.absolute.path));
  String rootBaseRevision = '';
  final Map<String, List<MigratePlatformConfig>> revisionToConfigs = <String, List<MigratePlatformConfig>>{};
  final Set<String> revisions = Set<String>();
  if (baseRevision == null) {
    print(config.platformConfigs.keys);
    for (final MigratePlatformConfig platform in config.platformConfigs.values) {
      String effectiveRevision = platform.baseRevision == null ? fallbackRevision : platform.baseRevision!;
      if (platform.platform == SupportedPlatform.root) {
        rootBaseRevision = effectiveRevision;
      }
      revisions.add(effectiveRevision);
      if (revisionToConfigs[effectiveRevision] == null) {
        revisionToConfigs[effectiveRevision] = <MigratePlatformConfig>[];
      }
      revisionToConfigs[effectiveRevision]!.add(platform);
    }
  } else {
    rootBaseRevision = baseRevision;
  }
  // Reorder such that the root revision is created first.
  revisions.remove(rootBaseRevision);
  final List<String> revisionsList = List<String>.from(revisions);
  if (rootBaseRevision != '') {
    revisionsList.insert(0, rootBaseRevision);
  }
  if (verbose) logger.printStatus('Potential base revisions: $revisionsList');

  // Extract the files/paths that should be ignored by the migrate tool.
  // These paths are absolute paths.
  if (verbose) logger.printStatus('Parsing unmanagedFiles.');
  final List<String> unmanagedFiles = <String>[];
  final List<String> unmanagedDirectories = <String>[];
  final String basePath = flutterProject.directory.path;
  for (String localPath in config.unmanagedFiles) {
    if (localPath.endsWith(globals.fs.path.separator)) {
      unmanagedDirectories.add(globals.fs.path.join(basePath, localPath));
    } else {
      unmanagedFiles.add(globals.fs.path.join(basePath, localPath));
    }
  }

  final MigrateResult migrateResult = MigrateResult.empty();

  // Generate the base templates
  final bool customBaseAppDir = baseAppPath != null;
  final bool customTargetAppDir = targetAppPath != null;
  if (customBaseAppDir) {
    migrateResult.generatedBaseTemplateDirectory = globals.fs.directory(baseAppPath);
  } else {
    migrateResult.generatedBaseTemplateDirectory = await MigrateUtils.createTempDirectory('generatedBaseTemplate');
  }
  if (customTargetAppDir) {
    migrateResult.generatedTargetTemplateDirectory = globals.fs.directory(targetAppPath);
  } else {
    migrateResult.generatedTargetTemplateDirectory = await MigrateUtils.createTempDirectory('generatedTargetTemplate');
  }

  await MigrateUtils.gitInit(migrateResult.generatedBaseTemplateDirectory!.absolute.path);
  await MigrateUtils.gitInit(migrateResult.generatedTargetTemplateDirectory!.absolute.path);

  // Create base
  final String name = flutterProject.manifest.appName;
  final String androidLanguage = flutterProject.android.isKotlin ? 'kotlin' : 'java';
  final String iosLanguage = flutterProject.ios.isSwift ? 'swift' : 'objc';

  Directory targetFlutterDirectory = globals.fs.directory(Cache.flutterRoot!);
  // Clone base flutter
  final List<Directory> sdkTempDirs = <Directory>[];
  if (verbose) logger.printStatus('Creating base app.');
  if (baseAppPath == null) {
    final Map<String, Directory> revisionToFlutterSdkDir = <String, Directory>{};
    for (String revision in revisionsList) {
      final List<String> platforms = <String>[];
      for (final MigratePlatformConfig config in revisionToConfigs[revision]!) {
        platforms.add(config.platform.toString().split('.').last);
      }
      platforms.remove('root'); // Root does not need to be listed and is not a valid platform

      // In the case of the revision being invalid or not a hash of the master branch,
      // we want to fallback in the following order:
      //   - parsed revision
      //   - fallback revision
      //   - target revision (currently installed flutter)
      late Directory sdkDir;
      final List<String> revisionsToTry = <String>[revision];
      if (revision != fallbackRevision) {
        revisionsToTry.add(fallbackRevision);
      }
      bool sdkAvailable = false;
      int index = 0;
      do {
        if (index < revisionsToTry.length) {
          final String activeRevision = revisionsToTry[index++];
          if (activeRevision != revision && revisionToFlutterSdkDir.containsKey(activeRevision)) {
            sdkDir = revisionToFlutterSdkDir[activeRevision]!;
            revisionToFlutterSdkDir[revision] = sdkDir;
            sdkAvailable = true;
          } else {
            sdkDir = await MigrateUtils.createTempDirectory('flutter_$activeRevision');
            migrateResult.sdkDirs[activeRevision] = sdkDir;
            sdkAvailable = await MigrateUtils.cloneFlutter(activeRevision, sdkDir.absolute.path);
            revisionToFlutterSdkDir[revision] = sdkDir;
          }
        } else {
          // fallback to just using the modern target version of flutter.
          sdkDir = targetFlutterDirectory;
          revisionToFlutterSdkDir[revision] = sdkDir;
          sdkAvailable = true;
        }
      } while (!sdkAvailable);
      if (verbose) logger.printStatus('SDK cloned for revision $revision in ${sdkDir.path}');
      await MigrateUtils.createFromTemplates(
        sdkDir.childDirectory('bin').absolute.path,
        name: name,
        androidLanguage: androidLanguage,
        iosLanguage: iosLanguage,
        outputDirectory: migrateResult.generatedBaseTemplateDirectory!.absolute.path,
        platforms: platforms,
      );
      if (verbose) logger.printStatus('Creating base app for platforms $platforms with $revision SDK.');
    }
  }

  if (targetAppPath == null) {
    // Create target
    if (verbose) logger.printStatus('Creating target app.');
    await MigrateUtils.createFromTemplates(
      targetFlutterDirectory.childDirectory('bin').absolute.path,
      name: name,
      androidLanguage: androidLanguage,
      iosLanguage: iosLanguage,
      outputDirectory: migrateResult.generatedTargetTemplateDirectory!.absolute.path
    );
  }

  await MigrateUtils.gitInit(flutterProject.directory.absolute.path);

  // Generate diffs. These diffs are used to determine if a file is newly added, needs merging, or deleted (rare).
  if (verbose) logger.printStatus('Diffing base app and target app.');
  final List<FileSystemEntity> generatedBaseFiles = migrateResult.generatedBaseTemplateDirectory!.listSync(recursive: true);
  final List<FileSystemEntity> generatedTargetFiles = migrateResult.generatedTargetTemplateDirectory!.listSync(recursive: true);
  int modifiedFilesCount = 0;
  final Map<String, DiffResult> diffMap = <String, DiffResult>{};
  for (final FileSystemEntity entity in generatedBaseFiles) {
    if (entity is! File) {
      continue;
    }
    final File baseTemplateFile = (entity as File).absolute;
    if (!baseTemplateFile.path.startsWith(migrateResult.generatedBaseTemplateDirectory!.absolute.path)) {
      continue;
    }
    final String localPath = baseTemplateFile.path.replaceFirst(migrateResult.generatedBaseTemplateDirectory!.absolute.path + globals.fs.path.separator, '');
    if (_skipped(localPath)) {
      continue;
    }
    if (await MigrateUtils.isGitIgnored(baseTemplateFile.absolute.path, migrateResult.generatedBaseTemplateDirectory!.absolute.path)) {
      diffMap[localPath] = DiffResult.ignored();
    }
    final File targetTemplateFile = migrateResult.generatedTargetTemplateDirectory!.childFile(localPath);
    if (targetTemplateFile.existsSync()) {
      DiffResult diff = await MigrateUtils.diffFiles(baseTemplateFile, targetTemplateFile);
      diffMap[localPath] = diff;
      if (verbose && diff.diff != '') {
        logger.printStatus('  Found ${diff.exitCode} changes in $localPath ');
        modifiedFilesCount++;
      }
    } else {
      // Current file has no new template counterpart, which is equivalent to a deletion.
      // This could also indicate a renaming if there is an addition with equivalent contents.
      diffMap[localPath] = DiffResult.deletion();
    }
  }
  if (verbose) logger.printStatus('$modifiedFilesCount files were modified between base and target apps.');

  // Check for any new files that were added in the new template
  for (final FileSystemEntity entity in generatedTargetFiles) {
    if (entity is! File) {
      continue;
    }
    final File targetTemplateFile = (entity as File).absolute;
    if (!targetTemplateFile.path.startsWith(migrateResult.generatedTargetTemplateDirectory!.absolute.path)) {
      continue;
    }
    String localPath = targetTemplateFile.path.replaceFirst(migrateResult.generatedTargetTemplateDirectory!.absolute.path + globals.fs.path.separator, '');
    if (diffMap.containsKey(localPath) || _skipped(localPath)) {
      continue;
    }
    if (await MigrateUtils.isGitIgnored(targetTemplateFile.absolute.path, migrateResult.generatedTargetTemplateDirectory!.absolute.path)) {
      diffMap[localPath] = DiffResult.ignored();
    }
    diffMap[localPath] = DiffResult.addition();
    migrateResult.addedFiles.add(FilePendingMigration(localPath, targetTemplateFile));
  }
  if (verbose) logger.printStatus('${migrateResult.addedFiles.length} files were newly added in the target app.');

  final List<CustomMerge> customMerges = <CustomMerge>[
    MetadataCustomMerge(logger: logger),
  ];

  // For each existing file in the project, we attampt to 3 way merge if it is changed by the user.
  final List<FileSystemEntity> currentFiles = flutterProject.directory.listSync(recursive: true);
  final String projectRootPath = flutterProject.directory.absolute.path;
  for (final FileSystemEntity entity in currentFiles) {
    if (entity is! File) {
      continue;
    }
    // check if the file is unmanaged/ignored by the migration tool.
    bool ignored = false;
    ignored = unmanagedFiles.contains(entity.absolute.path);
    for (String path in unmanagedDirectories) {
      if (entity.absolute.path.startsWith(path)) {
        ignored = true;
        break;
      }
    }
    if (ignored) {
      continue; // Skip if marked as unmanaged
    }

    final File currentFile = (entity as File).absolute;
    if (!currentFile.path.startsWith(projectRootPath)) {
      continue; // Not a project file.
    }
    // Diff the current file against the old generated template
    final String localPath = currentFile.path.replaceFirst(projectRootPath + globals.fs.path.separator, '');
    if (diffMap.containsKey(localPath) && diffMap[localPath]!.isIgnored ||
        await MigrateUtils.isGitIgnored(currentFile.path, flutterProject.directory.absolute.path) ||
        _skipped(localPath) ||
        _skippedMerge(localPath)) {
      continue;
    }
    final File baseTemplateFile = migrateResult.generatedBaseTemplateDirectory!.childFile(localPath);
    final File targetTemplateFile = migrateResult.generatedTargetTemplateDirectory!.childFile(localPath);
    final DiffResult userDiff = await MigrateUtils.diffFiles(baseTemplateFile, currentFile);

    if (userDiff.exitCode == 0) {
      // Current file unchanged by user
      if (diffMap.containsKey(localPath)) {
        if (diffMap[localPath]!.isDeletion) {
          // File is deleted in new template
          migrateResult.deletedFiles.add(FilePendingMigration(localPath, currentFile));
        }
        if (diffMap[localPath]!.exitCode != 0) {
          // Accept the target version wholesale
          MergeResult result;
          try {
            result = MergeResult.explicit(
              mergedString: targetTemplateFile.readAsStringSync(),
              hasConflict: false,
              exitCode: 0,
              localPath: localPath,
            );
          } on FileSystemException {
            result = MergeResult.explicit(
              mergedBytes: targetTemplateFile.readAsBytesSync(),
              hasConflict: false,
              exitCode: 0,
              localPath: localPath,
            );
          }
          migrateResult.mergeResults.add(result);
          continue;
        }
      }
      continue;
    }

    if (diffMap.containsKey(localPath)) {
      MergeResult? result;
      for (final CustomMerge customMerge in customMerges) {
        if (customMerge.localPath == localPath) {
          result = customMerge.merge(currentFile, baseTemplateFile, targetTemplateFile);
          break;
        }
      }
      if (result == null) {
        result = await MigrateUtils.gitMergeFile(
          ancestor: globals.fs.path.join(migrateResult.generatedBaseTemplateDirectory!.path, localPath),
          current: currentFile.path,
          other: globals.fs.path.join(migrateResult.generatedTargetTemplateDirectory!.path, localPath),
          localPath: localPath,
        );
      }
      migrateResult.mergeResults.add(result);
      if (verbose) logger.printStatus('$localPath was merged.');
      continue;
    }
  }

  if (deleteTempDirectories) {
    // Don't delete user-provided directories
    if (!customBaseAppDir) {
      migrateResult.tempDirectories.add(migrateResult.generatedBaseTemplateDirectory!);
    }
    if (!customTargetAppDir) {
      migrateResult.tempDirectories.add(migrateResult.generatedTargetTemplateDirectory!);
    }
    migrateResult.tempDirectories.addAll(migrateResult.sdkDirs.values);
  }
  return migrateResult;
}

String getFallbackBaseRevision(FlutterProjectMetadata metadata, FlutterVersion version) {
  if (metadata.versionRevision != null) {
    return metadata.versionRevision!;
  }
  return version.frameworkRevision;
}

/// Writes the files into the working directory for the developer to review and resolve any conflicts.
Future<void> writeWorkingDir(MigrateResult migrateResult, {bool verbose = false, FlutterProject? flutterProject}) async {
  if (flutterProject == null) {
    flutterProject = FlutterProject.current();
  }
  final Directory workingDir = FlutterProject.current().directory.childDirectory(kDefaultMigrateWorkingDirectoryName);
  if (verbose) globals.logger.printStatus('Writing migrate working directory at `${workingDir.path}`');
  // Write files in working dir
  for (final MergeResult result in migrateResult.mergeResults) {
    final File file = workingDir.childFile(result.localPath);
    file.createSync(recursive: true);
    if (result.mergedString != null) {
      file.writeAsStringSync(result.mergedString!, flush: true);
    } else {
      file.writeAsBytesSync(result.mergedBytes!, flush: true);
    }
  }

  for (final FilePendingMigration addedFile in migrateResult.addedFiles) {
    final File file = workingDir.childFile(addedFile.localPath);
    file.createSync(recursive: true);
    try {
      file.writeAsStringSync(addedFile.file.readAsStringSync(), flush: true);
    } on FileSystemException {
      file.writeAsBytesSync(addedFile.file.readAsBytesSync(), flush: true);
    }
  }

  final MigrateManifest manifest = MigrateManifest(
    migrateRootDir: workingDir,
    migrateResult: migrateResult,
  );
  manifest.writeFile();

  globals.logger.printBox('Working directory created at `${workingDir.path}`');

  checkAndPrintMigrateStatus(manifest, workingDir);
}
