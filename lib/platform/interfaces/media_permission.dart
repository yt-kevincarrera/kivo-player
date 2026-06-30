enum MediaAccess { granted, denied, limited }

abstract class MediaPermission {
  Future<MediaAccess> status();
  Future<MediaAccess> request();
}
