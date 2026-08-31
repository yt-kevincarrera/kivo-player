/// Builds the file name a captured frame is saved under.
///
/// The instant is part of the name, so capturing the same video twice only
/// collides if it happens twice within the same second. Minutes and seconds
/// are zero-padded so a folder of captures from one video sorts in the order
/// they occur, which a gallery's name sort then gets right for free.
String captureFileName(String videoName, Duration at) {
  final dot = videoName.lastIndexOf('.');
  // A leading dot is a hidden file, not an extension, so only split on a dot
  // that has something before it.
  final base = dot > 0 ? videoName.substring(0, dot) : videoName;

  final hours = at.inHours;
  final minutes = at.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = at.inSeconds.remainder(60).toString().padLeft(2, '0');
  final stamp = hours > 0 ? '${hours}h${minutes}m${seconds}s' : '${minutes}m${seconds}s';

  return '$base — $stamp.jpg';
}
