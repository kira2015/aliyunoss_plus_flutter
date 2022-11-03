import 'dart:convert';


/// 阿里云分片信息
class AliyunOssPartInfo {
  late String bucket;
  late String endpoint;
  String? domain;
  late String objectPath;
  late String filePath;
  late String uploadId;

  /// 读取文件名字时添加后缀: xxx.mp4->xxx${fileNameSuffix}.mp4
  String? fileNameSuffix;
  late int progress;
  late int total;
  List<AliyunOssPart> parts = [];
  AliyunOssPartInfo(
      {required this.bucket,
      required this.endpoint,
      this.domain,
      required this.objectPath,
      required this.filePath,
      required this.uploadId,
      this.progress = 0,
      required this.total,
      this.fileNameSuffix});
  String toEncodeString() {
    return json.encode({
      "bucket": bucket,
      "endpoint": endpoint,
      "domain": domain,
      "objectPath": objectPath,
      "filePath": filePath,
      "uploadId": uploadId,
      "progress": progress,
      "total": total,
      "parts": parts.map((e) => e.toEncodeString()).toList(),
      "fileNameSuffix": fileNameSuffix
    });
  }

  AliyunOssPartInfo.fromJson(String jsonStr) {
    Map<String, dynamic> map = json.decode(jsonStr);
    bucket = map["bucket"];
    endpoint = map["endpoint"];
    domain = map["domain"];
    objectPath = map["objectPath"];
    filePath = map["filePath"];
    uploadId = map["uploadId"];
    progress = map["progress"] ?? 0;
    total = map["total"];
    parts =
        (map["parts"] as List).map((e) => AliyunOssPart.fromJson(e)).toList();
    fileNameSuffix = map["fileNameSuffix"];
  }
  @override
  String toString() => "AliyunOssPartInfo(${toEncodeString()})";
}

class AliyunOssPart {
  late int partNumber;
  late int partRangeStart;
  late int partRangeLength;
  late String? partETag;

  AliyunOssPart({
    required this.partNumber,
    required this.partRangeStart,
    required this.partRangeLength,
    this.partETag,
  });
  String toEncodeString() {
    return json.encode({
      "partNumber": partNumber,
      "partRangeStart": partRangeStart,
      "partRangeLength": partRangeLength,
      "partETag": partETag,
    });
  }

  AliyunOssPart.fromJson(String jsonStr) {
    Map<String, dynamic> map = json.decode(jsonStr);
    partNumber = map["partNumber"];
    partRangeStart = map["partRangeStart"];
    partRangeLength = map["partRangeLength"];
    partETag = map["partETag"];
  }
  @override
  String toString() {
    return "partNumber:$partNumber,partRangeStart:$partRangeStart,partRangeLength:$partRangeLength,partETag:$partETag";
  }
}
