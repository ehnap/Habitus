import 'dart:math';

import '../model/models.dart';

List<QueueItem> queueFromTap({
  required List<Song> songs,
  required int index,
  required bool shuffle,
  required bool albumGain,
  Random? random,
}) {
  if (index < 0 || index >= songs.length) return const [];
  final rest = songs.sublist(index + 1).toList();
  if (shuffle) rest.shuffle(random ?? Random());
  final useAlbumGain = albumGain && !shuffle;
  return [
    QueueItem(song: songs[index], albumGain: useAlbumGain),
    for (final song in rest) QueueItem(song: song, albumGain: useAlbumGain),
  ];
}

List<QueueItem> queueFromAlbum({
  required List<Song> songs,
  required bool shuffle,
  Random? random,
}) {
  final copy = songs.toList();
  if (shuffle) copy.shuffle(random ?? Random());
  return [for (final song in copy) QueueItem(song: song, albumGain: !shuffle)];
}

List<QueueItem> moveItemToNext(List<QueueItem> items, int current, int from) {
  if (from < 0 || from >= items.length || current < 0 || current >= items.length) {
    return items;
  }
  if (from == current) return items;
  final next = List<QueueItem>.of(items);
  final item = next.removeAt(from);
  var insertAt = current + 1;
  if (from < current) insertAt -= 1;
  if (insertAt < 0) insertAt = 0;
  if (insertAt > next.length) insertAt = next.length;
  next.insert(insertAt, item);
  return next;
}

int indexAfterRemoval(int current, int removed, int lengthAfter) {
  if (lengthAfter <= 0) return 0;
  if (removed < current) return current - 1;
  if (removed == current) return current >= lengthAfter ? lengthAfter - 1 : current;
  return current;
}

bool preferDirectPlay({
  required QualityMode quality,
  required bool cellular,
  required bool phone,
}) {
  switch (quality) {
    case QualityMode.original:
      return true;
    case QualityMode.saver:
      return false;
    case QualityMode.auto:
      if (!phone) return true;
      return !cellular;
  }
}
