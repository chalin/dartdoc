// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library dartdoc;

import 'dart:io';

import 'package:analyzer/src/generated/ast.dart';
import 'package:analyzer/src/generated/element.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/java_io.dart';
import 'package:analyzer/src/generated/sdk.dart';
import 'package:analyzer/src/generated/sdk_io.dart';
import 'package:analyzer/src/generated/source_io.dart';

import 'generator.dart';
import 'src/html_generator.dart';
import 'src/io_utils.dart';
import 'src/model.dart';
import 'src/model_utils.dart';

const String DEFAULT_OUTPUT_DIRECTORY = 'docs';

const String NAME = 'dartdoc';

// Update when puspec version changes
const String VERSION = '0.0.1';


/// Initialize and setup the generators
List<Generator> initGenerators(String url) {
  List<Generator> generators = [];
  generators.add(new HtmlGenerator(url));
  return generators;
}

/// Generates Dart documentation for all public Dart libraries in the given
/// directory.
class DartDoc {
  List<String> _excludes;
  Directory _rootDir;
  Directory out;
  Directory _sdkDir;
  bool _sdkDocs;
  Set<LibraryElement> libraries = new Set();
  List<Generator> _generators;

  DartDoc(this._rootDir, this._excludes, this._sdkDir, this._generators, [this._sdkDocs = false]);

  /// Generate the documentation
  void generateDocs() {
    Stopwatch stopwatch = new Stopwatch();
    stopwatch.start();

    var files = _sdkDocs ? [] : findFilesToDocumentInPackage(_rootDir.path);
    List<LibraryElement> libs = [];
    libs.addAll(_parseLibraries(files));
    // remove excluded libraries
    _excludes.forEach((pattern) => libs.removeWhere((l) => l.name.startsWith(pattern)));
    libs.removeWhere((LibraryElement library) => _excludes.contains(library.name));
    libs.sort(elementCompare);
    libraries.addAll(libs);

    // create the out directory
    out = new Directory(DEFAULT_OUTPUT_DIRECTORY);
    if (!out.existsSync()) {
      out.createSync(recursive: true);
    }
    Package package = new Package(libraries, _rootDir.path, _sdkDocs);
    _generators.forEach((generator) => generator.generate(package, out));

    double seconds = stopwatch.elapsedMilliseconds / 1000.0;
    print('');
    print("Documented ${libraries.length} " "librar${libraries.length == 1 ? 'y' : 'ies'} in " "${seconds.toStringAsFixed(1)} seconds.");
  }

  List<LibraryElement> _parseLibraries(List<String> files) {
    DartSdk sdk = new DirectoryBasedDartSdk(new JavaFile(_sdkDir.path));
    ContentCache contentCache = new ContentCache();
    List<UriResolver> resolvers = [new DartUriResolver(sdk), new FileUriResolver()];
    JavaFile packagesDir = new JavaFile.relative(new JavaFile(_rootDir.path), 'packages');
    if (packagesDir.exists()) {
      resolvers.add(new PackageUriResolver([packagesDir]));
    }
    SourceFactory sourceFactory = new SourceFactory(/*contentCache,*/ resolvers);
    AnalysisContext context = AnalysisEngine.instance.createAnalysisContext();
    context.sourceFactory = sourceFactory;

    if (_sdkDocs) {
      var sdkApiLibs =
          sdk.sdkLibraries.where((SdkLibrary sdkLib)
              => !sdkLib.isInternal && sdkLib.isDocumented).toList();
      sdkApiLibs.sort((lib1, lib2) => lib1.shortName.compareTo(lib2.shortName));
      sdkApiLibs
           .forEach((SdkLibrary sdkLib) {
              Source source = sdk.mapDartUri(sdkLib.shortName);
              LibraryElement library = context.computeLibraryElement(source);
              CompilationUnit unit = context.resolveCompilationUnit(source, library);
              libraries.add(library);
              libraries.addAll(library.exportedLibraries);
            });
    }
    files.forEach((String filePath) {
      print('parsing ${filePath}...');
      Source source = new FileBasedSource.con1(new JavaFile(filePath));
      if (context.computeKindOf(source) == SourceKind.LIBRARY) {
        LibraryElement library = context.computeLibraryElement(source);
        CompilationUnit unit = context.resolveCompilationUnit(source, library);
        libraries.add(library);
        libraries.addAll(library.exportedLibraries);
      }
    });
    return libraries.toList();
  }
}
