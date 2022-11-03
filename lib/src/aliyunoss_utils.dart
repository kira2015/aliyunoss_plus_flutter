import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../aliyunoss_plus_flutter.dart';

// 此文件仅为AliyunOssClient内部使用
extension AliyunOssUtil on AliyunOssClient {
  String requestTime() {
    initializeDateFormatting('en', null);
    final DateTime now = DateTime.now();
    final String string =
        DateFormat('EEE, dd MMM yyyy HH:mm:ss', 'en_ISO').format(now.toUtc());
    return '$string GMT';
  }

  int _calculatePartLength(int length) {
    if (length / 1024 / 1024 < 1000) {
      return 1024 * 1024;
    } else {
      return length ~/ 999;
    }
  }

  ///获取历史上传记录
  Future<AliyunOssPartInfo?> getPartInfo(String id) async {
    String? jsonStr = await keyStoreGet(id);
    AliyunOssPartInfo? partInfo;
    if (jsonStr?.isNotEmpty == true) {
      partInfo = AliyunOssPartInfo.fromJson(jsonStr!);
    }
    return partInfo;
  }

  List<AliyunOssPart> calculateParts(int contentLength) {
    // 计算分片
    List<AliyunOssPart> ossPartList = [];
    int partLength = _calculatePartLength(contentLength);
    for (int i = 0; i < (contentLength ~/ partLength) + 1; i++) {
      final partRangeStart = i * partLength;
      if (partRangeStart < contentLength) {
        final ossPart = AliyunOssPart(
          partNumber: i + 1,
          partRangeStart: partRangeStart,
          partRangeLength: partRangeStart + partLength <= contentLength
              ? partLength
              : contentLength - partRangeStart,
        );
        ossPartList.add(ossPart);
      }
    }
    return ossPartList;
  }

  bool stateCodePass(int? statusCode) {
    return statusCode != null && statusCode >= 200 && statusCode <= 300;
  }

  /// 增加名字后缀
  String addSuffix(String url, String? suffix) {
    if (suffix != null) {
      int lastIndex = url.lastIndexOf(".");
      url = url.substring(0, lastIndex) +
          suffix +
          url.substring(lastIndex, url.length);
    }
    return url;
  }

  Future<bool> keyStoreSave(String key, String value) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return await prefs.setString(key, value);
  }

  Future<String?> keyStoreGet(String key) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  ///签名
  String sign(
      {required Map<String, String> headers,
      required String objectPath,
      required String bucket,
      String httpMethod = "PUT"}) {
    final canonicalizedOSSHeaders = _buildCanonicalizedOSSHander(headers);
    final canonicalizedResource =
        _buildCanonicalizedResource(bucket, objectPath);

    String contentMd5 = headers["content-md5"] ??
        headers["Content-MD5"] ??
        headers["Content-Md5"] ??
        "";
    String contentType =
        headers["content-type"] ?? headers["Content-Type"] ?? "";
    String date = headers["date"] ?? headers["Date"] ?? "";

    final signature = _buildSignature(
      httpMethod: httpMethod,
      contentMd5: contentMd5,
      contentType: contentType,
      date: date,
      canonicalizedOSSHeaders: canonicalizedOSSHeaders,
      canonicalizedResource: canonicalizedResource,
    );

    return 'OSS $accessKeyId:$signature';
  }

  /// 所有以x-oss-为前缀的HTTP Header被称为CanonicalizedOSSHeaders，构建方法如下：
  ///
  /// 将所有以x-oss-为前缀的HTTP请求头的名称转换为小写的形式，例如X-OSS-Meta-Name: TaoBao转换为x-oss-meta-name: TaoBao。
  /// 如果以从STS服务获取的临时访问凭证发送请求时，您还需要将获得的security-token值以x-oss-security-token:security-token的形式加入到签名字符串中。
  /// 将所有HTTP请求头按照名称的字典序进行升序排列。
  /// 删除请求头和内容之间分隔符两端出现的任何空格。例如x-oss-meta-name: TaoBao转换为x-oss-meta-name:TaoBao。
  /// 将每一个请求头和内容使用分隔符\n分隔拼成CanonicalizedOSSHeaders。
  String _buildCanonicalizedOSSHander(Map<String, String>? headers) {
    final securityHeaders = {
      if (headers != null) ...headers,
      'x-oss-security-token': securityToken,
    };
    final sortedHeaders = _sortByLowerKey(securityHeaders);
    return sortedHeaders
        .where((e) => e.key.startsWith('x-oss-'))
        .map((e) => '${e.key}:${e.value}')
        .join('\n');
  }

  /// 用户发送请求中想访问的OSS目标资源被称为CanonicalizedResource，构建方法如下：
  /// 设置要访问的OSS资源，格式为/BucketName/ObjectName。
  /// 如果仅有BucketName而没有ObjectName，则CanonicalizedResource为”/BucketName/“。
  /// 如果既没有BucketName也没有ObjectName，则CanonicalizedResource为“/”。
  String _buildCanonicalizedResource(String bucketName, String objectName) {
    if (bucketName.isEmpty && objectName.isEmpty) {
      return "/";
    }
    return '/$bucketName/$objectName';
  }

  /// Signature = base64(hmac-sha1(AccessKeySecret,
  ///             VERB + "\n"
  ///             + Content-MD5 + "\n"
  ///             + Content-Type + "\n"
  ///             + Date + "\n"
  ///             + CanonicalizedOSSHeaders
  ///             + CanonicalizedResource))
  String _buildSignature({
    required String httpMethod,
    required String contentMd5,
    required String contentType,
    required String date,
    required String canonicalizedOSSHeaders,
    required String canonicalizedResource,
  }) {
    final canonicalizedString = [
      httpMethod,
      contentMd5,
      contentType,
      date,
      canonicalizedOSSHeaders,
      canonicalizedResource,
    ].join('\n');

    final digest = Hmac(sha1, utf8.encode(accessKeySecret))
        .convert(utf8.encode(canonicalizedString));
    return base64.encode(digest.bytes);
  }

  List<MapEntry<String, String>> _sortByLowerKey(Map<String, String> map) {
    final lowerPairs = map.entries.map(
        (e) => MapEntry(e.key.toLowerCase().trim(), e.value.toString().trim()));
    return lowerPairs.toList()..sort((a, b) => a.key.compareTo(b.key));
  }
}
