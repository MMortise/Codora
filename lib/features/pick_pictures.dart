import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import '../core/util.dart';

/// One picture the reader chose, already in hand.
typedef PickedPicture = ({String name, Uint8List bytes});

/// Asks for pictures to put in a post. Empty when the reader picked none.
///
/// Read here rather than handed on as a path: a picture goes to a forum
/// through the WebView the rest of the site is read in, which has no way to
/// reach into the file system — and on macOS the permission to read what was
/// picked belongs to the picking, not to the app.
Future<List<PickedPicture>> pickPictures() async {
  final files = await openFiles(
    acceptedTypeGroups: [
      XTypeGroup(label: '图片', extensions: kPictureTypes.keys.toList()),
    ],
    confirmButtonText: '插入',
  );
  return [
    for (final file in files) (name: file.name, bytes: await file.readAsBytes()),
  ];
}
